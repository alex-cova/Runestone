import Foundation
import AppKit

/// Default theme used by Runestone when no other theme has been set.
public final class DefaultTheme: Runestone.Theme {
    private static let defaultFont = NSFont(name: "Menlo", size: 14) ?? NSFont.userFixedPitchFont(ofSize: 14) ?? NSFont.systemFont(ofSize: 14)

    public let font: UIFont = DefaultTheme.defaultFont
    public let textColor = UIColor(themeColorNamed: "foreground")
    public let gutterBackgroundColor = UIColor(themeColorNamed: "gutter_background")
    public let gutterHairlineColor = UIColor(themeColorNamed: "gutter_hairline")
    public let lineNumberColor = UIColor(themeColorNamed: "line_number")
    public let lineNumberFont: UIFont = DefaultTheme.defaultFont
    public let selectedLineBackgroundColor = UIColor(themeColorNamed: "current_line")
    public let selectedLinesLineNumberColor = UIColor(themeColorNamed: "line_number_current_line")
    public let selectedLinesGutterBackgroundColor = UIColor(themeColorNamed: "gutter_background")
    public let invisibleCharactersColor = UIColor(themeColorNamed: "invisible_characters")
    public let pageGuideHairlineColor = UIColor(themeColorNamed: "page_guide_hairline")
    public let pageGuideBackgroundColor = UIColor(themeColorNamed: "page_guide_background")
    public let markedTextBackgroundColor = UIColor(themeColorNamed: "marked_text")
    public let selectionColor = UIColor(themeColorNamed: "selection")

    public init() {}

    // swiftlint:disable:next cyclomatic_complexity
    public func textColor(for highlightName: String) -> UIColor? {
        guard let highlightName = HighlightName(highlightName) else {
            return nil
        }
        switch highlightName {
        case .comment:
            return UIColor(themeColorNamed: "comment")
        case .constantBuiltin:
            return UIColor(themeColorNamed: "constant_builtin")
        case .constantCharacter:
            return UIColor(themeColorNamed: "constant_character")
        case .constructor:
            return UIColor(themeColorNamed: "constructor")
        case .function:
            return UIColor(themeColorNamed: "function")
        case .keyword:
            return UIColor(themeColorNamed: "keyword")
        case .number:
            return UIColor(themeColorNamed: "number")
        case .property:
            return UIColor(themeColorNamed: "property")
        case .string:
            return UIColor(themeColorNamed: "string")
        case .type:
            return UIColor(themeColorNamed: "type")
        case .variable:
            return nil
        case .variableBuiltin:
            return UIColor(themeColorNamed: "variable_builtin")
        case .operator:
            return UIColor(themeColorNamed: "operator")
        case .punctuation:
            return UIColor(themeColorNamed: "punctuation")
        }
    }

    public func fontTraits(for highlightName: String) -> FontTraits {
        guard let highlightName = HighlightName(highlightName) else {
            return []
        }
        if highlightName == .keyword {
            return .bold
        } else {
            return []
        }
    }

    public func highlightedRange(forFoundTextRange foundTextRange: NSRange, ofStyle style: UITextSearchFoundTextStyle) -> HighlightedRange? {
        switch style {
        case .found:
            let color = UIColor(themeColorNamed: "search_match_found")
            return HighlightedRange(range: foundTextRange, color: color, cornerRadius: 2)
        case .highlighted:
            let color = UIColor(themeColorNamed: "search_match_highlighted")
            return HighlightedRange(range: foundTextRange, color: color, cornerRadius: 2)
        case .standard, .normal:
            return nil
        @unknown default:
            return nil
        }
    }
}

private extension UIColor {
    convenience init(themeColorNamed name: String) {
        let fullName = "theme_" + name
        if NSColor(named: fullName, in: .module, compatibleWith: nil) != nil {
            self.init(named: fullName, bundle: .module)!
            return
        }
        // Catalog colors often fail to resolve when Runestone is statically
        // linked. Never fall back to near-black for chrome — that paints the
        // gutter as a black strip on first layout.
        self.init(name: nil) { _ in
            switch name {
            case "gutter_background", "page_guide_background":
                return .textBackgroundColor
            case "current_line":
                return .selectedContentBackgroundColor.withAlphaComponent(0.25)
            case "selection", "marked_text", "search_match_found", "search_match_highlighted":
                return .selectedContentBackgroundColor.withAlphaComponent(0.35)
            case "foreground":
                return .textColor
            case "line_number", "line_number_current_line", "invisible_characters",
                 "gutter_hairline", "page_guide_hairline":
                return .secondaryLabelColor
            default:
                return .labelColor
            }
        }
    }
}
