import XCTest
import AppKit
@testable import Runestone

/// Smoke coverage for the `viewDidChangeEffectiveAppearance()` overrides added to re-bake
/// `CGColor`-backed theme colors (see `DefaultThemeTests` for the color-source fix these pair
/// with). Live system-appearance changes can't be driven headlessly in a test, so this instead
/// forces each view's own `appearance` between `.aqua`/`.darkAqua` and calls the override
/// directly, asserting only that it runs to completion without crashing — a regression here would
/// most likely be a force-unwrap or an unguarded access to state that isn't set up yet (e.g. a nil
/// `lineDataSource`/`theme` before the view has been fully configured).
@MainActor
final class AppearanceChangeSmokeTests: XCTestCase {
    private func exerciseAppearanceChange(on view: NSView, _ body: () -> Void = {}) {
        view.appearance = NSAppearance(named: .aqua)
        view.viewDidChangeEffectiveAppearance()
        view.appearance = NSAppearance(named: .darkAqua)
        view.viewDidChangeEffectiveAppearance()
        body()
    }

    func testCompatUIViewRebakesBackgroundColorWithoutCrashing() {
        let view = UIView(frame: .zero)
        view.backgroundColor = DefaultTheme().gutterBackgroundColor
        exerciseAppearanceChange(on: view)
    }

    func testCompatUIViewWithNoBackgroundColorDoesNotCrash() {
        let view = UIView(frame: .zero)
        exerciseAppearanceChange(on: view)
    }

    func testCaretViewRebakesCaretColorWithoutCrashing() {
        let caretView = CaretView(frame: .zero)
        caretView.caretColor = DefaultTheme().textColor
        exerciseAppearanceChange(on: caretView)
    }

    func testMinimapViewWithoutLineDataSourceDoesNotCrash() {
        // Exercises the guard in `applyTheme()`/the appearance-change path before a data source
        // (and therefore a theme) has been attached.
        let minimapView = MinimapView(frame: .zero)
        exerciseAppearanceChange(on: minimapView)
    }

    func testMinimapViewWithThemeRebakesViewportBorderWithoutCrashing() {
        let minimapView = MinimapView(frame: .zero)
        let textInputView = TextInputView(theme: DefaultTheme())
        minimapView.lineDataSource = textInputView
        minimapView.applyTheme()
        exerciseAppearanceChange(on: minimapView)
    }

    func testTextInputViewForcesReTypesetWithoutCrashing() {
        let textInputView = TextInputView(theme: DefaultTheme())
        exerciseAppearanceChange(on: textInputView)
    }

    func testFindPanelBarViewRebakesBackgroundWithoutCrashing() {
        exerciseAppearanceChange(on: FindPanelBarView(frame: .zero))
    }

    func testWorkspaceSearchPanelViewRebakesColorsWithoutCrashing() {
        exerciseAppearanceChange(on: WorkspaceSearchPanelView(frame: .zero))
    }

    func testOutlineSidebarViewRebakesBackgroundWithoutCrashing() {
        exerciseAppearanceChange(on: OutlineSidebarView(frame: .zero))
    }

    func testCodeActionViewRebakesColorsWithoutCrashing() {
        exerciseAppearanceChange(on: CodeActionView(frame: .zero))
    }

    func testBreadcrumbBarViewRebakesBackgroundWithoutCrashing() {
        exerciseAppearanceChange(on: BreadcrumbBarView(frame: .zero))
    }
}
