import Foundation

/// Hover provider that looks up the word at the cursor in the symbol index and returns its
/// documentation or signature as Markdown.
public actor SymbolHoverProvider: HoverProvider {
    public let name = "Symbol"
    private let index: SymbolIndex

    public init(index: SymbolIndex) {
        self.index = index
    }

    public func provide(context: HoverContext) async -> HoverResult? {
        let word = context.document.wordAtCursor()
        guard !word.isEmpty else { return nil }
        let symbols = await index.search(exact: word)
        guard let symbol = symbols.first else { return nil }
        let contents = symbol.documentation ?? symbol.signature ?? symbol.name
        return HoverResult(
            contents: contents,
            range: symbol.range,
            source: name
        )
    }
}
