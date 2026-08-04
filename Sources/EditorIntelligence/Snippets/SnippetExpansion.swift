import Foundation

/// The result of expanding a snippet body into concrete text with placeholder coordinates.
public struct SnippetExpansion: Sendable, CustomStringConvertible {
    public let text: String
    public let placeholders: [SnippetPlaceholder]
    public let finalCursorOffset: Int?

    public init(text: String, placeholders: [SnippetPlaceholder], finalCursorOffset: Int?) {
        self.text = text
        self.placeholders = placeholders
        self.finalCursorOffset = finalCursorOffset
    }

    public var description: String {
        var base = "SnippetExpansion(text: \"\(text)\", placeholders: \(placeholders)"
        if let finalCursorOffset = finalCursorOffset {
            base += ", finalCursorOffset: \(finalCursorOffset)"
        }
        return base + ")"
    }
}
