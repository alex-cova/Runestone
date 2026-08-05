import Foundation

/// Result of applying a refactoring operation.
///
/// The engine returns the concrete text edits to apply and the documents affected by them.
public struct RefactoringResult: Sendable, CustomStringConvertible {
    public let operationName: String
    public let summary: String
    public let edits: [TextEdit]
    public let affectedDocuments: [DocumentID]

    public init(
        operationName: String,
        summary: String,
        edits: [TextEdit],
        affectedDocuments: [DocumentID] = []
    ) {
        self.operationName = operationName
        self.summary = summary
        self.edits = edits
        self.affectedDocuments = affectedDocuments
    }

    public var description: String {
        "\(operationName): \(summary) (\(edits.count) edits)"
    }
}
