import Foundation

/// A refactoring operation that produces concrete text edits for a given context.
public protocol RefactoringOperation: Sendable {
    /// Human-readable operation name, used for menus and tracing.
    var name: String { get }

    /// Determine whether this operation can be applied to the given context.
    func canApply(context: RefactoringContext) async -> Bool

    /// Apply the operation and return the edits to perform.
    func apply(context: RefactoringContext, parameters: [String: String]) async -> RefactoringResult
}
