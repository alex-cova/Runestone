import AppKit
import Foundation

public enum UIGestureRecognizerState: Int {
    case possible, began, changed, ended, cancelled, failed
}

public protocol UIGestureRecognizerDelegate: AnyObject {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
}

extension UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

open class UIGestureRecognizer: NSObject {
    public weak var delegate: UIGestureRecognizerDelegate?
    weak var view: UIView?
    public var state: UIGestureRecognizerState = .possible
    private weak var target: AnyObject?
    private var action: Selector?
    public func addTarget(_ target: AnyObject, action: Selector) { self.target = target; self.action = action }
    public func require(toFail otherGestureRecognizer: UIGestureRecognizer) {}
    public func location(in view: UIView?) -> CGPoint { .zero }
    fileprivate func sendAction() { _ = target?.perform(action, with: self) }
    func handleMouseDown(_ event: NSEvent) { state = .ended; sendAction(); state = .possible }
}

open class UITapGestureRecognizer: UIGestureRecognizer {}
open class QuickTapGestureRecognizer: UITapGestureRecognizer {
    open var maximumPressDuration: TimeInterval = 0.3
}
open class UIPanGestureRecognizer: UIGestureRecognizer {}

open class UILabel: UIView {
    @objc open var text: String?
    @objc open var textColor: UIColor = .label
    @objc open var font: UIFont?
    @objc open var textAlignment: NSTextAlignment = .left

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Frame-laid-out by LineNumberView; keep Auto Layout from using
        // intrinsicContentSize as a SwiftUI/AppKit measurement input.
        translatesAutoresizingMaskIntoConstraints = true
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open var intrinsicContentSize: NSSize {
        guard let font, let text else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        let size = (text as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }
}
