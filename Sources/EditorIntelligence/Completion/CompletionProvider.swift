import Foundation

/// A provider that produces completion suggestions for a given context.
public protocol CompletionProvider: Sendable {
    /// Human-readable provider name, used for tracing and ranking weights.
    var name: String { get }

    /// Produce completion items for the given context.
    func provide(context: CompletionContext) async -> [CompletionItem]
}
