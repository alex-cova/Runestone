import Foundation

final class StringViewBytesResult {
    // The bytes are not deallocated by this type.
    let bytes: UnsafePointer<Int8>
    let length: ByteCount

    init(bytes: UnsafePointer<Int8>, length: ByteCount) {
        self.bytes = bytes
        self.length = length
    }
}

/// Document text facade. Small / untitled buffers stay a contiguous `NSMutableString`.
/// ``TextViewState/load`` uses a file-backed ``PieceTree`` (mmap original + append-only add buffer).
final class StringView {
    private enum Storage {
        case contiguous(NSMutableString)
        case pieceTree(PieceTree)
    }

    private var storage: Storage

    /// UTF-16 length. Prefer this over ``string``.length so file-backed documents do not materialize.
    var length: Int {
        switch storage {
        case .contiguous(let string):
            return string.length
        case .pieceTree(let tree):
            return tree.utf16Length
        }
    }

    var byteCount: ByteCount {
        ByteCount(utf16Length: length)
    }

    var isFileBacked: Bool {
        if case .pieceTree = storage {
            return true
        }
        return false
    }

    /// Full-document `NSString`. Bridging a file-backed buffer allocates UTF-16 of the entire file.
    var string: NSString {
        get {
            switch storage {
            case .contiguous(let string):
                return string
            case .pieceTree(let tree):
                return tree.materializeNSString()
            }
        }
        set {
            storage = .contiguous(NSMutableString(string: newValue))
        }
    }

    init(string: NSMutableString = NSMutableString()) {
        self.storage = .contiguous(string)
    }

    convenience init(string: String) {
        self.init(string: NSMutableString(string: string))
    }

    init(pieceTree: PieceTree) {
        self.storage = .pieceTree(pieceTree)
    }

    func substring(in range: NSRange) -> String? {
        switch storage {
        case .contiguous(let string):
            guard range.location >= 0, range.upperBound <= string.length else {
                return nil
            }
            if range.length == 0 {
                return ""
            }
            return string.substring(with: range)
        case .pieceTree(let tree):
            return tree.substring(in: range)
        }
    }

    func character(at location: Int) -> Character? {
        switch storage {
        case .contiguous(let string):
            if location >= 0 && location < string.length, let scalar = Unicode.Scalar(string.character(at: location)) {
                return Character(scalar)
            }
            return nil
        case .pieceTree(let tree):
            return tree.character(at: location)
        }
    }

    func replaceText(in range: NSRange, with string: String) {
        RunestoneSignposts.interval("StringView.replaceText") {
            switch storage {
            case .contiguous(let mutable):
                mutable.replaceCharacters(in: range, with: string)
            case .pieceTree(let tree):
                tree.replaceText(in: range, with: string)
            }
        }
    }

    func bytes(in range: ByteRange) -> StringViewBytesResult? {
        switch storage {
        case .contiguous:
            guard range.lowerBound.value >= 0 && range.upperBound <= byteCount else {
                return nil
            }
            let stringRange = NSRange(range)
            var usedLength = 0
            if let buffer = string.getBytes(in: stringRange, encoding: String.preferredUTF16Encoding, usedLength: &usedLength) {
                return StringViewBytesResult(bytes: buffer, length: ByteCount(usedLength))
            }
            return nil
        case .pieceTree(let tree):
            return tree.bytes(in: range)
        }
    }

    func rangeOfNextNewLine(startingAt location: Int) -> NSRange? {
        switch storage {
        case .contiguous(let string):
            return NewLineFinder.rangeOfNextNewLine(in: string, startingAt: location)
        case .pieceTree(let tree):
            return tree.rangeOfNextNewLine(startingAt: location)
        }
    }

    func rangeOfComposedCharacterSequence(at location: Int) -> NSRange {
        switch storage {
        case .contiguous(let string):
            return string.customRangeOfComposedCharacterSequence(at: location)
        case .pieceTree(let tree):
            return tree.rangeOfComposedCharacterSequence(at: location)
        }
    }

    func enumerateSubstrings(
        in range: NSRange,
        options: NSString.EnumerationOptions,
        using block: @escaping (String?, NSRange, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        switch storage {
        case .contiguous(let string):
            string.enumerateSubstrings(in: range, options: options, using: block)
        case .pieceTree(let tree):
            tree.enumerateSubstrings(in: range, options: options, using: block)
        }
    }

    func prefetch(utf16Range: NSRange) {
        if case .pieceTree(let tree) = storage {
            tree.prefetch(utf16Range: utf16Range)
        }
    }

    func contentSnapshot() -> PieceTreeContentSnapshot? {
        if case .pieceTree(let tree) = storage {
            return tree.contentSnapshot()
        }
        return nil
    }

    var materializeCount: Int {
        if case .pieceTree(let tree) = storage {
            return tree.materializeCount
        }
        return 0
    }

    var pieceCount: Int {
        if case .pieceTree(let tree) = storage {
            return tree.pieceCount
        }
        return 1
    }

    var lastPrefetchByteCount: Int {
        if case .pieceTree(let tree) = storage {
            return tree.lastPrefetchByteCount
        }
        return 0
    }

    func unichar(at location: Int) -> unichar? {
        switch storage {
        case .contiguous(let string):
            guard location >= 0, location < string.length else {
                return nil
            }
            return string.character(at: location)
        case .pieceTree(let tree):
            return tree.unichar(at: location)
        }
    }
}
