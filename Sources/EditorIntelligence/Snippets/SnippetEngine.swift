import Foundation

/// High-level snippet engine that parses a snippet body and expands it into concrete text.
///
/// The engine is stateless and can be used synchronously. It delegates parsing to
/// `SnippetParser` and expansion to `SnippetExpander`.
public struct SnippetEngine {
    public init() {}

    /// Expand a snippet using the given context to resolve variables and transforms.
    public func expand(_ snippet: Snippet, context: SnippetExpansionContext) -> SnippetExpansion {
        let nodes = SnippetParser().parse(snippet.body)
        return SnippetExpander(nodes: nodes, context: context).expand()
    }

    /// Expand a snippet body directly using the given context.
    public func expand(body: String, context: SnippetExpansionContext) -> SnippetExpansion {
        let nodes = SnippetParser().parse(body)
        return SnippetExpander(nodes: nodes, context: context).expand()
    }
}
