import Foundation

/// Background indexing service that keeps the `SymbolIndex` in sync with the workspace.
///
/// The service listens to `WorkspaceEvent`s, parses changed documents with a `LanguageParser`, and
/// forwards extracted symbols and words to the `SymbolIndex`. It runs entirely on its own actor.
public actor IndexingService {
    public let index: SymbolIndex
    private let parser: LanguageParser
    private var workspaceEventTask: Task<Void, Never>?

    public init(parser: LanguageParser, index: SymbolIndex = SymbolIndex()) {
        self.parser = parser
        self.index = index
    }

    /// Subscribe to workspace events and index documents in the background.
    @discardableResult
    public func connect(to workspace: Workspace) -> Task<Void, Never> {
        workspaceEventTask?.cancel()
        let events = workspace.eventBus.events
        let task = Task {
            for await event in events {
                await handleWorkspaceEvent(event)
            }
        }
        workspaceEventTask = task
        return task
    }

    /// Manually index a single document. Useful for seeding the index outside of workspace events.
    public func indexDocument(_ document: Document) async {
        let signpost = EditorIntelligenceSignposts.performance.beginInterval("IndexingService.indexDocument")
        defer { EditorIntelligenceSignposts.performance.endInterval("IndexingService.indexDocument", signpost) }
        if document.contentSnapshot.isElided {
            return
        }
        let tree = await parser.parse(document: document)
        var symbols = tree.symbols
        let wordSymbols = tree.words.map { word in
            Symbol(
                name: word,
                kind: .word,
                documentID: document.id,
                range: TextRange(start: TextPosition(line: 0, column: 0, utf16Offset: 0),
                                 end: TextPosition(line: 0, column: 0, utf16Offset: 0))
            )
        }
        symbols.append(contentsOf: wordSymbols)
        if let url = document.url {
            symbols.append(Symbol(
                name: url.lastPathComponent,
                kind: .fileName,
                documentID: document.id,
                range: TextRange(start: TextPosition(line: 0, column: 0, utf16Offset: 0),
                                 end: TextPosition(line: 0, column: 0, utf16Offset: 0))
            ))
        }
        await index.index(symbols, for: document.id)
    }

    private func handleWorkspaceEvent(_ event: WorkspaceEvent) async {
        switch event {
        case .documentOpened(let document), .documentChanged(let document):
            await indexDocument(document)
        case .documentEdited(let document, _):
            await indexDocument(document)
        case .documentClosed(let documentID):
            await index.remove(documentID: documentID)
        default:
            break
        }
    }
}
