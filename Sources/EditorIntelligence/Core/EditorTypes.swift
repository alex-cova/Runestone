import Foundation

/// Stable identifier for a document.
public struct DocumentID: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let uuid: UUID

    public init(_ uuid: UUID = UUID()) {
        self.uuid = uuid
    }

    public var description: String {
        uuid.uuidString
    }
}

/// Stable identifier for an editor adapter instance.
public struct EditorAdapterID: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let uuid: UUID

    public init(_ uuid: UUID = UUID()) {
        self.uuid = uuid
    }

    public var description: String {
        uuid.uuidString
    }
}

/// Coordinate system used by positions in the editor abstraction layer.
public struct TextPosition: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let line: Int
    public let column: Int
    public let utf16Offset: Int

    public init(line: Int, column: Int, utf16Offset: Int) {
        self.line = line
        self.column = column
        self.utf16Offset = utf16Offset
    }

    public var description: String {
        "\(line):\(column) [offset \(utf16Offset)]"
    }
}

/// Range of text in the editor abstraction layer.
public struct TextRange: Hashable, Equatable, Sendable {
    public let start: TextPosition
    public let end: TextPosition

    public init(start: TextPosition, end: TextPosition) {
        self.start = start
        self.end = end
    }

    public var isEmpty: Bool {
        start == end
    }
}

/// A single edit operation that can be applied to a document.
public struct TextEdit: Hashable, Sendable {
    public let range: TextRange
    public let replacement: String

    public init(range: TextRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}
