import Foundation

/// A simple snippet definition.
///
/// Snippet expansion (placeholders, tab stops, transforms) is implemented in the dedicated snippet
/// engine in a later phase. This model is the minimal representation needed by the completion provider.
public struct Snippet: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let prefix: String
    public let body: String
    public let description: String?
    public let kind: CompletionItemKind

    public init(
        id: UUID = UUID(),
        prefix: String,
        body: String,
        description: String? = nil,
        kind: CompletionItemKind = .snippet
    ) {
        self.id = id
        self.prefix = prefix
        self.body = body
        self.description = description
        self.kind = kind
    }

    /// A small built-in catalog of useful snippets for testing and demonstration.
    public static let builtIn: [Snippet] = [
        Snippet(
            prefix: "func",
            body: "function ${1:name}(${2:args}) {\n\t$0\n}",
            description: "Function declaration"
        ),
        Snippet(
            prefix: "if",
            body: "if (${1:condition}) {\n\t$0\n}",
            description: "If statement"
        ),
        Snippet(
            prefix: "for",
            body: "for (let ${1:i} = 0; ${1:i} < ${2:length}; ${1:i}++) {\n\t$0\n}",
            description: "For loop"
        )
    ]
}
