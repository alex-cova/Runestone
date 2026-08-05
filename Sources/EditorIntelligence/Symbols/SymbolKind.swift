import Foundation

/// Classification of a symbol in the index.
public enum SymbolKind: Hashable, Sendable, CustomStringConvertible {
    case function
    case type
    case variable
    case property
    case importStatement
    case fileName
    case word
    case unknown

    public var description: String {
        switch self {
        case .function: return "function"
        case .type: return "type"
        case .variable: return "variable"
        case .property: return "property"
        case .importStatement: return "import"
        case .fileName: return "fileName"
        case .word: return "word"
        case .unknown: return "unknown"
        }
    }
}
