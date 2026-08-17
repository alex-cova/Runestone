import Foundation

/// Minimal LSP client protocol used by the EIP bridge.
///
/// Concrete implementations can communicate with a language server via JSON-RPC, stdio, or sockets.
/// The protocol exposes the small surface area needed by the EIP providers.
public protocol LSPClient: Sendable {
    /// Request diagnostics for the given document.
    func requestDiagnostics(for document: Document) async throws -> [LSPDiagnostic]

    /// Request hover information at the given position in the document.
    func requestHover(for document: Document, at position: TextPosition) async throws -> LSPHover?

    /// Request completion items at the given position in the document.
    func requestCompletions(for document: Document, at position: TextPosition) async throws -> [LSPCompletionItem]

    /// Request the definition location for the symbol at the given position.
    func requestDefinition(for document: Document, at position: TextPosition) async throws -> [LSPLocation]

    /// Request reference locations for the symbol at the given position.
    func requestReferences(for document: Document, at position: TextPosition) async throws -> [LSPLocation]

    /// Request a workspace-wide rename of the symbol at the given position.
    func requestRename(for document: Document, at position: TextPosition, to newName: String) async throws -> LSPWorkspaceEdit?

    /// Request formatting for the given document range.
    func requestFormatting(for document: Document, in range: TextRange?) async throws -> [LSPTextEdit]

    /// Request signature help at the given position.
    func requestSignatureHelp(for document: Document, at position: TextPosition) async throws -> LSPSignatureHelp?

    /// Request full semantic tokens for the document.
    func requestSemanticTokens(for document: Document) async throws -> LSPSemanticTokens

    /// Request a semantic-token delta when a previous result id is known.
    func requestSemanticTokensDelta(for document: Document, previousResultId: String) async throws -> LSPSemanticTokensDelta
}

public extension LSPClient {
    func requestDefinition(for document: Document, at position: TextPosition) async throws -> [LSPLocation] { [] }
    func requestReferences(for document: Document, at position: TextPosition) async throws -> [LSPLocation] { [] }
    func requestRename(for document: Document, at position: TextPosition, to newName: String) async throws -> LSPWorkspaceEdit? { nil }
    func requestFormatting(for document: Document, in range: TextRange?) async throws -> [LSPTextEdit] { [] }
    func requestSignatureHelp(for document: Document, at position: TextPosition) async throws -> LSPSignatureHelp? { nil }
    func requestSemanticTokens(for document: Document) async throws -> LSPSemanticTokens { LSPSemanticTokens(resultId: nil, data: []) }
    func requestSemanticTokensDelta(for document: Document, previousResultId: String) async throws -> LSPSemanticTokensDelta {
        LSPSemanticTokensDelta(resultId: nil, data: [])
    }
}
