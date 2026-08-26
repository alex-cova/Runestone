import Foundation

/// Performance guardrails for tree-sitter parsing and highlighting, adapted from CodeEditSourceEditor.
public enum TreeSitterPerformanceConstants {
    /// Maximum query matches per tree-sitter cursor invocation.
    nonisolated(unsafe) public static var matchLimit = 256

    /// Parser timeout between cancellation checks (seconds).
    nonisolated(unsafe) public static var parserTimeout: TimeInterval = 0.05

    /// Maximum edit length processed synchronously.
    nonisolated(unsafe) public static var maxSyncEditLength = 1024

    /// Maximum document length for synchronous operations.
    ///
    /// Also the cutoff for ``SyntaxParsePolicy/viewport``: documents at or below this UTF-16
    /// length are parsed in full so indent/outline/`syntaxNode(at:)` work everywhere.
    nonisolated(unsafe) public static var maxSyncContentLength = 1_000_000

    /// Cap on UTF-16 units included in a viewport parse of a larger document.
    nonisolated(unsafe) public static var maxViewportParseUTF16Length = 262_144

    /// Extra viewport heights parsed above and below the visible rect in viewport mode.
    nonisolated(unsafe) public static var viewportOverscanScreens: CGFloat = 2

    /// Maximum query length for synchronous highlight queries.
    nonisolated(unsafe) public static var maxSyncQueryLength = 4096

    /// Duration before a long parse is considered noteworthy (seconds).
    nonisolated(unsafe) public static var longParseTimeout: TimeInterval = 0.5

    public static let longParseNotification = Notification.Name("Runestone.longParseNotification")
    public static let longParseFinishedNotification = Notification.Name("Runestone.longParseFinishedNotification")
}
