import Foundation

/// Classification of a completion item.
public enum CompletionItemKind: Hashable, Sendable, CustomStringConvertible {
    case text
    case keyword
    case function
    case method
    case property
    case variable
    case type
    case snippet
    case module
    case file

    public var description: String {
        switch self {
        case .text: return "text"
        case .keyword: return "keyword"
        case .function: return "function"
        case .method: return "method"
        case .property: return "property"
        case .variable: return "variable"
        case .type: return "type"
        case .snippet: return "snippet"
        case .module: return "module"
        case .file: return "file"
        }
    }
}

/// A single completion suggestion produced by a provider and later ranked by the completion engine.
public struct CompletionItem: Hashable, Sendable, Identifiable, CustomStringConvertible {
    public let id: UUID
    public let label: String
    public let insertText: String
    public let kind: CompletionItemKind
    public let range: TextRange
    public let source: String
    public let documentation: String?
    public let sortText: String?
    public let filterText: String?

    public init(
        id: UUID = UUID(),
        label: String,
        insertText: String,
        kind: CompletionItemKind,
        range: TextRange,
        source: String,
        documentation: String? = nil,
        sortText: String? = nil,
        filterText: String? = nil
    ) {
        self.id = id
        self.label = label
        self.insertText = insertText
        self.kind = kind
        self.range = range
        self.source = source
        self.documentation = documentation
        self.sortText = sortText
        self.filterText = filterText
    }

    public var description: String {
        "\(label) [\(kind)] from \(source)"
    }
}
