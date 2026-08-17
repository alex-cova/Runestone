import XCTest
import EditorIntelligence

final class LSPWorkspaceSyncBridgeTests: XCTestCase {
    func testDocumentLifecycleHandlersFire() async {
        let opened = LockedBox<Document>()
        let changed = LockedBox<Document>()
        let closed = LockedBox<DocumentID>()

        let handlers = LSPDocumentSyncHandlers(
            onOpen: { document, languageID, version in
                XCTAssertEqual(languageID, "swift")
                XCTAssertEqual(version, 1)
                opened.value = document
            },
            onFullChange: { document, version in
                XCTAssertEqual(version, 2)
                changed.value = document
            },
            onClose: { documentID in
                closed.value = documentID
            }
        )

        let bridge = LSPWorkspaceSyncBridge(
            handlers: handlers,
            languageResolver: { _ in "swift" }
        )
        let workspace = Workspace()
        await bridge.connect(to: workspace)

        let document = makeDocument(text: "let a = 1")
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

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(opened.value?.contentSnapshot.text, "let a = 1")
        if let changedDocument = changed.value {
            XCTAssertEqual(changedDocument.contentSnapshot.text, "let a = 2")
        } else {
            XCTFail("Expected document change handler")
        }
        XCTAssertEqual(closed.value, document.id)
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
