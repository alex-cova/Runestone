import Foundation

/// Contextual values used to resolve snippet variables during expansion.
public struct SnippetExpansionContext: Sendable {
    public let selectedText: String
    public let currentLine: String
    public let currentWord: String
    public let filename: String
    public let filenameBase: String
    public let lineIndex: Int
    public let lineNumber: Int
    public let softTab: String
    public let date: Date

    public init(
        selectedText: String = "",
        currentLine: String = "",
        currentWord: String = "",
        filename: String = "",
        filenameBase: String = "",
        lineIndex: Int = 0,
        lineNumber: Int = 1,
        softTab: String = "    ",
        date: Date = .now
    ) {
        self.selectedText = selectedText
        self.currentLine = currentLine
        self.currentWord = currentWord
        self.filename = filename
        self.filenameBase = filenameBase
        self.lineIndex = lineIndex
        self.lineNumber = lineNumber
        self.softTab = softTab
        self.date = date
    }
}
