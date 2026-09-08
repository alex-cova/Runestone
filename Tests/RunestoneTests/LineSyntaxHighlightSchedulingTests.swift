@preconcurrency import AppKit
import XCTest
@testable import Runestone

/// Layout used to cancel the in-flight highlight on every `prepareToDisplayString`, so a viewport
/// that laid out at display refresh starved syntax coloring. These tests lock the new rule:
/// cancel only when the line string/default attributes are rebuilt; skip starting a second async
/// job while one is already running.
final class LineSyntaxHighlightSchedulingTests: XCTestCase, LineControllerStorageDelegate, LineControllerDelegate {
    private let highlighter = StickyAsyncHighlighter()

    func lineControllerStorage(_ storage: LineControllerStorage, didCreate lineController: LineController) {
        lineController.delegate = self
        lineController.constrainingWidth = 320
    }

    func lineSyntaxHighlighter(for lineController: LineController) -> LineSyntaxHighlighter? {
        highlighter
    }

    func lineControllerDidInvalidateLineWidthDuringAsyncSyntaxHighlight(_ lineController: LineController) {}

    func testRepeatedAsyncPrepareDoesNotCancelOrRestartInFlightHighlight() {
        let controller = makeLineController(text: "let value = 42")
        controller.prepareToDisplayString(toLocation: 14, syntaxHighlightAsynchronously: true)
        XCTAssertEqual(highlighter.highlightCount, 1)
        let cancelsAfterFirstPrepare = highlighter.cancelCount

        controller.prepareToDisplayString(toLocation: 14, syntaxHighlightAsynchronously: true)
        XCTAssertEqual(highlighter.highlightCount, 1, "in-flight highlight should not be restarted")
        XCTAssertEqual(highlighter.cancelCount, cancelsAfterFirstPrepare, "in-flight highlight should not be cancelled by a layout pass")
    }

    func testRebuildingTheLineStringCancelsInFlightHighlight() {
        let controller = makeLineController(text: "let value = 42")
        controller.prepareToDisplayString(toLocation: 14, syntaxHighlightAsynchronously: true)
        XCTAssertEqual(highlighter.highlightCount, 1)

        controller.invalidateEverything()
        controller.prepareToDisplayString(toLocation: 14, syntaxHighlightAsynchronously: true)
        XCTAssertGreaterThan(highlighter.cancelCount, 0)
        XCTAssertEqual(highlighter.highlightCount, 2, "a new highlight should start after the string is rebuilt")
    }

    private func makeLineController(text: String) -> LineController {
        let stringView = StringView(string: text)
        let lineManager = LineManager(stringView: stringView)
        lineManager.rebuild()
        let factory = LineControllerFactory(
            stringView: stringView,
            highlightService: HighlightService(lineManager: lineManager),
            invisibleCharacterConfiguration: InvisibleCharacterConfiguration()
        )
        let storage = LineControllerStorage(stringView: stringView, lineControllerFactory: factory)
        storage.delegate = self
        return storage.getOrCreateLineController(for: lineManager.line(atRow: 0))
    }
}

private final class StickyAsyncHighlighter: LineSyntaxHighlighter {
    var theme: Theme = DefaultTheme()
    var canHighlight: Bool { true }
    var isHighlighting: Bool {
        highlightCount > 0 && pendingCompletion != nil
    }
    var highlightCount = 0
    var cancelCount = 0
    private var pendingCompletion: AsyncCallback?

    func syntaxHighlight(_ input: LineSyntaxHighlighterInput) {
        highlightCount += 1
    }

    func syntaxHighlight(_ input: LineSyntaxHighlighterInput, completion: @escaping AsyncCallback) {
        highlightCount += 1
        pendingCompletion = completion
    }

    func cancel() {
        cancelCount += 1
        pendingCompletion = nil
    }
}
