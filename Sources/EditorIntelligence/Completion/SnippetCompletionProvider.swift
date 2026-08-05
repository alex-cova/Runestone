import Foundation

/// Suggests built-in snippets whose prefix matches the current completion prefix.
public actor SnippetCompletionProvider: CompletionProvider {
    public let name = "Snippet"
    private let snippets: [Snippet]

    public init(snippets: [Snippet] = Snippet.builtIn) {
        self.snippets = snippets
    }

    public func provide(context: CompletionContext) async -> [CompletionItem] {
        let prefix = context.prefix.lowercased()
        return snippets.compactMap { snippet in
            let snippetPrefix = snippet.prefix.lowercased()
            if prefix.isEmpty || snippetPrefix.hasPrefix(prefix) {
                return CompletionItem(
                    label: snippet.prefix,
                    insertText: snippet.body,
                    kind: snippet.kind,
                    range: context.range,
                    source: name,
                    documentation: snippet.description
                )
            }
            return nil
        }
    }
}
