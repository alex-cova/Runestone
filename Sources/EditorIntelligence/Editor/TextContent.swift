import Foundation

/// Read-only snapshot of a document's text content.
public struct TextSnapshot: Hashable, Sendable {
    public let version: Int
    /// UTF-16 length of the document.
    public let utf16Length: Int
    /// Full text when the adapter materialized it. `nil` for large file-backed documents.
    public let text: String?
    /// Ranged reader used when ``text`` is elided. Excluded from ``Hashable``.
    public let rangeReader: TextRangeReader?

    public init(version: Int, text: String) {
        self.version = version
        self.utf16Length = (text as NSString).length
        self.text = text
        self.rangeReader = nil
    }

    public init(version: Int, utf16Length: Int, text: String?, rangeReader: TextRangeReader? = nil) {
        self.version = version
        self.utf16Length = utf16Length
        self.text = text
        self.rangeReader = rangeReader
    }

    public var isElided: Bool {
        text == nil
    }

    public func substring(utf16Offset: Int, length: Int) -> String {
        if let text {
            let ns = text as NSString
            let location = max(0, min(utf16Offset, ns.length))
            let take = max(0, min(length, ns.length - location))
            guard take > 0 else {
                return ""
            }
            return ns.substring(with: NSRange(location: location, length: take))
        }
        return rangeReader?.substring(utf16Offset: utf16Offset, length: length) ?? ""
    }

    public static func == (lhs: TextSnapshot, rhs: TextSnapshot) -> Bool {
        lhs.version == rhs.version && lhs.utf16Length == rhs.utf16Length && lhs.text == rhs.text
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        hasher.combine(utf16Length)
        hasher.combine(text)
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
