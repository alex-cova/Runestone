import Foundation

/// Context passed to navigation providers when the editor requests navigation.
public struct NavigationContext: Sendable, CustomStringConvertible {
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
        "Navigation in \(document.displayName) at \(cursor.position)"
    }
}
