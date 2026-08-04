import Foundation

/// Context passed to completion providers.
public struct CompletionContext: Sendable, CustomStringConvertible {
    public let document: Document
    public let cursor: Cursor
    public let trigger: RequestTrigger
    public let prefix: String
    public let range: TextRange

    public init(
        document: Document,
        cursor: Cursor,
        trigger: RequestTrigger,
        prefix: String,
        range: TextRange
    ) {
        self.document = document
        self.cursor = cursor
        self.trigger = trigger
        self.prefix = prefix
        self.range = range
    }

    public var description: String {
        "Completion in \(document.displayName) at \(cursor.position) prefix='\(prefix)'"
    }
}
