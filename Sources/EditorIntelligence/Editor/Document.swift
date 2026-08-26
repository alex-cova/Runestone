import Foundation

/// Immutable snapshot of a document exposed to the Editor Intelligence Platform.
public struct Document: Hashable, Sendable, Identifiable {
    public let id: DocumentID
    public let url: URL?
    public let displayName: String
    public let contentSnapshot: TextSnapshot
    public let selection: Selection
    public let cursor: Cursor
    public let viewport: Viewport
    public let languageIdentifier: String?

    public init(
        id: DocumentID = DocumentID(),
        url: URL? = nil,
        displayName: String,
        contentSnapshot: TextSnapshot,
        selection: Selection,
        cursor: Cursor,
        viewport: Viewport,
        languageIdentifier: String? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.contentSnapshot = contentSnapshot
        self.selection = selection
        self.cursor = cursor
        self.viewport = viewport
        self.languageIdentifier = languageIdentifier
    }

    public var text: String {
        contentSnapshot.text ?? ""
    }

    public var version: Int {
        contentSnapshot.version
    }

    /// UTF-16 slice that uses the snapshot's full text or its ranged reader.
    public func substring(utf16Offset: Int, length: Int) -> String {
        contentSnapshot.substring(utf16Offset: utf16Offset, length: length)
    }

    /// Text around the cursor, for prompts and word extraction on elided documents.
    public func textAroundCursor(radius: Int = 8_192) -> String {
        let offset = cursor.position.utf16Offset
        let start = max(0, offset - radius)
        let end = min(contentSnapshot.utf16Length, offset + radius)
        return substring(utf16Offset: start, length: max(0, end - start))
    }

    /// Word at the cursor using a bounded window so file-backed documents do not need full text.
    public func wordAtCursor(window: Int = 256) -> String {
        word(atUTF16Offset: cursor.position.utf16Offset, window: window)
    }

    public func word(atUTF16Offset offset: Int, window: Int = 256) -> String {
        let start = max(0, offset - window)
        let slice = substring(utf16Offset: start, length: min(window * 2, max(0, contentSnapshot.utf16Length - start)))
        return EditorIntelligence.word(at: offset - start, in: slice)
    }
}
