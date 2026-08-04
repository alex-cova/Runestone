import Foundation

/// Parses a snippet body into a tree of `SnippetNode` values.
///
/// The supported syntax is a subset of the VS Code snippet grammar:
/// * Tab stops: `$1` or `${1}`
/// * Placeholders: `${1:default}` (nested placeholders are allowed)
/// * Variables: `$TM_SELECTED_TEXT` or `${TM_FILENAME:default}`
/// * Transforms: `${1/regex/replacement/options}` or `${TM_SELECTED_TEXT/(.)/$1/g}`
/// * Escaped dollars: `$$` produces a literal `$`.
public struct SnippetParser {
    public init() {}

    public func parse(_ body: String) -> [SnippetNode] {
        var parser = _Parser(body[...])
        return parser.parseNodes()
    }
}

private struct _Parser {
    private var input: Substring

    init(_ input: Substring) {
        self.input = input
    }

    mutating func parseNodes() -> [SnippetNode] {
        var nodes: [SnippetNode] = []
        while !input.isEmpty {
            if let node = parseNode() {
                nodes.append(node)
            }
        }
        return nodes
    }

    private mutating func parseNode() -> SnippetNode? {
        if input.first == "$" {
            return parseDollar()
        }
        return parseText()
    }

    private mutating func parseText() -> SnippetNode {
        var text = ""
        while !input.isEmpty, input.first != "$" {
            text.append(input.removeFirst())
        }
        return .text(text)
    }

    private mutating func parseDollar() -> SnippetNode? {
        input.removeFirst() // consume $
        guard let next = input.first else {
            return .text("$")
        }
        if next == "{" {
            return parseBraced()
        } else if next == "$" {
            input.removeFirst()
            return .text("$")
        } else if next.isNumber {
            let id = parseInteger()
            return .tabStop(id: id)
        } else if next.isLetter || next == "_" {
            let name = parseName()
            return .variable(name: name, defaultValue: nil)
        } else {
            input.removeFirst()
            return .text("$\(next)")
        }
    }

    private mutating func parseBraced() -> SnippetNode? {
        input.removeFirst() // consume {
        var content = ""
        var depth = 1
        while !input.isEmpty {
            let char = input.removeFirst()
            if char == "{" {
                depth += 1
                content.append(char)
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    break
                }
                content.append(char)
            } else {
                content.append(char)
            }
        }
        return parseInnerContent(content[...])
    }

    private mutating func parseInteger() -> Int {
        var text = ""
        while !input.isEmpty, let char = input.first, char.isNumber {
            text.append(input.removeFirst())
        }
        return Int(text) ?? 0
    }

    private mutating func parseName() -> String {
        var text = ""
        while !input.isEmpty, let char = input.first, char.isLetter || char.isNumber || char == "_" {
            text.append(input.removeFirst())
        }
        return text
    }
}

private func parseInnerContent(_ content: Substring) -> SnippetNode? {
    if let transform = parseTransform(content) {
        return transform
    }
    if let colonIndex = firstTopLevelIndex(of: ":", in: content) {
        let left = content[..<colonIndex].trimmingCharacters(in: .whitespaces)
        let right = content[content.index(after: colonIndex)...]
        if let id = Int(left) {
            let defaultNodes = SnippetParser().parse(String(right))
            return .placeholder(id: id, defaultValue: defaultNodes)
        } else {
            return .variable(name: left, defaultValue: String(right))
        }
    }
    let trimmed = content.trimmingCharacters(in: .whitespaces)
    if let id = Int(trimmed) {
        return .tabStop(id: id)
    }
    return .variable(name: trimmed, defaultValue: nil)
}

private func parseTransform(_ content: Substring) -> SnippetNode? {
    guard let firstSlash = firstTopLevelIndex(of: "/", in: content) else { return nil }
    let target = content[..<firstSlash].trimmingCharacters(in: .whitespaces)
    let rest = content[content.index(after: firstSlash)...]
    guard let secondSlash = firstTopLevelIndex(of: "/", in: rest) else { return nil }
    let regex = rest[..<secondSlash]
    let rest2 = rest[rest.index(after: secondSlash)...]
    let replacement: Substring
    let options: Substring
    if let thirdSlash = firstTopLevelIndex(of: "/", in: rest2) {
        replacement = rest2[..<thirdSlash]
        options = rest2[rest2.index(after: thirdSlash)...]
    } else {
        replacement = rest2
        options = ""
    }
    let targetValue: SnippetTransformTarget
    if let id = Int(target) {
        targetValue = .tabStop(id: id)
    } else {
        targetValue = .variable(name: target)
    }
    return .transform(
        target: targetValue,
        regex: String(regex),
        replacement: String(replacement),
        options: String(options)
    )
}

private func firstTopLevelIndex(of character: Character, in string: Substring) -> String.Index? {
    var depth = 0
    var index = string.startIndex
    while index < string.endIndex {
        let char = string[index]
        if char == "{" {
            depth += 1
        } else if char == "}" {
            depth -= 1
        } else if char == character && depth == 0 {
            return index
        }
        string.formIndex(after: &index)
    }
    return nil
}
