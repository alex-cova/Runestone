import Foundation

/// A placeholder inside an expanded snippet, identified by a tab-stop number.
///
/// Offsets are UTF-16 offsets relative to the start of the expanded snippet text. The editor can
/// map these offsets to document coordinates after applying the snippet.
public struct SnippetPlaceholder: Sendable, Identifiable, CustomStringConvertible, Hashable {
    public let id: Int
    public let startOffset: Int
    public let length: Int
    public let defaultText: String
    public let children: [SnippetPlaceholder]

    public var endOffset: Int { startOffset + length }
    public var description: String {
        "\(id) [\(startOffset)-\(endOffset)]"
    }

    public init(
        id: Int,
        startOffset: Int,
        length: Int,
        defaultText: String,
        children: [SnippetPlaceholder] = []
    ) {
        self.id = id
        self.startOffset = startOffset
        self.length = length
        self.defaultText = defaultText
        self.children = children
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(startOffset)
        hasher.combine(length)
        hasher.combine(defaultText)
        hasher.combine(children)
    }
}
