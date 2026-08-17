import EditorIntelligence
import Foundation

extension TextViewDiagnostic {
    /// Creates a text-view diagnostic from an Editor Intelligence Platform diagnostic.
    public init(_ diagnostic: Diagnostic) {
        self.init(id: diagnostic.id.uuidString,
                  range: NSRange(location: diagnostic.range.start.utf16Offset,
                                 length: diagnostic.range.end.utf16Offset - diagnostic.range.start.utf16Offset),
                  severity: TextViewDiagnosticSeverity(diagnostic.severity))
    }
}

extension TextViewDiagnosticSeverity {
    init(_ severity: DiagnosticSeverity) {
        switch severity {
        case .error:
            self = .error
        case .warning:
            self = .warning
        case .information:
            self = .information
        case .hint:
            self = .hint
        }
    }
}
