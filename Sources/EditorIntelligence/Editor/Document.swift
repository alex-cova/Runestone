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
        contentSnapshot.text
    }

    public var version: Int {
        contentSnapshot.version
    }
}
