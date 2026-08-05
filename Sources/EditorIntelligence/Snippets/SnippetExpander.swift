import Foundation

/// Expands a parsed snippet AST into concrete text with placeholder coordinates.
public struct SnippetExpander {
    private let nodes: [SnippetNode]
    private let context: SnippetExpansionContext

    public init(nodes: [SnippetNode], context: SnippetExpansionContext) {
        self.nodes = nodes
        self.context = context
    }

    public func expand() -> SnippetExpansion {
        let result = expand(nodes: nodes)
        return SnippetExpansion(
            text: result.text,
            placeholders: result.placeholders,
            finalCursorOffset: result.finalCursorOffset
        )
    }

    private func expand(nodes: [SnippetNode]) -> ExpansionResult {
        var output = ""
        var placeholders: [SnippetPlaceholder] = []
        var finalCursorOffset: Int?

        for node in nodes {
            switch node {
            case .text(let string):
                output += string
            case .tabStop(let id):
                if id == 0 {
                    finalCursorOffset = output.utf16.count
                }
                placeholders.append(SnippetPlaceholder(
                    id: id,
                    startOffset: output.utf16.count,
                    length: 0,
                    defaultText: "",
                    children: []
                ))
            case .placeholder(let id, let defaultNodes):
                let startOffset = output.utf16.count
                let childResult = expand(nodes: defaultNodes)
                output += childResult.text
                let length = output.utf16.count - startOffset
                placeholders.append(SnippetPlaceholder(
                    id: id,
                    startOffset: startOffset,
                    length: length,
                    defaultText: childResult.text,
                    children: childResult.placeholders
                ))
                placeholders.append(contentsOf: childResult.placeholders)
            case .variable(let name, let defaultValue):
                let value = resolveVariable(name: name) ?? defaultValue ?? ""
                output += value
            case .transform(let target, let regex, let replacement, let options):
                let targetValue = resolveTransformTarget(target)
                output += applyTransform(to: targetValue, regex: regex, replacement: replacement, options: options)
            }
        }

        let sorted = placeholders.sorted { $0.id < $1.id }
        return ExpansionResult(
            text: output,
            placeholders: sorted,
            finalCursorOffset: finalCursorOffset
        )
    }

    private func resolveTransformTarget(_ target: SnippetTransformTarget) -> String {
        switch target {
        case .variable(let name):
            return resolveVariable(name: name) ?? ""
        case .tabStop(let id):
            return placeholderDefaultText(for: id, in: nodes) ?? ""
        }
    }

    private func placeholderDefaultText(for id: Int, in nodes: [SnippetNode]) -> String? {
        for node in nodes {
            if case .placeholder(let nodeID, let defaultNodes) = node, nodeID == id {
                return SnippetExpander(nodes: defaultNodes, context: context).expand().text
            }
            if let found = placeholderDefaultText(for: id, in: children(of: node)) {
                return found
            }
        }
        return nil
    }

    private func children(of node: SnippetNode) -> [SnippetNode] {
        if case .placeholder(_, let defaultNodes) = node {
            return defaultNodes
        }
        return []
    }

    private func resolveVariable(name: String) -> String? {
        switch name {
        case "TM_SELECTED_TEXT": return nonEmpty(context.selectedText)
        case "TM_CURRENT_LINE": return nonEmpty(context.currentLine)
        case "TM_CURRENT_WORD": return nonEmpty(context.currentWord)
        case "TM_FILENAME": return nonEmpty(context.filename)
        case "TM_FILENAME_BASE": return nonEmpty(context.filenameBase)
        case "TM_LINE_INDEX": return String(context.lineIndex)
        case "TM_LINE_NUMBER": return String(context.lineNumber)
        case "TM_SOFT_TAB": return nonEmpty(context.softTab)
        case "TM_NEWLINE": return "\n"
        case "TM_TAB": return "\t"
        case "TM_YEAR": return String(Calendar.current.component(.year, from: context.date))
        case "TM_YEAR_SHORT": return String(Calendar.current.component(.year, from: context.date) % 100)
        case "TM_MONTH": return String(format: "%02d", Calendar.current.component(.month, from: context.date))
        case "TM_MONTH_NAME": return Calendar.current.monthSymbols[Calendar.current.component(.month, from: context.date) - 1]
        case "TM_MONTH_NAME_SHORT": return Calendar.current.shortMonthSymbols[Calendar.current.component(.month, from: context.date) - 1]
        case "TM_DAY": return String(format: "%02d", Calendar.current.component(.day, from: context.date))
        case "TM_DAY_NAME": return Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: context.date) - 1]
        case "TM_DAY_NAME_SHORT": return Calendar.current.shortWeekdaySymbols[Calendar.current.component(.weekday, from: context.date) - 1]
        case "TM_HOUR": return String(format: "%02d", Calendar.current.component(.hour, from: context.date))
        case "TM_MINUTE": return String(format: "%02d", Calendar.current.component(.minute, from: context.date))
        case "TM_SECOND": return String(format: "%02d", Calendar.current.component(.second, from: context.date))
        default: return nil
        }
    }

    private func nonEmpty(_ string: String) -> String? {
        string.isEmpty ? nil : string
    }

    private func applyTransform(to string: String, regex: String, replacement: String, options: String) -> String {
        do {
            let nsOptions: NSRegularExpression.Options = options.contains("i") ? .caseInsensitive : []
            let expression = try NSRegularExpression(pattern: regex, options: nsOptions)
            let range = NSRange(location: 0, length: string.utf16.count)
            if options.contains("g") {
                return expression.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: replacement)
            } else if let match = expression.firstMatch(in: string, options: [], range: range) {
                let template = expression.replacementString(for: match, in: string, offset: 0, template: replacement)
                let mutable = NSMutableString(string: string)
                mutable.replaceCharacters(in: match.range, with: template)
                return mutable as String
            }
            return string
        } catch {
            return string
        }
    }

    private struct ExpansionResult {
        let text: String
        let placeholders: [SnippetPlaceholder]
        let finalCursorOffset: Int?
    }
}
