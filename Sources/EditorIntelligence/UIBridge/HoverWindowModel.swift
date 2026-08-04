import Foundation

/// Presentation model for a hover window.
public struct HoverWindowModel: Sendable, CustomStringConvertible {
    public let contents: String
    public let anchorRange: TextRange
    public let isMarkdown: Bool

    public init(
        contents: String,
        anchorRange: TextRange,
        isMarkdown: Bool = true
    ) {
        self.contents = contents
        self.anchorRange = anchorRange
        self.isMarkdown = isMarkdown
    }

    public var description: String {
        "HoverWindowModel(\(contents.prefix(40)))"
    }
}
