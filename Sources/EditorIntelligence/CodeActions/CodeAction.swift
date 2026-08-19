import Foundation

/// A single actionable fix or refactor offered at a cursor position.
public struct CodeAction: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let kind: String?
    public let edits: [TextEdit]
    public let isPreferred: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        kind: String? = nil,
        edits: [TextEdit],
        isPreferred: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.edits = edits
        self.isPreferred = isPreferred
    }
}
