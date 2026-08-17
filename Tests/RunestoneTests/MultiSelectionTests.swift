import AppKit
import XCTest
@testable import Runestone

final class MultiSelectionTests: XCTestCase {
    private func makeFocusedTextView(text: String) -> TextView {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        textView.setState(TextViewState(text: text, theme: DefaultTheme()))
        textView.layoutIfNeeded()
        XCTAssertTrue(textView.focusTextInput())
        return textView
    }

    func testInsertTextAtMultipleCarets() {
        let textView = makeFocusedTextView(text: "ab ab ab")
        textView.selectedRanges = [
            NSRange(location: 0, length: 0),
            NSRange(location: 3, length: 0),
            NSRange(location: 6, length: 0)
        ]
        textView.insertText("X")
        XCTAssertEqual(textView.text as String, "Xab Xab Xab")
        XCTAssertEqual(textView.selectedRanges, [
            NSRange(location: 1, length: 0),
            NSRange(location: 4, length: 0),
            NSRange(location: 7, length: 0)
        ])
    }

    func testDeleteBackwardAtMultipleCarets() {
        let textView = makeFocusedTextView(text: "aabb")
        textView.selectedRanges = [
            NSRange(location: 2, length: 0),
            NSRange(location: 4, length: 0)
        ]
        textView.deleteBackward()
        XCTAssertEqual(textView.text as String, "ab")
        XCTAssertEqual(textView.selectedRanges, [
            NSRange(location: 1, length: 0),
            NSRange(location: 3, length: 0)
        ])
    }

    func testCollapseMultiSelectionToPrimary() {
        let textView = makeFocusedTextView(text: "hello")
        textView.selectedRanges = [
            NSRange(location: 0, length: 0),
            NSRange(location: 3, length: 0)
        ]
        textView.collapseMultiSelectionToPrimary()
        XCTAssertFalse(textView.isMultiCursorActive)
        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 0))
    }

    func testAddSelectionsOnEachLine() {
        let textView = makeFocusedTextView(text: "one\ntwo\nthree")
        textView.selectedRange = NSRange(location: 0, length: 11)
        textView.addSelectionsOnEachLine()
        XCTAssertEqual(textView.selectedRanges, [
            NSRange(location: 0, length: 0),
            NSRange(location: 4, length: 0),
            NSRange(location: 8, length: 0)
        ])
    }

    func testMultiSelectionControllerNormalizesDuplicateCarets() {
        let controller = MultiSelectionController()
        controller.setSelections([
            NSRange(location: 2, length: 0),
            NSRange(location: 2, length: 0),
            NSRange(location: 5, length: 0)
        ])
        XCTAssertEqual(controller.selections, [
            NSRange(location: 2, length: 0),
            NSRange(location: 5, length: 0)
        ])
    }

    func testNonEmptyRangeReplacesMultiCaretSelection() {
        let controller = MultiSelectionController()
        controller.setSelections([
            NSRange(location: 0, length: 0),
            NSRange(location: 4, length: 0)
        ])
        controller.setSelections([NSRange(location: 1, length: 3)])
        XCTAssertEqual(controller.selections, [NSRange(location: 1, length: 3)])
        XCTAssertFalse(controller.hasMultipleSelections)
    }

    func testMultipleMatchingRangesArePreserved() {
        let controller = MultiSelectionController()
        controller.setSelections([
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3)
        ])
        XCTAssertEqual(controller.selections, [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3)
        ])
        XCTAssertTrue(controller.hasMultipleSelections)
    }

    func testSelectNextOccurrenceSelectsWordThenAddsNextMatch() {
        let textView = makeFocusedTextView(text: "foo foo foo")
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.selectNextOccurrence()
        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 3))
        textView.selectNextOccurrence()
        XCTAssertEqual(textView.selectedRanges, [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 3)
        ])
    }

    func testInsertTextAtMultipleMatchingRanges() {
        let textView = makeFocusedTextView(text: "foo bar foo")
        textView.selectedRanges = [
            NSRange(location: 0, length: 3),
            NSRange(location: 8, length: 3)
        ]
        textView.insertText("X")
        XCTAssertEqual(textView.text as String, "X bar X")
    }

    func testVerticalArrowMovesAllCarets() {
        let textView = makeFocusedTextView(text: "aaa\nbbb\nccc")
        textView.selectedRanges = [
            NSRange(location: 0, length: 0),
            NSRange(location: 8, length: 0)
        ]
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 0x7D
        )!
        textView.window?.sendEvent(event)
        XCTAssertEqual(textView.selectedRanges, [
            NSRange(location: 4, length: 0),
            NSRange(location: 11, length: 0)
        ])
    }
}
