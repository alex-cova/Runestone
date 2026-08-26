@preconcurrency import AppKit
import Foundation

/// A miniature overview of the document rendered along the trailing edge of the text view,
/// similar to the minimap in Xcode, VS Code, and CodeEditSourceEditor. Each line is drawn as a
/// small horizontal bar approximating the line's length; a draggable box shows which portion of
/// the document is currently visible in the main editor, and dragging it — or clicking elsewhere
/// in the minimap — scrolls the editor.
///
/// The minimap does not typeset or render real glyphs. It only reads each line's cached length
/// (`DocumentLineNode.data.length`, an O(1) property already maintained by the line manager's
/// red-black tree), so drawing it is cheap regardless of document size.
///
/// Every source line maps to a fixed-height row (``rowHeight``). For documents whose minimap
/// content would be taller than the minimap's own bounds, the minimap's drawn content scrolls in
/// lock-step with the editor (see `minimapContentOffsetY`) rather than compressing every line
/// into the available height — the same behavior as the minimaps in the editors above, where a
/// visible row always represents exactly one source line. This also means `draw(_:)` only ever
/// has to iterate the rows visible within the minimap's own (small, fixed) bounds — at most
/// `bounds.height / rowHeight` of them — regardless of how many lines the document has, so unlike
/// the main editor's gutter this view doesn't need dirty-rect-scoped redraws to stay cheap.
final class MinimapView: UIView {
    /// Source of line/string data this minimap reflects. Not owned by the minimap.
    weak var lineDataSource: TextInputView?
    /// The scroll view whose `contentOffset`/`contentSize` this minimap reflects and controls.
    weak var scrollView: TextView?
    /// Called before the minimap changes `scrollView.contentOffset` from a click or drag.
    var onUserScroll: (() -> Void)?

    /// Height, in points, of each line's row.
    var rowHeight: CGFloat = 3
    /// Width, in points, allotted per character when drawing a line's bar.
    var characterWidth: CGFloat = 1
    /// Horizontal inset before the first bar.
    var leadingInset: CGFloat = 4
    /// Longest line length, in characters, a bar will be drawn to represent. Longer lines are
    /// capped so a single very long line (e.g. a minified file) doesn't dominate the minimap.
    var maximumLineLength = 200

    private let hairlineView = UIView()
    private let viewportIndicatorView = UIView()
    private var isDraggingIndicator = false
    private var dragStartLocalY: CGFloat = 0
    private var dragStartContentOffsetY: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        viewportIndicatorView.wantsLayer = true
        viewportIndicatorView.layer?.cornerRadius = 3
        viewportIndicatorView.layer?.borderWidth = 1
        addSubview(hairlineView)
        addSubview(viewportIndicatorView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hairlineView.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
        layoutViewportIndicator()
    }

    override func draw(_ dirtyRect: CGRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext, let lineDataSource else {
            return
        }
        let lineManager = lineDataSource.lineManager
        let lineCount = lineManager.lineCount
        guard lineCount > 0 else {
            return
        }
        context.setFillColor(lineDataSource.theme.textColor.withAlphaComponent(0.45).cgColor)
        let offsetY = minimapContentOffsetY
        let firstRow = max(0, Int(floor((dirtyRect.minY + offsetY) / rowHeight)))
        let lastRow = min(lineCount - 1, Int(ceil((dirtyRect.maxY + offsetY) / rowHeight)))
        guard firstRow <= lastRow else {
            return
        }
        for row in firstRow ... lastRow {
            let line = lineManager.line(atRow: row)
            let length = min(line.data.length, maximumLineLength)
            guard length > 0 else {
                continue
            }
            let width = CGFloat(length) * characterWidth
            let y = CGFloat(row) * rowHeight - offsetY
            context.fill(CGRect(x: leadingInset, y: y, width: width, height: max(rowHeight - 1, 1)))
        }
    }

    /// Applies the current theme's colors to the minimap's chrome (background, hairline, and
    /// viewport indicator). The line bars themselves are colored directly in `draw(_:)` since
    /// they're redrawn far more often than the theme changes.
    func applyTheme() {
        guard let theme = lineDataSource?.theme else {
            return
        }
        backgroundColor = theme.gutterBackgroundColor
        hairlineView.backgroundColor = theme.gutterHairlineColor
        viewportIndicatorView.backgroundColor = theme.selectionColor.withAlphaComponent(0.25)
        applyViewportIndicatorBorderColor(theme: theme)
        setNeedsDisplayForContentChange()
    }

