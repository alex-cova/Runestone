import Foundation

/// A concrete location in a document, returned by navigation providers.
public struct Location: Sendable, Hashable, Identifiable, CustomStringConvertible {
    public let id: UUID
    public let documentID: DocumentID
    public let url: URL?
    public let range: TextRange
    public let displayName: String

    public init(
        id: UUID = UUID(),
        documentID: DocumentID,
        url: URL? = nil,
        range: TextRange,
        displayName: String
    ) {
        self.id = id
        self.documentID = documentID
        self.url = url
        self.range = range
        self.displayName = displayName
    }

    public var description: String {
        "\(displayName) @ \(documentID) \(range)"
    }
}
