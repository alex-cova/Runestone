import AppKit
import XCTest
import EditorIntelligence
@testable import Runestone

@MainActor
final class RunestoneEditorAdapterTests: XCTestCase {
    func testAdapterCreatesInitialDocument() async throws {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        textView.text = "hello world"
        let adapter = RunestoneEditorAdapter(textView: textView, context: EditorContext(rootProjectURL: URL(fileURLWithPath: "/tmp")))
        // Wait for the initial document capture task on the main actor.
        try await Task.sleep(nanoseconds: 100_000_000)
        let document = adapter.currentDocument
        XCTAssertNotNil(document)
        XCTAssertEqual(document?.text, "hello world")
        XCTAssertEqual(document?.displayName, "tmp")
    }

    func testTextChangeEmitsDocumentChangedEvent() async throws {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        textView.text = "hello"
        let adapter = RunestoneEditorAdapter(textView: textView, context: EditorContext())
        let events = adapter.events
        var capturedEvents: [EditorEvent] = []
        let task = Task.detached {
            for await event in events {
                capturedEvents.append(event)
                if capturedEvents.count >= 2 {
                    return
                }
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        textView.text = "hello world"
        adapter.textViewDidChange(textView)
        _ = await task.result
        XCTAssertEqual(capturedEvents.count, 2)
        if case .documentChanged = capturedEvents.last {
            // expected
        } else {
            XCTFail("Expected documentChanged event, got \(String(describing: capturedEvents.last))")
        }
    }
}
