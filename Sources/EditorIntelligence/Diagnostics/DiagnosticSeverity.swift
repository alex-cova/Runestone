import Foundation

/// Severity level of a diagnostic.
public enum DiagnosticSeverity: Sendable, Hashable, CustomStringConvertible, Comparable {
    case error
    case warning
    case information
    case hint

    public var description: String {
        switch self {
        case .error: return "error"
        case .warning: return "warning"
        case .information: return "information"
        case .hint: return "hint"
        }
    }

    /// Sort order: error first, then warning, information, hint.
    public var sortOrder: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .information: return 2
        case .hint: return 3
        }
    }

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
