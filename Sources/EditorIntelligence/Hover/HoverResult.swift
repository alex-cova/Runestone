import Foundation

/// A single hover result produced by a provider.
///
/// `contents` is expected to be Markdown; the UI bridge can render it as needed.
public struct HoverResult: Sendable, CustomStringConvertible {
    public let contents: String
    public let range: TextRange?
    public let source: String

    public init(
        contents: String,
        range: TextRange? = nil,
        source: String
    ) {
        self.contents = contents
        self.range = range
        self.source = source
    }

    public var description: String {
        "Hover from \(source) over \(range.map { String(describing: $0) } ?? "unknown")"
    }
}
