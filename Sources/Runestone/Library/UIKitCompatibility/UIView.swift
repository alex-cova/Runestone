import AppKit
import Foundation

public typealias UIResponder = NSResponder

open class UIView: NSView {
    open var isFirstResponder: Bool { window?.firstResponder === self }
    open var backgroundColor: UIColor? {
        didSet { wantsLayer = true; layer?.backgroundColor = backgroundColor?.cgColor }
    }
    open var isUserInteractionEnabled = true
    open var traitCollection: UITraitCollection { UITraitCollection() }
    open var inputAccessoryView: UIView?
    open var inputAssistantItem: UITextInputAssistantItem { UITextInputAssistantItem() }
    open func reloadInputViews() {}
    private var uiGestureRecognizers: [UIGestureRecognizer] = []

    override open var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required public init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    open func layoutSubviews() {}
    override open func layout() { super.layout(); layoutSubviews() }
    open func setNeedsLayout() { needsLayout = true }
    open func layoutIfNeeded() { layoutSubtreeIfNeeded() }
    open func setNeedsDisplay() { needsDisplay = true }
    open func bringSubviewToFront(_ view: UIView) { view.removeFromSuperview(); addSubview(view) }
    open func sendSubviewToBack(_ view: UIView) {
        view.removeFromSuperview()
        if let first = subviews.first { addSubview(view, positioned: .below, relativeTo: first) } else { addSubview(view) }
    }
    open func safeAreaInsetsDidChange() {}
    open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}
    open func addInteraction(_ interaction: Any) {}
    open func removeInteraction(_ interaction: Any) {}
    open func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        gestureRecognizer.view = self; uiGestureRecognizers.append(gestureRecognizer)
    }
    open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
    open func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {}
    override open func hitTest(_ point: NSPoint) -> NSView? { isUserInteractionEnabled ? super.hitTest(point) : nil }
    override open func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        didMoveToWindow()
    }
    open func didMoveToWindow() {}
    open override var acceptsFirstResponder: Bool { false }
    override open func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        uiGestureRecognizers.forEach { $0.handleMouseDown(event) }
        super.mouseDown(with: event)
    }
}
