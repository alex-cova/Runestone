import Foundation
import TreeSitter
import EditorIntelligence

/// Tree-sitter-based `LanguageParser` that produces a `TreeSitterSyntaxTree`.
///
/// The parser is an actor because the underlying `TreeSitterParser` is not thread-safe. Each
/// document is fully parsed on demand; incremental tree parsing can be added in a later phase.
public actor TreeSitterLanguageParser: LanguageParser {
    private let languageMode: TreeSitterLanguageMode
    private let parser: TreeSitterParser

    public init(languageMode: TreeSitterLanguageMode) {
        self.languageMode = languageMode
        self.parser = TreeSitterParser(encoding: .treeSitterUTF16)
        self.parser.language = languageMode.language.languagePointer
    }

    public func parse(document: Document) async -> SyntaxTree {
        let text = document.text as NSString
        let tree = parser.parse(text)
        return TreeSitterSyntaxTree(tree: tree, documentID: document.id, text: document.text)
    }
}
