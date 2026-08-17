import Foundation

/// Performance guardrails for tree-sitter parsing and highlighting, adapted from CodeEditSourceEditor.
public enum TreeSitterPerformanceConstants {
    /// Maximum query matches per tree-sitter cursor invocation.
    public static var matchLimit = 256

    /// Parser timeout between cancellation checks (seconds).
    public static var parserTimeout: TimeInterval = 0.05

    /// Maximum edit length processed synchronously.
    public static var maxSyncEditLength = 1024

    /// Maximum document length for synchronous operations.
    public static var maxSyncContentLength = 1_000_000

    /// Maximum query length for synchronous highlight queries.
    public static var maxSyncQueryLength = 4096

    /// Duration before a long parse is considered noteworthy (seconds).
    public static var longParseTimeout: TimeInterval = 0.5

    public static let longParseNotification = Notification.Name("Runestone.longParseNotification")
    public static let longParseFinishedNotification = Notification.Name("Runestone.longParseFinishedNotification")
}
