import AppKit
import Foundation

final class SelectionOverlayView: UIView {
    var selectionRects: [TextSelectionRect] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    var highlightColor: UIColor = .label.withAlphaComponent(0.2) {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        context.saveGState()
        context.setFillColor(highlightColor.cgColor)
        for selectionRect in selectionRects {
            context.fill(selectionRect.rect)
        }
        context.restoreGState()
    }
}
