import Foundation

/// LSP-compatible position (0-based line and character).
public struct LSPPosition: Sendable, Hashable, CustomStringConvertible {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }

    public var description: String {
        "\(line):\(character)"
    }
}

/// LSP-compatible range.
public struct LSPRange: Sendable, Hashable, CustomStringConvertible {
    public let start: LSPPosition
    public let end: LSPPosition

    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }

    public var description: String {
        "\(start)-\(end)"
    }
}

/// LSP diagnostic payload.
public struct LSPDiagnostic: Sendable, Hashable {
    public let range: LSPRange
    public let severity: Int?
    public let message: String
    public let code: String?
    public let source: String?

    public init(range: LSPRange, severity: Int?, message: String, code: String? = nil, source: String? = nil) {
        self.range = range
        self.severity = severity
        self.message = message
        self.code = code
        self.source = source
    }
}

/// LSP hover payload.
public struct LSPHover: Sendable {
    public let contents: String
    public let range: LSPRange?

    public init(contents: String, range: LSPRange? = nil) {
        self.contents = contents
        self.range = range
    }
}

/// LSP completion item payload.
public struct LSPCompletionItem: Sendable, Hashable {
    public let label: String
    public let insertText: String?
    public let kind: Int?
    public let documentation: String?
    public let detail: String?

    public init(
        label: String,
        insertText: String? = nil,
        kind: Int? = nil,
        documentation: String? = nil,
        detail: String? = nil
    ) {
        self.label = label
        self.insertText = insertText
        self.kind = kind
        self.documentation = documentation
        self.detail = detail
    }
}
