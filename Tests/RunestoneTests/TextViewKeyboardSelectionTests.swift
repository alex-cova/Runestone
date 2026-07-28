import AppKit
import XCTest
@testable import Runestone

/// Covers keyboard-driven caret movement and selection extension on `TextView`/`TextInputView`
/// on macOS — in particular the shift-arrow "extension sticks after one step" regression, and
/// that read-only (but selectable) editors still support navigation, selection and copy.
final class TextViewKeyboardSelectionTests: XCTestCase {
    // MARK: - Helpers

    private func makeFocusedTextView(text: String, isEditable: Bool = true) -> TextView {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        textView.isEditable = isEditable
        textView.isSelectable = true
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        textView.setState(TextViewState(text: text, theme: DefaultTheme()))
        // A real window always lays the view out before the user can type into it;
        // do the same here so line-fragment-dependent boundary math (Home/End, ⌘←/→)
        // isn't operating on unlaid-out (zero-length) line fragments.
        textView.layoutIfNeeded()
        XCTAssertTrue(textView.focusTextInput(), "focusTextInput() should install first responder")
        return textView
    }

    private func keyEvent(keyCode: UInt16, characters: String = "", flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func send(_ event: NSEvent, to textView: TextView) {
        textView.window?.sendEvent(event)
    }

    private enum KeyCode {
        static let leftArrow: UInt16 = 0x7B
        static let rightArrow: UInt16 = 0x7C
        static let letterA: UInt16 = 0x00
    }

    // MARK: - Shift-arrow extension (regression: stuck after one step)

    func testShiftRightArrowExtendsSelectionRepeatedly() {
        let textView = makeFocusedTextView(text: "hello world")
        textView.selectedRange = NSRange(location: 0, length: 0)

        for _ in 0..<3 {
            send(keyEvent(keyCode: KeyCode.rightArrow, flags: .shift), to: textView)
        }

        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 3))
    }

    func testShiftLeftArrowShrinksThenExtendsTheOtherWay() {
        let textView = makeFocusedTextView(text: "hello world")
        textView.selectedRange = NSRange(location: 5, length: 0)

        for _ in 0..<3 {
            send(keyEvent(keyCode: KeyCode.rightArrow, flags: .shift), to: textView)
        }
        XCTAssertEqual(textView.selectedRange, NSRange(location: 5, length: 3))

        for _ in 0..<3 {
            send(keyEvent(keyCode: KeyCode.leftArrow, flags: .shift), to: textView)
        }
        XCTAssertEqual(textView.selectedRange, NSRange(location: 5, length: 0))

        for _ in 0..<3 {
            send(keyEvent(keyCode: KeyCode.leftArrow, flags: .shift), to: textView)
        }
        XCTAssertEqual(textView.selectedRange, NSRange(location: 2, length: 3))
    }

    func testShiftOptionRightArrowExtendsByWord() {
        let textView = makeFocusedTextView(text: "hello world today")
        textView.selectedRange = NSRange(location: 0, length: 0)

        send(keyEvent(keyCode: KeyCode.rightArrow, flags: [.shift, .option]), to: textView)
        send(keyEvent(keyCode: KeyCode.rightArrow, flags: [.shift, .option]), to: textView)

        XCTAssertEqual(textView.selectedRange.location, 0)
        // Selection should have grown to cover "hello world" (both words), not be stuck
        // after the first extension.
        XCTAssertGreaterThan(textView.selectedRange.length, 5)
        XCTAssertLessThanOrEqual(textView.selectedRange.upperBound, 12)
    }

    func testShiftCommandRightArrowExtendsToEndOfLine() {
        let textView = makeFocusedTextView(text: "hello world")
        textView.selectedRange = NSRange(location: 0, length: 0)

        send(keyEvent(keyCode: KeyCode.rightArrow, flags: [.shift, .command]), to: textView)

        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 11))
    }

    func testPlainRightArrowWithExistingSelectionCollapsesToUpperBound() {
        let textView = makeFocusedTextView(text: "hello world")
        textView.selectedRange = NSRange(location: 2, length: 3)

        send(keyEvent(keyCode: KeyCode.rightArrow), to: textView)

        XCTAssertEqual(textView.selectedRange, NSRange(location: 5, length: 0))
    }

    func testPlainLeftArrowWithExistingSelectionCollapsesToLocation() {
        let textView = makeFocusedTextView(text: "hello world")
        textView.selectedRange = NSRange(location: 2, length: 3)

        send(keyEvent(keyCode: KeyCode.leftArrow), to: textView)

        XCTAssertEqual(textView.selectedRange, NSRange(location: 2, length: 0))
    }

    // MARK: - Read-only (selectable, non-editable) editors

    func testReadOnlyEditorSupportsArrowNavigation() {
        let textView = makeFocusedTextView(text: "hello world", isEditable: false)
        textView.selectedRange = NSRange(location: 0, length: 0)

        send(keyEvent(keyCode: KeyCode.rightArrow), to: textView)
        send(keyEvent(keyCode: KeyCode.rightArrow), to: textView)

        XCTAssertEqual(textView.selectedRange, NSRange(location: 2, length: 0))
    }

    func testReadOnlyEditorSupportsShiftSelection() {
        let textView = makeFocusedTextView(text: "hello world", isEditable: false)
        textView.selectedRange = NSRange(location: 0, length: 0)

        for _ in 0..<4 {
            send(keyEvent(keyCode: KeyCode.rightArrow, flags: .shift), to: textView)
        }

        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 4))
    }

    func testReadOnlyEditorDoesNotInsertText() {
        let textView = makeFocusedTextView(text: "hello world", isEditable: false)
        textView.selectedRange = NSRange(location: 0, length: 0)

        send(keyEvent(keyCode: KeyCode.letterA, characters: "a"), to: textView)

        XCTAssertEqual(textView.text, "hello world")
    }
}
