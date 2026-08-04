import Foundation

/// Query-based symbol search engine backed by the symbol index.
public actor SymbolSearchEngine {
    private let index: SymbolIndex

    public init(index: SymbolIndex) {
        self.index = index
    }

    /// Find symbols whose name begins with the given query.
    public func search(prefix query: String) async -> [Symbol] {
        await index.search(prefix: query)
    }

    /// Find symbols whose name matches the query exactly.
    public func search(exact name: String) async -> [Symbol] {
        await index.search(exact: name)
    }
}
