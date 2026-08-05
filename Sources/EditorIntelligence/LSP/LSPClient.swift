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
}
