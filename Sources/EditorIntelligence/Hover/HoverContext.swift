import Foundation

/// Context passed to hover providers when the editor requests hover information.
public struct HoverContext: Sendable, CustomStringConvertible {
    public let document: Document
    public let cursor: Cursor
    public let selection: Selection
    public let trigger: RequestTrigger

    public init(
        document: Document,
        cursor: Cursor,
        selection: Selection,
        trigger: RequestTrigger = .manual
    ) {
        self.document = document
        self.cursor = cursor
        self.selection = selection
        self.trigger = trigger
    }

    public var description: String {
        "Hover in \(document.displayName) at \(cursor.position)"
    }
}
