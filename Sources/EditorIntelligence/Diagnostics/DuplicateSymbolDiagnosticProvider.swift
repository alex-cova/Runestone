import Foundation

/// Diagnostic provider that reports duplicate symbol names within the same document.
public actor DuplicateSymbolDiagnosticProvider: DiagnosticProvider {
    public let name = "DuplicateSymbol"
    private let index: SymbolIndex

    public init(index: SymbolIndex) {
        self.index = index
    }

    public func diagnostics(for document: Document) async -> [Diagnostic] {
        let symbols = await index.symbols(in: document.id)
        var buckets: [String: [Symbol]] = [:]
        for symbol in symbols {
            buckets[symbol.name, default: []].append(symbol)
        }
        var diagnostics: [Diagnostic] = []
        for (_, symbols) in buckets where symbols.count > 1 {
            for symbol in symbols.dropFirst() {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    message: "Duplicate symbol '\(symbol.name)'",
                    range: symbol.range,
                    source: name,
                    code: "duplicate-symbol"
                ))
            }
        }
        return diagnostics
    }
}
