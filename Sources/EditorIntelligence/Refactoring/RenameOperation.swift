import Foundation

/// Refactoring operation that renames the symbol under the cursor across the indexed workspace.
///
/// The new name is supplied via the `newName` parameter.
public actor RenameOperation: RefactoringOperation {
    public let name = "Rename"

    public init() {}

    public func canApply(context: RefactoringContext) async -> Bool {
        let target = context.document.wordAtCursor()
        return !target.isEmpty
    }

    public func apply(context: RefactoringContext, parameters: [String: String]) async -> RefactoringResult {
        let oldName = context.document.wordAtCursor()
        let newName = parameters["newName"] ?? oldName
        guard !oldName.isEmpty else {
            return RefactoringResult(
                operationName: name,
                summary: "No symbol to rename",
                edits: []
            )
        }
        var edits: [TextEdit] = []
        var documentIDs: Set<DocumentID> = []
        if let index = context.index {
            let symbols = await index.search(exact: oldName)
            for symbol in symbols {
                edits.append(TextEdit(range: symbol.range, replacement: newName))
                documentIDs.insert(symbol.documentID)
            }
        }
        return RefactoringResult(
            operationName: name,
            summary: "Rename '\(oldName)' to '\(newName)'",
            edits: edits,
            affectedDocuments: Array(documentIDs)
        )
    }
}
