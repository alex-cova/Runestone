import Foundation

/// A symbol extracted from a document and stored in the index.
public struct Symbol: Hashable, Sendable, Identifiable, CustomStringConvertible {
    public let id: UUID
    public let name: String
    public let kind: SymbolKind
    public let documentID: DocumentID
    /// The symbol's identifying range — for a declaration, its name.
    public let range: TextRange
    /// The whole declaration body, when the symbol is a declaration whose extent is larger than
    /// its name (a function, a type). `nil` for bare identifiers / references. Breadcrumbs and the
    /// outline use this for containment: a cursor inside a function body is inside its
    /// `containerRange` but not its `range`.
    public let containerRange: TextRange?
    public let signature: String?
    public let documentation: String?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: SymbolKind,
        documentID: DocumentID,
        range: TextRange,
        containerRange: TextRange? = nil,
        signature: String? = nil,
        documentation: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.documentID = documentID
        self.range = range
        self.containerRange = containerRange
        self.signature = signature
        self.documentation = documentation
    }

    /// The range used for containment tests — ``containerRange`` when present, else ``range``.
    public var enclosingRange: TextRange {
        containerRange ?? range
    }

    public var description: String {
        "\(name) [\(kind)] @ \(documentID) \(range)"
    }
}
