import Foundation

/// A completion item with a computed score, produced by a `Ranker`.
public struct RankedCompletionItem: Sendable, CustomStringConvertible {
    public let item: CompletionItem
    public let score: Double

    public init(item: CompletionItem, score: Double) {
        self.item = item
        self.score = score
    }

    public var description: String {
        "\(item.label) score=\(score)"
    }
}

/// Ranks completion items for a given context.
public protocol Ranker: Sendable {
    func rank(items: [CompletionItem], context: CompletionContext) async -> [RankedCompletionItem]
}
