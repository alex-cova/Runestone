import Foundation
@preconcurrency import AppKit

protocol LineFragmentControllerDelegate: AnyObject {
    func string(in controller: LineFragmentController) -> String?
}

final class LineFragmentController {
    weak var delegate: LineFragmentControllerDelegate?
    var lineFragment: LineFragment {
        didSet {
            if lineFragment !== oldValue {
                renderer.lineFragment = lineFragment
                lineFragmentView?.setNeedsDisplay()
            }
        }
    }
    weak var lineFragmentView: LineFragmentView? {
        didSet {
            if lineFragmentView !== oldValue || lineFragmentView?.renderer !== renderer {
                lineFragmentView?.renderer = renderer
            }
        }
    }
    var markedRange: NSRange? {
        get {
            renderer.markedRange
        }
        set {
            if newValue != renderer.markedRange {
                renderer.markedRange = newValue
                lineFragmentView?.setNeedsDisplay()
            }
        }
    }
    var markedTextBackgroundColor: UIColor {
        get {
            renderer.markedTextBackgroundColor
        }
        set {
            if newValue != renderer.markedTextBackgroundColor {
                renderer.markedTextBackgroundColor = newValue
                lineFragmentView?.setNeedsDisplay()
            }
        }
    }
    var markedTextBackgroundCornerRadius: CGFloat {
        get {
            renderer.markedTextBackgroundCornerRadius
        }
        set {
            if newValue != renderer.markedTextBackgroundCornerRadius {
                renderer.markedTextBackgroundCornerRadius = newValue
                lineFragmentView?.setNeedsDisplay()
            }
        }
    }
    var highlightedRangeFragments: [HighlightedRangeFragment] {
        get {
            renderer.highlightedRangeFragments
        }
        set {
            if newValue != renderer.highlightedRangeFragments {
                renderer.highlightedRangeFragments = newValue
                lineFragmentView?.setNeedsDisplay()
            }
        }
    }
    var unfocusedAlpha: CGFloat {
        get {
            renderer.unfocusedAlpha
        }
        set {
            if newValue != renderer.unfocusedAlpha {
                renderer.unfocusedAlpha = newValue
                lineFragmentView?.setNeedsDisplay()
            }
        }
    }
    var focusedRanges: [NSRange] {
        get {
            renderer.focusedRanges
        }
        set {
            if newValue != renderer.focusedRanges {
                renderer.focusedRanges = newValue
                lineFragmentView?.setNeedsDisplay()
            }
        }
    }
    var foldPlaceholderText: String? {
        get {
            renderer.foldPlaceholderText
        }
        set {
            if newValue != renderer.foldPlaceholderText {
                renderer.foldPlaceholderText = newValue
                lineFragmentView?.setNeedsDisplay()
            }
        }
    }

    private let renderer: LineFragmentRenderer

    init(lineFragment: LineFragment, invisibleCharacterConfiguration: InvisibleCharacterConfiguration) {
        self.lineFragment = lineFragment
        self.renderer = LineFragmentRenderer(lineFragment: lineFragment, invisibleCharacterConfiguration: invisibleCharacterConfiguration)
        self.renderer.delegate = self
    }
}

// MARK: - LineFragmentRendererDelegate
extension LineFragmentController: LineFragmentRendererDelegate {
    func string(in lineFragmentRenderer: LineFragmentRenderer) -> String? {
        delegate?.string(in: self)
    }
}
