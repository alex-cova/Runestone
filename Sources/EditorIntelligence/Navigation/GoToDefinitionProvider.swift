import Foundation

/// Navigation provider that looks up the word under the cursor and returns its definition location.
public actor GoToDefinitionProvider: NavigationProvider {
    public let name = "GoToDefinition"
    private let index: SymbolIndex

    public init(index: SymbolIndex) {
        self.index = index
    }

    public func provide(context: NavigationContext) async -> NavigationResult? {
        let target = context.document.wordAtCursor()
        guard !target.isEmpty else { return nil }
        let symbols = await index.search(exact: target)
        guard let symbol = symbols.first else { return nil }
        return .single(Location(
            documentID: symbol.documentID,
            url: nil,
            range: symbol.range,
            displayName: symbol.name
        ))
    }
}
