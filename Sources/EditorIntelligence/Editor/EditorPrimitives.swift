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
    /// Additional selection ranges for multi-cursor editing. The primary range is always in ``range``.
    public let additionalRanges: [TextRange]
    public let isReversed: Bool

    public init(range: TextRange, additionalRanges: [TextRange] = [], isReversed: Bool = false) {
        self.range = range
        self.additionalRanges = additionalRanges
        self.isReversed = isReversed
    }

    public var isEmpty: Bool {
        range.isEmpty && additionalRanges.allSatisfy(\.isEmpty)
    }

    /// All selection ranges, primary first.
    public var allRanges: [TextRange] {
        if additionalRanges.isEmpty {
            return [range]
        }
        return [range] + additionalRanges
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
