import Foundation

/// Suggests indexed document words whose name matches the current completion prefix.
public actor WordCompletionProvider: CompletionProvider {
    public let name = "Word"
    private let index: SymbolIndex

    public init(index: SymbolIndex) {
        self.index = index
    }

    public func provide(context: CompletionContext) async -> [CompletionItem] {
        let prefix = context.prefix
        let symbols = await index.search(prefix: prefix)
        return symbols
            .filter { $0.kind == .word }
            .map { word in
                CompletionItem(
                    label: word.name,
                    insertText: word.name,
                    kind: .text,
                    range: context.range,
                    source: name
                )
            }
    }
}
