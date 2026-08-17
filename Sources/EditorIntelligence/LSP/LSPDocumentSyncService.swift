import Foundation

/// Batches document edits and forwards them to a language server sync handler.
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
    private var pending: [DocumentChange] = []
    private var task: Task<Void, Never>?
    private let onSync: SyncHandler

    public init(batchInterval: TimeInterval = 0.25, onSync: @escaping SyncHandler) {
        self.batchIntervalNanoseconds = UInt64(batchInterval * 1_000_000_000)
        self.onSync = onSync
    }

    public func documentOpened(_ document: Document, languageID: String, version: Int = 0) async {
        await onSync([])
    }

    public func enqueueChange(documentID: DocumentID, range: LSPRange, text: String) {
        pending.append(DocumentChange(documentID: documentID, range: range, text: text))
        scheduleFlush()
    }

    public func documentClosed(documentID: DocumentID) async {
        await flush()
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
        await onSync(batch)
    }
}
