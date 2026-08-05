import Foundation

/// Actor-isolated refactoring engine that discovers and executes registered operations.
public actor RefactoringEngine {
    private let operations: [RefactoringOperation]

    public init(operations: [RefactoringOperation]) {
        self.operations = operations
    }

    /// Return the operations that can be applied to the given context.
    public func availableOperations(for context: RefactoringContext) async -> [RefactoringOperation] {
        var available: [RefactoringOperation] = []
        for operation in operations {
            if await operation.canApply(context: context) {
                available.append(operation)
            }
        }
        return available
    }

    /// Apply the named operation with the supplied parameters.
    public func apply(
        operationName: String,
        context: RefactoringContext,
        parameters: [String: String] = [:]
    ) async -> RefactoringResult? {
        guard let operation = operations.first(where: { $0.name == operationName }) else {
            return nil
        }
        return await operation.apply(context: context, parameters: parameters)
    }
}
