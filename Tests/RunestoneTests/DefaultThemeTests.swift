import XCTest
@testable import Runestone

final class DefaultThemeTests: XCTestCase {
    /// `DefaultTheme` used to resolve its colors from `Theme.xcassets` via `Bundle.module`, which
    /// is known to fail to resolve under certain static-linking configurations — and when it did,
    /// every syntax-highlight token silently collapsed to the same fallback color, defeating
    /// syntax highlighting entirely. Colors are now defined directly in code, independent of the
    /// asset catalog resolving at all. This asserts the distinct token categories actually get
    /// distinct colors.
    func testSyntaxHighlightTokenCategoriesGetDistinctColors() {
        let theme = DefaultTheme()
        // One representative highlight name per distinct color bucket in DefaultTheme.
        let names = ["comment", "string", "keyword", "type", "number", "function", "constructor", "property", "punctuation", "variable.builtin"]
        let colors = names.compactMap { theme.textColor(for: $0) }
        XCTAssertEqual(colors.count, names.count, "Every listed highlight name should resolve to a color")

        let components = colors.map { $0.cgColor.components ?? [] }
        for i in 0 ..< components.count {
            for j in (i + 1) ..< components.count where j < components.count {
                XCTAssertNotEqual(components[i], components[j], "\(names[i]) and \(names[j]) should not share a color")
            }
        }
    }

    func testRelatedTokensIntentionallyShareAColor() {
        let theme = DefaultTheme()
        XCTAssertEqual(theme.textColor(for: "property")?.cgColor.components, theme.textColor(for: "constant.builtin")?.cgColor.components)
        XCTAssertEqual(theme.textColor(for: "property")?.cgColor.components, theme.textColor(for: "constant.character")?.cgColor.components)
        XCTAssertEqual(theme.textColor(for: "punctuation")?.cgColor.components, theme.textColor(for: "operator")?.cgColor.components)
    }

    func testEmphasisHighlightNamesCarryTraitsRatherThanColor() {
        let theme = DefaultTheme()
        XCTAssertNil(theme.textColor(for: "markup.bold"))
        XCTAssertNil(theme.textColor(for: "markup.italic"))
        XCTAssertTrue(theme.fontTraits(for: "markup.bold").contains(.bold))
        XCTAssertTrue(theme.fontTraits(for: "markup.italic").contains(.italic))
        XCTAssertTrue(theme.fontTraits(for: "keyword").contains(.bold))
    }

    func testChromeColorsResolveWithoutTheAssetCatalog() {
        let theme = DefaultTheme()
        // These construct successfully even though nothing here touches `Theme.xcassets` — a
        // regression here would mean DefaultTheme started depending on the resource bundle again.
        XCTAssertNotNil(theme.textColor)
        XCTAssertNotNil(theme.gutterBackgroundColor)
        XCTAssertNotNil(theme.selectedLineBackgroundColor)
        XCTAssertNotNil(theme.invisibleCharactersColor)
    }
}
