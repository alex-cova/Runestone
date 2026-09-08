import Foundation

/// Navigation provider that returns the symbols enclosing the current cursor position as a breadcrumb trail.
public actor BreadcrumbProvider: NavigationProvider {
    public let name = "Breadcrumb"
    private let index: SymbolIndex

    public init(index: SymbolIndex) {
        self.index = index
    }

    public func provide(context: NavigationContext) async -> NavigationResult? {
        let cursorOffset = context.cursor.position.utf16Offset
        let symbols = await index.symbols(in: context.document.id)
        let locations = Self.breadcrumbLocations(from: symbols, cursorOffset: cursorOffset)
        guard !locations.isEmpty else { return nil }
        return .multiple(locations)
    }

    /// Symbols that enclose `cursorOffset`, outermost first, as breadcrumb `Location`s.
    ///
    /// When any symbol carries a `containerRange` (a real declaration extent), only those are
    /// considered and nesting is by containment of that range — so a cursor in a function body
    /// resolves to `Type › function`. Without container ranges this falls back to the historical
    /// behaviour: every symbol whose (name) range spans the cursor, sorted by start offset.
    public static func breadcrumbLocations(from symbols: [Symbol], cursorOffset: Int) -> [Location] {
        let declarations = symbols.filter { $0.containerRange != nil }
        let candidates = declarations.isEmpty ? symbols : declarations
        let enclosing = candidates
            .filter { symbol in
                let range = symbol.enclosingRange
                let start = min(range.start.utf16Offset, range.end.utf16Offset)
                let end = max(range.start.utf16Offset, range.end.utf16Offset)
                return start <= cursorOffset && cursorOffset <= end
            }
            .sorted { lhs, rhs in
                let lhsStart = lhs.enclosingRange.start.utf16Offset
                let rhsStart = rhs.enclosingRange.start.utf16Offset
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                // Same start: outer (wider) span first.
                return span(of: lhs) > span(of: rhs)
            }
        return enclosing.map { symbol in
            Location(
                documentID: symbol.documentID,
                url: nil,
                range: symbol.range,
                displayName: symbol.name
            )
        }
    }

    private static func span(of symbol: Symbol) -> Int {
        let range = symbol.enclosingRange
        return abs(range.end.utf16Offset - range.start.utf16Offset)
    }
}
