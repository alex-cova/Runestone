import Foundation

/// Presentation model for ghost text shown inline at the cursor.
public struct GhostTextModel: Sendable, CustomStringConvertible {
    public let text: String
    public let anchorPosition: TextPosition

    public init(text: String, anchorPosition: TextPosition) {
        self.text = text
        self.anchorPosition = anchorPosition
    }

    public var description: String {
        "GhostTextModel(\(text))"
    }
}
