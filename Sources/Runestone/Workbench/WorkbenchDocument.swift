import CoreGraphics
import EditorIntelligence
import Foundation

/// In-memory document tracked by an ``EditorPane``.
public final class WorkbenchDocument: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let documentID: DocumentID
    public var url: URL?
    public var displayName: String
    public var text: String
    public var language: TreeSitterLanguage?
    public var languageIdentifier: String?
    public var isDirty: Bool
    public var selectedRange: NSRange
    public var scrollOffset: CGPoint
    /// One-shot `TextViewState` from ``load(contentsOf:language:languageIdentifier:parsePolicy:io:)``.
    /// Consumed on first apply so the workbench does not rebuild the line index from `text`.
    public var pendingState: TextViewState?
    /// True when the document was loaded as a file-backed piece tree (no `text` copy).
    public var isFileBacked: Bool
    /// Ranged reader for file-backed buffers so EIP snapshots can substring without full text.
    public var rangeReader: TextRangeReader?

    public init(
        id: UUID = UUID(),
        documentID: DocumentID = DocumentID(),
        url: URL? = nil,
        displayName: String = "Untitled",
        text: String = "",
        language: TreeSitterLanguage? = nil,
        languageIdentifier: String? = nil,
        isDirty: Bool = false,
        selectedRange: NSRange = NSRange(location: 0, length: 0),
        scrollOffset: CGPoint = .zero
    ) {
        self.id = id
        self.documentID = documentID
        self.url = url
        self.displayName = displayName
        self.text = text
        self.language = language
        self.languageIdentifier = languageIdentifier
        self.isDirty = isDirty
        self.selectedRange = selectedRange
        self.scrollOffset = scrollOffset
        self.isFileBacked = false
        self.rangeReader = nil
    }

    /// Loads a document from disk via mmap ingest (falling back to streamed reads).
    ///
    /// The returned document carries ``pendingState`` so the first ``TextView/setState`` can reuse
    /// the line index built during load instead of scanning `text` again.
    public static func load(
        contentsOf url: URL,
        language: TreeSitterLanguage? = nil,
        languageIdentifier: String? = nil,
        parsePolicy: SyntaxParsePolicy = .viewport,
        io: DocumentLoadIO = .memoryMapped
    ) async throws -> WorkbenchDocument {
        let prepared = try await RunestoneStateBuilder.load(
            contentsOf: url,
            language: language,
            parsePolicy: parsePolicy,
            io: io
        )
        let document = WorkbenchDocument(
            url: url,
            displayName: url.lastPathComponent,
            text: "",
            language: language,
            languageIdentifier: languageIdentifier
        )
        document.pendingState = prepared.state
        document.isFileBacked = prepared.state.stringView.isFileBacked
        if document.isFileBacked, let snapshot = prepared.state.stringView.contentSnapshot() {
            document.rangeReader = TextRangeReader(utf16Length: snapshot.utf16Length) { offset, length in
                snapshot.substring(utf16Offset: offset, length: length)
            }
        }
        return document
    }

    public func makeEIPDocument(version: Int = 0) -> Document {
        let snapshot: TextSnapshot
        if isFileBacked {
            let length = rangeReader?.utf16Length ?? pendingState?.stringView.length ?? (text as NSString).length
            snapshot = TextSnapshot(version: version, utf16Length: length, text: nil, rangeReader: rangeReader)
        } else {
            snapshot = TextSnapshot(version: version, text: text)
        }
        let start = TextPosition(
            line: 0,
            column: selectedRange.location,
            utf16Offset: selectedRange.location
        )
        let end = TextPosition(
            line: 0,
            column: selectedRange.location + selectedRange.length,
            utf16Offset: selectedRange.location + selectedRange.length
        )
        let selection = Selection(range: EditorIntelligence.TextRange(start: start, end: end))
        return Document(
            id: documentID,
            url: url,
            displayName: displayName,
            contentSnapshot: snapshot,
            selection: selection,
            cursor: Cursor(position: start),
            viewport: Viewport(x: Double(scrollOffset.x), y: Double(scrollOffset.y), width: 0, height: 0),
            languageIdentifier: languageIdentifier
        )
    }
}
