import Foundation

/// Read-only snapshot of a document's text content.
public struct TextSnapshot: Hashable, Sendable {
    public let version: Int
    public let text: String

    public init(version: Int, text: String) {
        self.version = version
        self.text = text
    }
}

/// Interface to the text content of a document.
///
/// Implementations are provided by the editor adapter and may be actor-isolated.
/// The EIP uses this to read snapshots and apply edits asynchronously.
public protocol TextContent: AnyObject {
    /// Read the current text of the document.
    var text: String { get }

    /// Capture a versioned snapshot of the text.
    func snapshot() -> TextSnapshot

    /// Apply an edit to the document.
    func applyEdit(_ edit: TextEdit) async throws
}