    /// `viewportIndicatorView.layer?.borderColor` isn't a `UIView.backgroundColor`, so it isn't
    /// covered by `UIView.viewDidChangeEffectiveAppearance()`'s re-bake — re-apply it here too, on
    /// both theme changes and effective-appearance changes.
    private func applyViewportIndicatorBorderColor(theme: Theme) {
        viewportIndicatorView.layer?.borderColor = theme.selectionColor.withAlphaComponent(0.6).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let theme = lineDataSource?.theme {
            applyViewportIndicatorBorderColor(theme: theme)
        }
    }

    /// Call whenever the document's content, scroll position, or size changes.
    func setNeedsDisplayForContentChange() {
        needsDisplay = true
        layoutViewportIndicator()
    }

    // MARK: - Scroll <-> minimap mapping

    private var minimapContentHeight: CGFloat {
        CGFloat(max(lineDataSource?.lineManager.lineCount ?? 0, 1)) * rowHeight
    }
    private var mainContentHeight: CGFloat {
        max(scrollView?.contentSize.height ?? 1, 1)
    }
    private var mainViewportHeight: CGFloat {
        max(scrollView?.bounds.height ?? 0, 0)
    }
    private var mainScrollableRange: CGFloat {
        max(mainContentHeight - mainViewportHeight, 0)
    }
    private var minimapScrollableRange: CGFloat {
        max(minimapContentHeight - bounds.height, 0)
    }
    /// The minimap's own virtual scroll offset — how far its drawn content is scrolled to keep
    /// the indicator visible, derived directly from the editor's scroll position. The minimap
    /// has no independent scroll state of its own; this is always a pure function of
    /// `scrollView.contentOffset.y`.
    private var minimapContentOffsetY: CGFloat {
        guard mainScrollableRange > 0 else {
            return 0
        }
        let progress = min(max((scrollView?.contentOffset.y ?? 0) / mainScrollableRange, 0), 1)
        return progress * minimapScrollableRange
    }

    private func layoutViewportIndicator() {
        guard mainContentHeight > 0, mainViewportHeight > 0 else {
            viewportIndicatorView.isHidden = true
            return
        }
        let scale = minimapContentHeight / mainContentHeight
        let indicatorHeight = min(bounds.height, mainViewportHeight * scale)
        let indicatorY = (scrollView?.contentOffset.y ?? 0) * scale - minimapContentOffsetY
        viewportIndicatorView.isHidden = false
        viewportIndicatorView.frame = CGRect(x: 0, y: indicatorY, width: bounds.width, height: max(indicatorHeight, 4))
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if viewportIndicatorView.frame.contains(point) {
            isDraggingIndicator = true
            dragStartLocalY = point.y
            dragStartContentOffsetY = scrollView?.contentOffset.y ?? 0
        } else {
            isDraggingIndicator = false
            scrollToContent(atLocalY: point.y, centered: true)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingIndicator else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let deltaLocalY = point.y - dragStartLocalY
        guard minimapContentHeight > 0 else {
            return
        }
        let scale = mainContentHeight / minimapContentHeight
        let deltaMainY = deltaLocalY * scale
        scrollTo(contentOffsetY: dragStartContentOffsetY + deltaMainY)
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingIndicator = false
    }

    override func scrollWheel(with event: NSEvent) {
        // The minimap doesn't scroll independently — forward wheel events to the real editor.
        scrollView?.scrollWheel(with: event)
    }

    private func scrollToContent(atLocalY localY: CGFloat, centered: Bool) {
        guard minimapContentHeight > 0 else {
            return
        }
        let contentY = localY + minimapContentOffsetY
        let scale = mainContentHeight / minimapContentHeight
        var targetY = contentY * scale
        if centered {
            targetY -= mainViewportHeight / 2
        }
        scrollTo(contentOffsetY: targetY)
    }

    private func scrollTo(contentOffsetY: CGFloat) {
        guard let scrollView else {
            return
        }
        onUserScroll?()
        let clampedY = min(max(contentOffsetY, 0), mainScrollableRange)
        scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: clampedY)
    }
}
