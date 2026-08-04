import Foundation

/// Result of parsing a document.
///
/// Implementations are provided by language-specific parsers (e.g., Tree-sitter). The index
/// consumes symbols, words, and imports to build the workspace database.
public protocol SyntaxTree: Sendable {
    /// Symbols extracted from the syntax tree (functions, types, variables, etc.).
    var symbols: [Symbol] { get }

    /// Plain words found in the document, useful for document-word completion.
    var words: [String] { get }

    /// Imported modules or dependencies referenced in the document.
    var imports: [String] { get }
}

/// Parses a document into a language-neutral syntax tree.
public protocol LanguageParser: Sendable {
    func parse(document: Document) async -> SyntaxTree
}
