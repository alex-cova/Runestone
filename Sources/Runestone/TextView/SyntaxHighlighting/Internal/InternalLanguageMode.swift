import Foundation

struct InsertLineBreakIndentStrategy {
    let indentLevel: Int
    let insertExtraLineBreak: Bool
}

protocol InternalLanguageMode: AnyObject {
    var isSyntaxTreeReady: Bool { get }
    func parse(_ text: NSString)
    func parse(_ text: NSString, completion: @escaping @MainActor @Sendable (Bool) -> Void)
    /// Parse using the buffer reader (no full-document `NSString` materialization).
    func parseFromBuffer()
    func cancelParse()
    func textDidChange(_ change: TextChange) -> LineChangeSet
    func createLineSyntaxHighlighter() -> LineSyntaxHighlighter
    func syntaxNode(at linePosition: LinePosition) -> SyntaxNode?
    func currentIndentLevel(of line: DocumentLineNode, using indentStrategy: IndentStrategy) -> Int
    func strategyForInsertingLineBreak(
        from startLinePosition: LinePosition,
        to endLinePosition: LinePosition,
        using indentStrategy: IndentStrategy) -> InsertLineBreakIndentStrategy
    func detectIndentStrategy() -> DetectedIndentStrategy
    func invalidateSyntaxTree()
}

extension InternalLanguageMode {
    var isSyntaxTreeReady: Bool { true }
    func cancelParse() {}
    func invalidateSyntaxTree() {}
    func parseFromBuffer() {
        parse("" as NSString)
    }
}
