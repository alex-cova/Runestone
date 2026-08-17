import Foundation

/// Batches document edits and forwards them to language-server sync handlers.
public actor LSPDocumentSyncService {
    public struct DocumentChange: Sendable {
        public let documentID: DocumentID
        public let range: LSPRange
        public let text: String

        public init(documentID: DocumentID, range: LSPRange, text: String) {
            self.documentID = documentID
            self.range = range
            self.text = text
        }
    }

    public typealias SyncHandler = @Sendable ([DocumentChange]) async -> Void

    private let batchIntervalNanoseconds: UInt64
    private let handlers: LSPDocumentSyncHandlers
    private var pending: [DocumentChange] = []
    private var task: Task<Void, Never>?

    public init(batchInterval: TimeInterval = 0.25, handlers: LSPDocumentSyncHandlers = LSPDocumentSyncHandlers()) {
        self.batchIntervalNanoseconds = UInt64(batchInterval * 1_000_000_000)
        self.handlers = handlers
    }

    public init(batchInterval: TimeInterval = 0.25, onSync: @escaping SyncHandler) {
        self.batchIntervalNanoseconds = UInt64(batchInterval * 1_000_000_000)
        self.handlers = LSPDocumentSyncHandlers(onIncrementalChanges: onSync)
    }

    public func notifyOpened(_ document: Document, languageID: String, version: Int) async {
        await handlers.onOpen(document, languageID, version)
    }

    public func notifyFullChange(_ document: Document, version: Int) async {
        await handlers.onFullChange(document, version)
    }

    public func documentOpened(_ document: Document, languageID: String, version: Int = 0) async {
        await notifyOpened(document, languageID: languageID, version: version)
    }

    public func enqueueChange(documentID: DocumentID, range: LSPRange, text: String) {
        pending.append(DocumentChange(documentID: documentID, range: range, text: text))
        scheduleFlush()
    }

    public func documentClosed(documentID: DocumentID) async {
        await flush()
        await handlers.onClose(documentID)
    }

    private func scheduleFlush() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.batchIntervalNanoseconds)
            await self.flush()
        }
    }

    private func flush() async {
        guard !pending.isEmpty else {
            return
        }
        let batch = pending
        pending = []
        await handlers.onIncrementalChanges(batch)
    }
}
