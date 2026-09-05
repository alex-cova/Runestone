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
    private static let chunkUTF16 = 64 * 1024

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
        let length = document.contentSnapshot.utf16Length
        guard length > 0 else {
            return []
        }
        let pattern = regexPattern(for: query)
        let options: NSRegularExpression.Options = query.isCaseSensitive ? [.anchorsMatchLines] : [.caseInsensitive, .anchorsMatchLines]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let overlap = max((query.text as NSString).length + 16, 256)
        var results: [WorkspaceSearchResult] = []
        var offset = 0
        var lineNumber = 0
        var consumedThrough = 0
        while offset < length {
            let take = min(Self.chunkUTF16, length - offset)
            let slice = document.substring(utf16Offset: offset, length: take) as NSString
            let matches = regex.matches(in: slice as String, range: NSRange(location: 0, length: slice.length))
            for match in matches {
                let absolute = match.range.location + offset
                if absolute < consumedThrough {
                    continue
                }
                let lineRange = slice.lineRange(for: match.range)
                let newlinesBefore = newlineCount(in: slice, upTo: match.range.location)
                let startColumn = match.range.location - lineRange.location
                let start = TextPosition(
                    line: lineNumber + newlinesBefore,
                    column: startColumn,
                    utf16Offset: absolute
                )
                let end = TextPosition(
                    line: lineNumber + newlinesBefore,
                    column: startColumn + match.range.length,
                    utf16Offset: absolute + match.range.length
                )
                let preview = slice.substring(with: lineRange).trimmingCharacters(in: .newlines)
                results.append(WorkspaceSearchResult(
                    documentID: document.id,
                    documentName: document.displayName,
                    line: start.line,
                    column: start.column,
                    preview: preview,
                    range: TextRange(start: start, end: end)
                ))
            }
            let unique = offset + take < length ? max(take - overlap, 1) : take
            lineNumber += newlineCount(in: slice, upTo: unique)
            consumedThrough = offset + unique
            offset += unique
        }
        return results
    }

    private func newlineCount(in text: NSString, upTo limit: Int) -> Int {
        var line = 0
        var index = 0
        let end = min(limit, text.length)
        while index < end {
            let unit = text.character(at: index)
            if unit == 0x000A || unit == 0x0085 || unit == 0x2028 || unit == 0x2029 {
                line += 1
            } else if unit == 0x000D {
                line += 1
                if index + 1 < end && text.character(at: index + 1) == 0x000A {
                    index += 1
                }
            }
            index += 1
        }
        return line
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
