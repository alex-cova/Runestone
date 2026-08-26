import Foundation

/// Navigation provider that looks up the word under the cursor and returns all indexed locations.
public actor FindReferencesProvider: NavigationProvider {
    public let name = "FindReferences"
    private let index: SymbolIndex

    public init(index: SymbolIndex) {
        self.index = index
    }

    public func provide(context: NavigationContext) async -> NavigationResult? {
        let target = context.document.wordAtCursor()
        guard !target.isEmpty else { return nil }
        let symbols = await index.search(exact: target)
        guard !symbols.isEmpty else { return nil }
        let locations = symbols.map { symbol in
            Location(
                documentID: symbol.documentID,
                url: nil,
                range: symbol.range,
                displayName: symbol.name
            )
        }
        return .multiple(locations)
    }
}
