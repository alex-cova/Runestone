import Foundation
import LanguageServerProtocol
import EditorIntelligence

/// Maps EIP document-sync payloads onto LSP `textDocument/didOpen` / `didChange` / `didClose`.
enum LSPDocumentSyncMapper {
    static func openParams(
        uri: String,
        languageID: String,
        version: Int,
        text: String
    ) -> DidOpenTextDocumentParams {
        DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(uri: uri, languageId: languageID, version: version, text: text)
        )
    }

    static func incrementalParams(
        uri: String,
        changes: [LSPDocumentSyncService.DocumentChange]
    ) -> DidChangeTextDocumentParams {
        let version = changes.last?.version ?? 0
        let events = changes.map { change in
            TextDocumentContentChangeEvent(
                range: protocolRange(from: change.range),
                rangeLength: change.rangeLength,
                text: change.text
            )
        }
        return DidChangeTextDocumentParams(uri: uri, version: version, contentChanges: events)
    }

    static func fullChangeParams(uri: String, version: Int, text: String) -> DidChangeTextDocumentParams {
        DidChangeTextDocumentParams(
            uri: uri,
            version: version,
            contentChange: TextDocumentContentChangeEvent(range: nil, rangeLength: nil, text: text)
        )
    }

    static func closeParams(uri: String) -> DidCloseTextDocumentParams {
        DidCloseTextDocumentParams(uri: uri)
    }

    private static func protocolRange(from range: EditorIntelligence.LSPRange) -> LanguageServerProtocol.LSPRange {
        LanguageServerProtocol.LSPRange(
            start: Position(line: range.start.line, character: range.start.character),
            end: Position(line: range.end.line, character: range.end.character)
        )
    }
}
