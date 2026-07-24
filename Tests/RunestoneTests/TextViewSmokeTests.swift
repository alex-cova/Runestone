import AppKit
import XCTest
@testable import Runestone

final class TextViewSmokeTests: XCTestCase {
    func testDefaultThemeProvidesEditorColors() {
        let theme = DefaultTheme()
        XCTAssertGreaterThan(theme.font.pointSize, 0)
        XCTAssertGreaterThan(theme.textColor.cgColor.alpha, 0)
        XCTAssertGreaterThan(theme.selectionColor.cgColor.alpha, 0)
    }

    func testTextViewStateInitializesForPlainText() {
        let state = TextViewState(text: "hello\nworld", theme: DefaultTheme())
        XCTAssertEqual(state.stringView.string as String, "hello\nworld")
        XCTAssertNotNil(state.lineManager)
    }
}
