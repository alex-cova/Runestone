import Foundation

/// Cursor (zero-length insertion point) in a document.
public struct Cursor: Hashable, Equatable, Sendable {
    public let position: TextPosition

    public init(position: TextPosition) {
        self.position = position
    }
}

/// Selection range in a document.
public struct Selection: Hashable, Equatable, Sendable {
    public let range: TextRange
    public let isReversed: Bool

    public init(range: TextRange, isReversed: Bool = false) {
        self.range = range
        self.isReversed = isReversed
    }

    public var isEmpty: Bool {
        range.isEmpty
    }
}

/// Visible viewport of a document.
public struct Viewport: Hashable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
