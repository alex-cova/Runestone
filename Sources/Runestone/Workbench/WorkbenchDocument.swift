import CoreGraphics
import EditorIntelligence
import Foundation

/// In-memory document tracked by an ``EditorPane``.
public final class WorkbenchDocument: Identifiable {
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
    }

    public func makeEIPDocument(version: Int = 0) -> Document {
        let snapshot = TextSnapshot(version: version, text: text)
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
