import Foundation

/// A symbol entry in the document outline tree.
public struct OutlineItem: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let kind: SymbolKind
    public let range: TextRange
    public let children: [OutlineItem]

    public init(
        id: UUID = UUID(),
        title: String,
        kind: SymbolKind,
        range: TextRange,
        children: [OutlineItem] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.range = range
        self.children = children
    }
}

/// Builds a hierarchical outline from flat symbol lists using range nesting.
public enum OutlineBuilder {
    private static let outlineKinds: Set<SymbolKind> = [
        .function, .type, .variable, .property, .importStatement
    ]

    /// Build a tree of outline items from document symbols.
    public static func build(from symbols: [Symbol]) -> [OutlineItem] {
        let candidates = symbols
            .filter { outlineKinds.contains($0.kind) }
            .sorted {
                if $0.range.start.utf16Offset == $1.range.start.utf16Offset {
                    return span(of: $0) > span(of: $1)
                }
                return $0.range.start.utf16Offset < $1.range.start.utf16Offset
            }
        return buildTree(from: candidates, within: nil)
    }

    private static func buildTree(from symbols: [Symbol], within parent: Symbol?) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var index = 0
        while index < symbols.count {
            let symbol = symbols[index]
            guard isDirectChild(symbol, of: parent, among: symbols) else {
                index += 1
                continue
            }
            let childSymbols = symbols[(index + 1)...]
            let children = buildTree(from: Array(childSymbols), within: symbol)
            items.append(OutlineItem(
                id: symbol.id,
                title: symbol.name,
                kind: symbol.kind,
                range: symbol.range,
                children: children
            ))
            index += 1
        }
        return items
    }

    private static func isDirectChild(_ symbol: Symbol, of parent: Symbol?, among symbols: [Symbol]) -> Bool {
        let start = symbolStart(of: symbol)
        let end = symbolEnd(of: symbol)
        if let parent {
            let parentStart = symbolStart(of: parent)
            let parentEnd = symbolEnd(of: parent)
            guard start >= parentStart, end <= parentEnd else {
                return false
            }
            return !symbols.contains(where: { other in
                guard other.id != symbol.id, other.id != parent.id else { return false }
                let otherStart = symbolStart(of: other)
                let otherEnd = symbolEnd(of: other)
                return otherStart >= parentStart
                    && otherEnd <= parentEnd
                    && otherStart <= start
                    && otherEnd >= end
                    && span(of: other) < span(of: symbol)
            })
        }
        return !symbols.contains(where: { other in
            guard other.id != symbol.id else { return false }
            let otherStart = symbolStart(of: other)
            let otherEnd = symbolEnd(of: other)
            return otherStart <= start && otherEnd >= end && span(of: other) > span(of: symbol)
        })
    }

    private static func symbolStart(of symbol: Symbol) -> Int {
        min(symbol.range.start.utf16Offset, symbol.range.end.utf16Offset)
    }

    private static func symbolEnd(of symbol: Symbol) -> Int {
        max(symbol.range.start.utf16Offset, symbol.range.end.utf16Offset)
    }

    private static func span(of symbol: Symbol) -> Int {
        symbolEnd(of: symbol) - symbolStart(of: symbol)
    }
}
