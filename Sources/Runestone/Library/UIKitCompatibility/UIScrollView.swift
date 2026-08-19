import AppKit
import Foundation

open class UIScrollView: UIView {
    open var contentSize: CGSize = .zero {
        didSet {
            guard contentSize != oldValue else { return }
            updateDocumentViewFrame()
        }
    }
    private var storedContentOffset: CGPoint = .zero
    open var contentOffset: CGPoint {
        get {
            storedContentOffset
        }
        set {
            guard newValue != storedContentOffset else { return }
            storedContentOffset = newValue
            clipView.scroll(to: newValue)
        }
    }
    open var contentInset: UIEdgeInsets = .zero
    open var adjustedContentInset: UIEdgeInsets { contentInset }
    open var isDragging = false
    open var isDecelerating = false
    open var panGestureRecognizer = UIPanGestureRecognizer()
    private let clipView = FlippedClipView()
    private let documentContainer = UIView(frame: .zero)

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipView.drawsBackground = false
        clipView.documentView = documentContainer
        // Frame-based layout only. Mixing Auto Layout edges with
        // `clipView.frame = bounds` in layout() causes an AppKit
        // "Update Constraints in Window" feedback loop when TextView
        // is hosted in SwiftUI's NSHostingView.
        clipView.translatesAutoresizingMaskIntoConstraints = true
        clipView.autoresizingMask = [.width, .height]
        clipView.frame = bounds
        super.addSubview(clipView)
    }
    required public init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    open override func addSubview(_ view: NSView) { documentContainer.addSubview(view) }
    /// Adds a view directly to the scroll view itself, outside the scrollable document
    /// container, so it stays fixed on screen instead of scrolling with content. `addSubview(_:)`
    /// always routes into the scrolling document container, so this is the only way to add a
    /// viewport-anchored overlay (e.g. a minimap) as a child of a `UIScrollView`.
    open func addFixedOverlaySubview(_ view: NSView) { super.addSubview(view) }
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }

    /// Scrolls to `offset`, optionally animating the AppKit clip view with an ease-out curve.
    open func setContentOffset(_ offset: CGPoint, animationDuration: TimeInterval) {
        guard animationDuration > 0, offset != storedContentOffset else {
            contentOffset = offset
            return
        }
        storedContentOffset = offset
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clipView.animator().setBoundsOrigin(offset)
        }
    }

    /// Stops a pending animated scroll at the current target.
    open func cancelAnimatedScrolling() {
        clipView.layer?.removeAllAnimations()
        clipView.scroll(to: storedContentOffset)
    }
    private func updateDocumentViewFrame() {
        // AppKit hit-tests against the document view's frame. For short or empty
        // documents, contentSize is only ~one line tall, so clicks in the empty
        // editor area below that miss TextInputView and never focus. Grow the
        // document container to at least the visible bounds; contentSize still
        // drives scroll metrics via maximumContentOffset.
        let size = CGSize(
            width: max(contentSize.width, bounds.width),
            height: max(contentSize.height, bounds.height)
        )
        let next = CGRect(origin: .zero, size: size)
        if documentContainer.frame != next {
            documentContainer.frame = next
        }
        if clipView.documentView !== documentContainer {
            clipView.documentView = documentContainer
        }
    }
    override open func layout() {
        layoutSubviews()
        if clipView.frame != bounds {
            clipView.frame = bounds
        }
        updateDocumentViewFrame()
    }

    /// NSClipView only receives wheel events when it is hit-tested. Text input
    /// sits above it in the document, so forward wheel deltas into contentOffset.
    override open func scrollWheel(with event: NSEvent) {
        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX * 10
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        let minOffset = minimumContentOffset
        let maxOffset = maximumContentOffset
        let next = CGPoint(
            x: min(max(contentOffset.x - dx, minOffset.x), maxOffset.x),
            y: min(max(contentOffset.y - dy, minOffset.y), maxOffset.y)
        )
        if next != contentOffset {
            contentOffset = next
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

private final class FlippedClipView: NSClipView { override var isFlipped: Bool { true } }

extension UIScrollView {
    public var minimumContentOffset: CGPoint { CGPoint(x: adjustedContentInset.left * -1, y: adjustedContentInset.top * -1) }
    public var maximumContentOffset: CGPoint {
        CGPoint(x: max(contentSize.width - bounds.width + adjustedContentInset.right, adjustedContentInset.left * -1),
                y: max(contentSize.height - bounds.height + adjustedContentInset.bottom, adjustedContentInset.top * -1))
    }
}
