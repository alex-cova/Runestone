import Foundation
import EditorIntelligence

/// Bridges a Runestone `TextView` to the Editor Intelligence Platform.
///
/// The adapter is non-isolated on the surface: it caches a `Document` snapshot so that EIP
/// services can read `currentDocument` and `openDocuments` without entering `MainActor`. Edits
/// and focus changes are async and run on the main actor because they touch UI. The adapter
/// becomes the `TextView`'s `editorDelegate` and emits `EditorEvent`s for text and selection changes.
public final class RunestoneEditorAdapter: EditorAdapter {
    public let id: EditorAdapterID
    public let context: EditorContext
    public var events: AsyncStream<EditorEvent> { eventBus.events }

    private(set) weak var textView: TextView?
    private let eventBus = EventBus<EditorEvent>()
    private let documentID: DocumentID
    private let lock = NSLock()
    private var latestDocument: Document?

    /// Create an adapter for a Runestone text view.
    /// - Parameters:
    ///   - textView: The text view to bridge.
    ///   - context: Editor context; defaults to a new context.
    public init(textView: TextView, context: EditorContext = EditorContext()) {
        self.textView = textView
        self.context = context
        self.id = context.adapterID
        self.documentID = DocumentID()
        textView.editorDelegate = self
        captureInitialDocument()
    }

    public var currentDocument: Document? {
        lock.withLock { latestDocument }
    }

    public var openDocuments: [Document] {
        lock.withLock { latestDocument.map { [$0] } ?? [] }
    }

    public func document(withID id: DocumentID) -> Document? {
        lock.withLock { id == documentID ? latestDocument : nil }
    }

    public func applyEdit(_ edit: TextEdit, toDocumentWithID documentID: DocumentID) async throws {
        guard documentID == self.documentID else {
            throw RunestoneEditorAdapterError.unknownDocumentID(documentID)
        }
        guard let textView = textView else {
            throw RunestoneEditorAdapterError.textViewDeallocated
        }
        let range = NSRange(
            location: edit.range.start.utf16Offset,
            length: edit.range.end.utf16Offset - edit.range.start.utf16Offset
        )
        await MainActor.run {
            textView.replace(range, withText: edit.replacement)
        }
    }

    public func focusRange(_ range: EditorIntelligence.TextRange, inDocumentWithID documentID: DocumentID) async throws {
        guard documentID == self.documentID else {
            throw RunestoneEditorAdapterError.unknownDocumentID(documentID)
        }
        guard let textView = textView else {
            throw RunestoneEditorAdapterError.textViewDeallocated
        }
        let nsRange = NSRange(
            location: range.start.utf16Offset,
            length: range.end.utf16Offset - range.start.utf16Offset
        )
        await MainActor.run {
            textView.selectedRanges = [nsRange]
        }
    }

    // MARK: - Snapshotting

    private func captureInitialDocument() {
        Task { @MainActor in
            guard let textView = textView else { return }
            let document = makeDocument(with: textView)
            setLatestDocument(document)
            eventBus.send(.documentOpened(document))
        }
    }

    private func refreshDocument() {
        Task { @MainActor in
            guard let textView = textView else { return }
            let document = makeDocument(with: textView)
            setLatestDocument(document)
            eventBus.send(.documentChanged(document.id, document.contentSnapshot))
        }
    }

    /// Builds a fresh document, re-bridging the text view's content into a new `TextSnapshot`.
    ///
    /// - Important: This copies the entire document (`NSMutableString` -> `String` bridging is
    ///   eager and unavoidable for a mutable backing store). Only call this when content has
    ///   actually changed; for selection/cursor-only updates use
    ///   ``makeDocument(with:snapshot:)`` to reuse the previous snapshot instead.
    private func makeDocument(with textView: TextView) -> Document {
        let text = textView.text as String
        let snapshot = TextSnapshot(version: nextVersion(), text: text)
        return makeDocument(with: textView, snapshot: snapshot)
    }

    /// Builds a document reusing an existing content snapshot, only recomputing
    /// selection/cursor/viewport. Used for selection-only changes so they don't pay the cost of
    /// re-bridging the full document text.
    private func makeDocument(with textView: TextView, snapshot: TextSnapshot) -> Document {
        let selection = makeSelection(from: textView.selectedRanges, in: textView)
        let cursor = Cursor(position: selection.range.start)
        let viewport = Viewport(
            x: Double(textView.contentOffset.x),
            y: Double(textView.contentOffset.y),
            width: Double(textView.frame.width),
            height: Double(textView.frame.height)
        )
        return Document(
            id: documentID,
            url: context.rootProjectURL,
            displayName: context.rootProjectURL?.lastPathComponent ?? "Untitled",
            contentSnapshot: snapshot,
            selection: selection,
            cursor: cursor,
            viewport: viewport,
            languageIdentifier: nil
        )
    }

    private func makeSelection(from ranges: [NSRange], in textView: TextView) -> Selection {
        guard let primary = ranges.first else {
            let position = makePosition(at: 0, in: textView)
            let range = EditorIntelligence.TextRange(start: position, end: position)
            return Selection(range: range)
        }
        let primaryRange = makeTextRange(from: primary, in: textView)
        let additionalRanges = ranges.dropFirst().map { makeTextRange(from: $0, in: textView) }
        return Selection(range: primaryRange, additionalRanges: additionalRanges)
    }

    private func makeTextRange(from range: NSRange, in textView: TextView) -> EditorIntelligence.TextRange {
        let start = makePosition(at: range.location, in: textView)
        let end = makePosition(at: range.location + range.length, in: textView)
        return EditorIntelligence.TextRange(start: start, end: end)
    }

    private func makeSelection(from range: NSRange, in textView: TextView) -> Selection {
        makeSelection(from: [range], in: textView)
    }

    private func makePosition(at offset: Int, in textView: TextView) -> TextPosition {
        let textLocation = textView.textLocation(at: offset)
        return TextPosition(
            line: textLocation?.lineNumber ?? 0,
            column: textLocation?.column ?? offset,
            utf16Offset: offset
        )
    }

    private func nextVersion() -> Int {
        lock.withLock {
            let version = (latestDocument?.version ?? -1) + 1
            return version
        }
    }

    private func setLatestDocument(_ document: Document) {
        lock.withLock { latestDocument = document }
    }
}

// MARK: - TextViewDelegate
extension RunestoneEditorAdapter: TextViewDelegate {
    public func textViewDidChange(_ textView: TextView) {
        refreshDocument()
    }

    public func textViewDidChangeSelection(_ textView: TextView) {
        Task { @MainActor in
            guard textView === self.textView else { return }
            // Selection/cursor movement doesn't change document content, so reuse the existing
            // content snapshot instead of re-bridging the entire NSMutableString into a new
            // String. This is what makes arrow-key navigation and mouse clicks on large
            // documents cheap: previously every selection change paid the same full-document
            // copy as an actual edit.
            let snapshot = currentDocument?.contentSnapshot
                ?? TextSnapshot(version: nextVersion(), text: textView.text as String)
            let document = makeDocument(with: textView, snapshot: snapshot)
            setLatestDocument(document)
            eventBus.send(.selectionChanged(document.id, document.selection))
            eventBus.send(.cursorMoved(document.id, document.cursor))
        }
    }
}

public enum RunestoneEditorAdapterError: Error {
    case unknownDocumentID(DocumentID)
    case textViewDeallocated
}
