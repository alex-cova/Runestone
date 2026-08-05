import Foundation
import TreeSitter
import EditorIntelligence

/// Syntax tree produced by the Tree-sitter language parser.
struct TreeSitterSyntaxTree: EditorIntelligence.SyntaxTree {
    let symbols: [EditorIntelligence.Symbol]
    let words: [String]
    let imports: [String]

    init(tree: TreeSitterTree?, documentID: EditorIntelligence.DocumentID, text: String) {
        self.symbols = Self.extractSymbols(tree: tree, documentID: documentID, text: text)
        self.words = Self.extractWords(from: text)
        self.imports = Self.extractImports(tree: tree, text: text)
    }

    // MARK: - Symbol extraction

    private static func extractSymbols(tree: TreeSitterTree?, documentID: EditorIntelligence.DocumentID, text: String) -> [EditorIntelligence.Symbol] {
        guard let root = tree?.rootNode else { return [] }
        var symbols: [EditorIntelligence.Symbol] = []
        walk(node: root, into: &symbols, documentID: documentID, text: text)
        return symbols
    }

    private static func walk(node: TreeSitterNode, into symbols: inout [EditorIntelligence.Symbol], documentID: EditorIntelligence.DocumentID, text: String) {
        if let type = node.type {
            switch type {
            case "identifier":
                let name = textForNode(node, in: text)
                let range = makeRange(node)
                symbols.append(EditorIntelligence.Symbol(name: name, kind: .variable, documentID: documentID, range: range))
            case "property_identifier":
                let name = textForNode(node, in: text)
                let range = makeRange(node)
                symbols.append(EditorIntelligence.Symbol(name: name, kind: .property, documentID: documentID, range: range))
            case "type_identifier":
                let name = textForNode(node, in: text)
                let range = makeRange(node)
                symbols.append(EditorIntelligence.Symbol(name: name, kind: .type, documentID: documentID, range: range))
            case "function_declaration", "method_definition":
                if let nameNode = findChildIdentifier(in: node) {
                    let name = textForNode(nameNode, in: text)
                    let range = makeRange(nameNode)
                    symbols.append(EditorIntelligence.Symbol(name: name, kind: .function, documentID: documentID, range: range))
                }
            case "class_declaration":
                if let nameNode = findChildIdentifier(in: node) {
                    let name = textForNode(nameNode, in: text)
                    let range = makeRange(nameNode)
                    symbols.append(EditorIntelligence.Symbol(name: name, kind: .type, documentID: documentID, range: range))
                }
            default:
                break
            }
        }
        for index in 0 ..< node.childCount {
            if let child = node.child(at: index) {
                walk(node: child, into: &symbols, documentID: documentID, text: text)
            }
        }
    }

    private static func findChildIdentifier(in node: TreeSitterNode) -> TreeSitterNode? {
        for index in 0 ..< node.childCount {
            if let child = node.child(at: index), let type = child.type, type == "identifier" {
                return child
            }
        }
        return nil
    }

    private static func textForNode(_ node: TreeSitterNode, in text: String) -> String {
        let start = node.startByte.utf16Length
        let end = node.endByte.utf16Length
        let range = NSRange(location: start, length: end - start)
        return (text as NSString).substring(with: range)
    }

    private static func makeRange(_ node: TreeSitterNode) -> EditorIntelligence.TextRange {
        let start = EditorIntelligence.TextPosition(
            line: Int(node.startPoint.row),
            column: Int(node.startPoint.column) / 2,
            utf16Offset: node.startByte.utf16Length
        )
        let end = EditorIntelligence.TextPosition(
            line: Int(node.endPoint.row),
            column: Int(node.endPoint.column) / 2,
            utf16Offset: node.endByte.utf16Length
        )
        return EditorIntelligence.TextRange(start: start, end: end)
    }

    // MARK: - Word extraction

    private static func extractWords(from text: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(text.components(separatedBy: separators).filter { !$0.isEmpty }).sorted()
    }

    // MARK: - Import extraction

    private static func extractImports(tree: TreeSitterTree?, text: String) -> [String] {
        guard let root = tree?.rootNode else { return [] }
        var imports: [String] = []
        walkImports(node: root, into: &imports, text: text)
        return imports
    }

    private static func walkImports(node: TreeSitterNode, into imports: inout [String], text: String) {
        if let type = node.type, type == "import_statement" {
            for index in 0 ..< node.childCount {
                if let child = node.child(at: index), let childType = child.type, childType == "string" {
                    var source = textForNode(child, in: text)
                    if source.count >= 2 {
                        source = String(source.dropFirst().dropLast())
                    }
                    imports.append(source)
                }
            }
        }
        for index in 0 ..< node.childCount {
            if let child = node.child(at: index) {
                walkImports(node: child, into: &imports, text: text)
            }
        }
    }
}
