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
        let enclosing = symbols
            .filter { symbol in
                let start = min(symbol.range.start.utf16Offset, symbol.range.end.utf16Offset)
                let end = max(symbol.range.start.utf16Offset, symbol.range.end.utf16Offset)
                return start <= cursorOffset && cursorOffset <= end
            }
            .sorted { $0.range.start.utf16Offset < $1.range.start.utf16Offset }
        guard !enclosing.isEmpty else { return nil }
        let locations = enclosing.map { symbol in
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
