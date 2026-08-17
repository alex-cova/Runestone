import Foundation

/// Wraps the built-in tree-sitter language mode as a ``HighlightProviding`` source.
@MainActor
public final class TreeSitterHighlightProvider: HighlightProviding {
    private weak var textView: TextView?

    public init() {}

    public func setUp(textView: TextView) {
        self.textView = textView
    }

    public func applyEdit(
        range: NSRange,
        delta: Int,
        completion: @escaping @MainActor (Result<IndexSet, Error>) -> Void
    ) {
        var indices = IndexSet(integersIn: range.location..<(range.location + max(0, range.length + delta)))
        if delta > 0 {
            indices.insert(integersIn: range.location..<(range.location + delta))
        }
        completion(.success(indices))
    }

    public func queryHighlightsFor(
        range: NSRange,
        completion: @escaping @MainActor (Result<[SyntaxHighlightRange], Error>) -> Void
    ) {
        guard let textView else {
            completion(.success([]))
            return
        }
        var results: [SyntaxHighlightRange] = []
        var location = range.location
        let end = range.location + range.length
        while location < end {
            guard let node = textView.syntaxNode(at: location) else {
                location += 1
                continue
            }
            let start = textView.location(at: node.startLocation) ?? location
            let nodeEnd = textView.location(at: node.endLocation) ?? (location + 1)
            let nodeRange = NSRange(location: start, length: max(0, nodeEnd - start))
            let capped = nodeRange.intersection(range) ?? nodeRange
            if capped.length > 0 {
                results.append(SyntaxHighlightRange(range: capped, highlightName: node.type))
            }
            location = max(location + 1, nodeEnd)
        }
        completion(.success(results))
    }
}
