import Foundation

/// Callbacks fired when documents in an EIP ``Workspace`` should be mirrored to a language server.
public struct LSPDocumentSyncHandlers: Sendable {
    public var onIncrementalChanges: @Sendable ([LSPDocumentSyncService.DocumentChange]) async -> Void
    public var onOpen: @Sendable (Document, String, Int) async -> Void
    public var onFullChange: @Sendable (Document, Int) async -> Void
    public var onClose: @Sendable (DocumentID) async -> Void

    public init(
        onIncrementalChanges: @escaping @Sendable ([LSPDocumentSyncService.DocumentChange]) async -> Void = { _ in },
        onOpen: @escaping @Sendable (Document, String, Int) async -> Void = { _, _, _ in },
        onFullChange: @escaping @Sendable (Document, Int) async -> Void = { _, _ in },
        onClose: @escaping @Sendable (DocumentID) async -> Void = { _ in }
    ) {
        self.onIncrementalChanges = onIncrementalChanges
        self.onOpen = onOpen
        self.onFullChange = onFullChange
        self.onClose = onClose
    }
}

/// Subscribes to ``Workspace`` events and forwards document lifecycle notifications to LSP handlers.
public actor LSPWorkspaceSyncBridge {
  private let syncService: LSPDocumentSyncService
    private let languageResolver: @Sendable (Document) -> String
    private var versions: [DocumentID: Int] = [:]
    private var subscription: Task<Void, Never>?

    public init(
        handlers: LSPDocumentSyncHandlers = LSPDocumentSyncHandlers(),
        batchInterval: TimeInterval = 0.25,
        languageResolver: @escaping @Sendable (Document) -> String = { _ in "plaintext" }
    ) {
        self.syncService = LSPDocumentSyncService(batchInterval: batchInterval, handlers: handlers)
        self.languageResolver = languageResolver
    }

    @discardableResult
    public func connect(to workspace: Workspace) -> Task<Void, Never> {
        subscription?.cancel()
        let stream = workspace.eventBus.events
        let task = Task {
            for await event in stream {
                await handle(event)
            }
        }
        subscription = task
        return task
    }

    private func handle(_ event: WorkspaceEvent) async {
        switch event {
        case .documentOpened(let document):
            let version = bumpVersion(for: document.id)
            await syncService.notifyOpened(
                document,
                languageID: languageResolver(document),
                version: version
            )
        case .documentChanged(let document):
            let version = bumpVersion(for: document.id)
            await syncService.notifyFullChange(document, version: version)
        case .documentClosed(let documentID):
            versions.removeValue(forKey: documentID)
            await syncService.documentClosed(documentID: documentID)
        default:
            break
        }
    }

    private func bumpVersion(for documentID: DocumentID) -> Int {
        let version = (versions[documentID] ?? 0) + 1
        versions[documentID] = version
        return version
    }
}
