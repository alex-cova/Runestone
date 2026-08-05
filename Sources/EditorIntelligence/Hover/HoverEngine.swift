import Foundation

/// Actor-isolated hover engine that queries registered providers and optionally caches results.
///
/// Providers are run concurrently. The first non-nil result is returned and cached.
public actor HoverEngine {
    private let providers: [HoverProvider]
    private let cache: Cache<HoverCacheKey, HoverResult>?

    public init(
        providers: [HoverProvider],
        cache: Cache<HoverCacheKey, HoverResult>? = nil
    ) {
        self.providers = providers
        self.cache = cache
    }

    /// Request hover information for the given context.
    ///
    /// Returns the first non-nil result produced by the registered providers, or `nil` if no
    /// provider can resolve hover information for the context.
    public func hover(context: HoverContext) async -> HoverResult? {
        let key = HoverCacheKey(documentID: context.document.id, cursor: context.cursor)
        if let cached = await cache?.get(key) {
            return cached
        }
        var tasks: [Task<HoverResult?, Never>] = []
        for provider in providers {
            tasks.append(Task { await provider.provide(context: context) })
        }
        for (index, task) in tasks.enumerated() {
            if let result = await task.value {
                for remaining in tasks.suffix(from: index + 1) {
                    remaining.cancel()
                }
                await cache?.set(result, for: key)
                return result
            }
        }
        return nil
    }
}

/// Cache key for hover results.
public struct HoverCacheKey: Hashable, Sendable {
    public let documentID: DocumentID
    public let cursor: Cursor

    public init(documentID: DocumentID, cursor: Cursor) {
        self.documentID = documentID
        self.cursor = cursor
    }
}
