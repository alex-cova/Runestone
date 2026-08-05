import Foundation

/// A symbol extracted from a document and stored in the index.
public struct Symbol: Hashable, Sendable, Identifiable, CustomStringConvertible {
    public let id: UUID
    public let name: String
    public let kind: SymbolKind
    public let documentID: DocumentID
    public let range: TextRange
    public let signature: String?
    public let documentation: String?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: SymbolKind,
        documentID: DocumentID,
        range: TextRange,
        signature: String? = nil,
        documentation: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.documentID = documentID
        self.range = range
        self.signature = signature
        self.documentation = documentation
    }

    public var description: String {
        "\(name) [\(kind)] @ \(documentID) \(range)"
    }
}
