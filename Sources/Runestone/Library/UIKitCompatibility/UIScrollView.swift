import AppKit
import Foundation

open class UIScrollView: UIView {
    open var contentSize: CGSize = .zero { didSet { updateDocumentViewFrame() } }
    open var contentOffset: CGPoint = .zero { didSet { clipView.scroll(to: contentOffset) } }
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
        super.addSubview(clipView)
        clipView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            clipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            clipView.topAnchor.constraint(equalTo: topAnchor),
            clipView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required public init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    open override func addSubview(_ view: NSView) { documentContainer.addSubview(view) }
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
    private func updateDocumentViewFrame() {
        documentContainer.frame = CGRect(origin: .zero, size: contentSize)
        clipView.documentView = documentContainer
    }
    override open func layout() { super.layout(); clipView.frame = bounds; updateDocumentViewFrame() }
}

private final class FlippedClipView: NSClipView { override var isFlipped: Bool { true } }

extension UIScrollView {
    public var minimumContentOffset: CGPoint { CGPoint(x: adjustedContentInset.left * -1, y: adjustedContentInset.top * -1) }
    public var maximumContentOffset: CGPoint {
        CGPoint(x: max(contentSize.width - bounds.width + adjustedContentInset.right, adjustedContentInset.left * -1),
                y: max(contentSize.height - bounds.height + adjustedContentInset.bottom, adjustedContentInset.top * -1))
    }
}
