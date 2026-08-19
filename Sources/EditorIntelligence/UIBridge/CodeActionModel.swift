import Foundation

public struct CodeActionModel: Sendable {
    public let actions: [CodeAction]
    public let anchorRange: TextRange

    public init(actions: [CodeAction], anchorRange: TextRange) {
        self.actions = actions
        self.anchorRange = anchorRange
    }
}
