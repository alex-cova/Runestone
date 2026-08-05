import Foundation

/// A provider that produces diagnostics for a document.
public protocol DiagnosticProvider: Sendable {
    /// Human-readable provider name, used for tracing.
    var name: String { get }

    /// Produce diagnostics for the given document.
    func diagnostics(for document: Document) async -> [Diagnostic]
}
