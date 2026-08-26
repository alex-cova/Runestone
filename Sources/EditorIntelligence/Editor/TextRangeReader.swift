import Foundation

/// Sendable bounded reader for document text that does not require a full UTF-16 copy.
///
/// File-backed snapshots install a reader over the piece tree so EIP services can substring
/// around the cursor or walk the file in chunks without materializing `text`.
public final class TextRangeReader: @unchecked Sendable {
    public let utf16Length: Int
    private let impl: @Sendable (Int, Int) -> String

    public init(utf16Length: Int, substring: @escaping @Sendable (Int, Int) -> String) {
        self.utf16Length = utf16Length
        self.impl = substring
    }

    public func substring(utf16Offset: Int, length: Int) -> String {
        let location = max(0, utf16Offset)
        guard location < utf16Length else {
            return ""
        }
        let take = max(0, min(length, utf16Length - location))
        guard take > 0 else {
            return ""
        }
        return impl(location, take)
    }
}
