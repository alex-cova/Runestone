import Foundation

/// Query for searching across all open workspace documents.
public struct WorkspaceSearchQuery: Sendable, Hashable {
    public let text: String
    public let isCaseSensitive: Bool
    public let matchWholeWord: Bool
    public let useRegularExpression: Bool

    public init(
        text: String,
        isCaseSensitive: Bool = false,
        matchWholeWord: Bool = false,
        useRegularExpression: Bool = false
    ) {
        self.text = text
        self.isCaseSensitive = isCaseSensitive
        self.matchWholeWord = matchWholeWord
        self.useRegularExpression = useRegularExpression
    }
}

/// A single match found in a workspace document.
public struct WorkspaceSearchResult: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let documentID: DocumentID
    public let documentName: String
    public let line: Int
    public let column: Int
    public let preview: String
    public let range: TextRange

    public init(
        id: UUID = UUID(),
        documentID: DocumentID,
        documentName: String,
        line: Int,
        column: Int,
        preview: String,
        range: TextRange
    ) {
        self.id = id
        self.documentID = documentID
        self.documentName = documentName
        self.line = line
        self.column = column
        self.preview = preview
        self.range = range
    }
}

/// Searches text across all open documents in a workspace.
public actor WorkspaceSearchEngine {
    public init() {}

    public func search(_ query: WorkspaceSearchQuery, in workspace: Workspace) async -> [WorkspaceSearchResult] {
        guard !query.text.isEmpty else {
            return []
        }
        let documents = await workspace.allOpenDocuments()
        var results: [WorkspaceSearchResult] = []
        for document in documents {
            results.append(contentsOf: search(query, in: document))
        }
        return results.sorted {
            if $0.documentName == $1.documentName {
                return $0.line < $1.line
            }
            return $0.documentName < $1.documentName
        }
    }

    private func search(_ query: WorkspaceSearchQuery, in document: Document) -> [WorkspaceSearchResult] {
        let text = document.text as NSString
        guard text.length > 0 else {
            return []
        }
        let pattern = regexPattern(for: query)
        let options: NSRegularExpression.Options = query.isCaseSensitive ? [.anchorsMatchLines] : [.caseInsensitive, .anchorsMatchLines]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let matches = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        return matches.map { match in
            let lineRange = text.lineRange(for: match.range)
            let lineNumber = text.lineNumber(for: lineRange.location)
            let preview = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let start = TextPosition(
                line: lineNumber,
                column: match.range.location - lineRange.location,
                utf16Offset: match.range.location
            )
            let end = TextPosition(
                line: lineNumber,
                column: match.range.location + match.range.length - lineRange.location,
                utf16Offset: match.range.location + match.range.length
            )
            return WorkspaceSearchResult(
                documentID: document.id,
                documentName: document.displayName,
                line: lineNumber,
                column: start.column,
                preview: preview,
                range: TextRange(start: start, end: end)
            )
        }
    }

    private func regexPattern(for query: WorkspaceSearchQuery) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: query.text)
        if query.useRegularExpression {
            return query.text
        }
        if query.matchWholeWord {
            return "\\b\(escaped)\\b"
        }
        return escaped
    }
}

private extension NSString {
    func lineNumber(for location: Int) -> Int {
        var line = 0
        var index = 0
        while index < location, index < length {
            if character(at: index) == 10 {
                line += 1
            }
            index += 1
        }
        return line
    }
}
