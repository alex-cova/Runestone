import XCTest
import EditorIntelligence

final class LSPWorkspaceSyncBridgeTests: XCTestCase {
    func testDocumentLifecycleHandlersFire() async {
        let opened = LockedBox<Document>()
        let changed = LockedBox<Document>()
        let closed = LockedBox<DocumentID>()

        let barrier = HandlerBarrier(expected: 3)

        let handlers = LSPDocumentSyncHandlers(
            onOpen: { document, languageID, version in
                XCTAssertEqual(languageID, "swift")
                XCTAssertEqual(version, 1)
                opened.value = document
                await barrier.signal()
            },
            onFullChange: { document, version in
                XCTAssertEqual(version, 2)
                changed.value = document
                await barrier.signal()
            },
            onClose: { documentID in
                closed.value = documentID
                await barrier.signal()
            }
        )

        let bridge = LSPWorkspaceSyncBridge(
            handlers: handlers,
            languageResolver: { _ in "swift" }
        )
        let workspace = Workspace()
        await bridge.connect(to: workspace)

        let document = makeDocument(text: "let a = 1")
        async let handlersComplete = barrier.wait()
        await workspace.openDocument(document)
        await workspace.updateDocument(
            Document(
                id: document.id,
                url: document.url,
                displayName: document.displayName,
                contentSnapshot: TextSnapshot(version: 1, text: "let a = 2"),
                selection: document.selection,
                cursor: document.cursor,
                viewport: document.viewport,
                languageIdentifier: document.languageIdentifier
            )
        )
        await workspace.closeDocument(document.id)
        await handlersComplete

        XCTAssertEqual(opened.value?.contentSnapshot.text, "let a = 1")
        if let changedDocument = changed.value {
            XCTAssertEqual(changedDocument.contentSnapshot.text, "let a = 2")
        } else {
            XCTFail("Expected document change handler")
        }
        XCTAssertEqual(closed.value, document.id)
    }
}

private actor HandlerBarrier {
    private let expected: Int
    private var received = 0
    private var waiter: CheckedContinuation<Void, Never>?

    init(expected: Int) {
        self.expected = expected
    }

    func signal() {
        received += 1
        if received >= expected, let waiter {
            waiter.resume()
            self.waiter = nil
        }
    }

    func wait() async {
        if received >= expected {
            return
        }
        await withCheckedContinuation { continuation in
            if received >= expected {
                continuation.resume()
            } else {
                waiter = continuation
            }
        }
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    var value: T?

    init(_ value: T? = nil) {
        self.value = value
    }
}

private func makeDocument(text: String) -> Document {
    let position = TextPosition(line: 0, column: 0, utf16Offset: 0)
    let range = TextRange(start: position, end: position)
    return Document(
        id: DocumentID(),
        url: nil,
        displayName: "test.swift",
        contentSnapshot: TextSnapshot(version: 0, text: text),
        selection: Selection(range: range),
        cursor: Cursor(position: position),
        viewport: Viewport(x: 0, y: 0, width: 100, height: 100),
        languageIdentifier: "swift"
    )
}
