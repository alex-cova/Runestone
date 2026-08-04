import Foundation

/// A single diagnostic message produced by a provider.
public struct Diagnostic: Sendable, Hashable, Identifiable, CustomStringConvertible {
    public let id: UUID
    public let severity: DiagnosticSeverity
    public let message: String
    public let range: TextRange
    public let source: String
    public let code: String?

    public init(
        id: UUID = UUID(),
        severity: DiagnosticSeverity,
        message: String,
        range: TextRange,
        source: String,
        code: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.range = range
        self.source = source
        self.code = code
    }

    public var description: String {
        "\(severity) [\(source)]: \(message)"
    }
}
