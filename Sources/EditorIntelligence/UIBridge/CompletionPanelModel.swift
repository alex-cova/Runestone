import Foundation

/// Presentation model for a completion panel.
public struct CompletionPanelModel: Sendable, Identifiable, CustomStringConvertible {
    public let id: UUID
    public let items: [CompletionItem]
    public let selectedIndex: Int?
    public let replacementRange: TextRange

    public init(
        id: UUID = UUID(),
        items: [CompletionItem],
        selectedIndex: Int? = nil,
        replacementRange: TextRange
    ) {
        self.id = id
        self.items = items
        self.selectedIndex = selectedIndex
        self.replacementRange = replacementRange
    }

    public var description: String {
        "CompletionPanelModel(\(items.count) items)"
    }
}
