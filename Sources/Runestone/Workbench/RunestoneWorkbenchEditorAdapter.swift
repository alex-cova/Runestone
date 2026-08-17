import EditorIntelligence
import Foundation

/// ``EditorAdapter`` that aggregates open ``WorkbenchDocument``s and tracks the active pane's ``TextView``.
public final class RunestoneWorkbenchEditorAdapter: EditorAdapter {
    public let id: EditorAdapterID
    public let context: EditorContext
    public var events: AsyncStream<EditorEvent> { eventBus.events }

    public let workbench: EditorWorkbench
    public weak var textView: TextView?
    public weak var forwardingDelegate: TextViewDelegate?

    private let eventBus = EventBus<EditorEvent>()
    private let lock = NSLock()
    private var liveDocumentID: DocumentID?
    private var cachedOpenDocuments: [Document] = []

    public init(workbench: EditorWorkbench, textView: TextView? = nil, context: EditorContext = EditorContext()) {
        self.workbench = workbench
        self.textView = textView
        self.context = context
        self.id = context.adapterID
        if let textView {
            textView.editorDelegate = self
        }
        refreshCachedDocuments(emitEvents: false)
    }

    public var currentDocument: Document? {
        lock.withLock {
            if let liveDocumentID,
               let match = cachedOpenDocuments.first(where: { $0.id == liveDocumentID }) {
                return match
            }
            return workbench.activePane.selectedDocument.map { $0.makeEIPDocument() }
        }
    }

    public var openDocuments: [Document] {
        lock.withLock { cachedOpenDocuments }
    }

    public func document(withID id: DocumentID) -> Document? {
        lock.withLock { cachedOpenDocuments.first { $0.id == id } }
    }

    public func applyEdit(_ edit: TextEdit, toDocumentWithID documentID: DocumentID) async throws {
        guard let textView = textView else {
            throw RunestoneEditorAdapterError.textViewDeallocated
        }
        guard document(withID: documentID) != nil else {
            throw RunestoneEditorAdapterError.unknownDocumentID(documentID)
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
        guard document(withID: documentID) != nil else {
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

    public func refreshCachedDocuments(emitEvents: Bool = true) {
        let activePane = workbench.activePane
        let documents = workbench.allDocuments().map { $0.makeEIPDocument() }
        lock.withLock {
            cachedOpenDocuments = documents
            liveDocumentID = activePane.selectedDocument?.documentID
        }
        guard emitEvents else { return }
        for document in documents {
            eventBus.send(.documentChanged(document.id, document.contentSnapshot))
        }
        if let selected = activePane.selectedDocument {
            let doc = selected.makeEIPDocument()
            eventBus.send(.selectionChanged(doc.id, doc.selection))
            eventBus.send(.cursorMoved(doc.id, doc.cursor))
        }
    }

    func refreshLiveDocumentFromTextView(_ textView: TextView) {
        guard let selected = workbench.activePane.selectedDocument else { return }
        selected.text = textView.text
        selected.selectedRange = textView.selectedRange
        selected.scrollOffset = textView.contentOffset
        let document = selected.makeEIPDocument()
        lock.withLock {
            liveDocumentID = selected.documentID
            if let index = cachedOpenDocuments.firstIndex(where: { $0.id == document.id }) {
                cachedOpenDocuments[index] = document
            }
        }
        eventBus.send(.documentChanged(document.id, document.contentSnapshot))
        eventBus.send(.selectionChanged(document.id, document.selection))
        eventBus.send(.cursorMoved(document.id, document.cursor))
    }
}

extension RunestoneWorkbenchEditorAdapter: TextViewDelegate {
    public func textViewDidChange(_ textView: TextView) {
        refreshLiveDocumentFromTextView(textView)
        forwardingDelegate?.textViewDidChange(textView)
    }

    public func textViewDidChangeSelection(_ textView: TextView) {
        refreshLiveDocumentFromTextView(textView)
        forwardingDelegate?.textViewDidChangeSelection(textView)
    }

    public func textViewShouldBeginEditing(_ textView: TextView) -> Bool {
        forwardingDelegate?.textViewShouldBeginEditing(textView) ?? true
    }

    public func textViewShouldEndEditing(_ textView: TextView) -> Bool {
        forwardingDelegate?.textViewShouldEndEditing(textView) ?? true
    }

    public func textViewDidBeginEditing(_ textView: TextView) {
        forwardingDelegate?.textViewDidBeginEditing(textView)
    }

    public func textViewDidEndEditing(_ textView: TextView) {
        forwardingDelegate?.textViewDidEndEditing(textView)
    }

    public func textView(_ textView: TextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        forwardingDelegate?.textView(textView, shouldChangeTextIn: range, replacementText: text) ?? true
    }
}
