import AppKit
import XCTest
@testable import Runestone

/// `CommandPaletteController` wiring: built-in action registration, presentation state,
/// keymap-action routing, provider selection, and fuzzy match plumbing.
@MainActor
final class CommandPaletteControllerTests: XCTestCase {
    func testRegistersBuiltInActionsWithShortcutsFromKeymap() {
        let textView = makeFocusedTextView(text: "x")
        textView.keymap = .intelliJ
        let controller = CommandPaletteController(textView: textView)

        let joinLines = controller.commandRegistry.command(id: "action.\(EditorActionID.joinLines.rawValue)")
        XCTAssertNotNil(joinLines)
        XCTAssertEqual(joinLines?.shortcutDisplay, "\u{2303}\u{21E7}J")
    }

    func testSearchEverywhereActionPresentsThePalette() {
        let textView = makeFocusedTextView(text: "x")
        let controller = CommandPaletteController(textView: textView)
        XCTAssertFalse(controller.isPresented)

        XCTAssertTrue(textView.perform(.findAction))
        XCTAssertTrue(controller.isPresented)

        controller.dismiss()
        XCTAssertFalse(controller.isPresented)
    }

    func testSurroundWithActionOnlyPresentsWithANonEmptySelection() {
        let textView = makeFocusedTextView(text: "value")
        let controller = CommandPaletteController(textView: textView)

        textView.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertTrue(textView.perform(.surroundWith))
        XCTAssertFalse(controller.isPresented, "No selection -> nothing to surround")

        textView.selectedRange = NSRange(location: 0, length: 5)
        XCTAssertTrue(textView.perform(.surroundWith))
        XCTAssertTrue(controller.isPresented)
    }

    func testCommandsProviderPopulatesFuzzyMatchIndices() async {
        let registry = CommandRegistry()
        registry.register(EditorCommand(id: "c1", title: "Reformat Code", group: "Editor", action: {}))
        registry.register(EditorCommand(id: "c2", title: "Reindent Lines", group: "Editor", action: {}))
        let provider = CommandsPaletteProvider(registry: registry)

        let items = await provider.items(matching: "rc", limit: 10)
        XCTAssertEqual(items.first?.title, "Reformat Code")
        XCTAssertFalse(items.first?.matchedIndices.isEmpty ?? true, "Match indices drive the row highlight")
    }

    func testActionHandlerChainingPreservesAPreviousHandler() {
        let textView = makeFocusedTextView(text: "x")
        var previousSaw: EditorActionID?
        textView.editorActionHandler = { action in
            previousSaw = action
            return false
        }
        _ = CommandPaletteController(textView: textView)

        // A non-palette action falls through the controller to the previous handler.
        _ = textView.perform(.goToImplementation)
        XCTAssertEqual(previousSaw, .goToImplementation)
    }
}
