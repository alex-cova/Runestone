import Foundation

public struct OutlineModel: Sendable {
    public let items: [OutlineItem]
    public let selectedItemID: UUID?

    public init(items: [OutlineItem], selectedItemID: UUID? = nil) {
        self.items = items
        self.selectedItemID = selectedItemID
    }
}
