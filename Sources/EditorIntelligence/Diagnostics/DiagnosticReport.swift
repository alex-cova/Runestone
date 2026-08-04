import Foundation

/// Aggregated diagnostics for a single document.
public struct DiagnosticReport: Sendable, CustomStringConvertible {
    public let documentID: DocumentID
    public let diagnostics: [Diagnostic]

    public init(documentID: DocumentID, diagnostics: [Diagnostic]) {
        self.documentID = documentID
        self.diagnostics = diagnostics
    }

    public var description: String {
        "DiagnosticReport(\(documentID): \(diagnostics.count) diagnostics)"
    }
}
