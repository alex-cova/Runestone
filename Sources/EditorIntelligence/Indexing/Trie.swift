import Foundation

/// Prefix tree supporting insertion, removal, and prefix lookup of hashable values keyed by a string.
final class Trie<Value: Hashable> {
    private final class Node {
        var children: [Character: Node] = [:]
        var values: Set<Value> = []
        var isEmpty: Bool { children.isEmpty && values.isEmpty }
    }

    private let root = Node()

    init() {}

    /// Insert a value under the given key.
    func insert(_ key: String, value: Value) {
        var node = root
        for char in key {
            if node.children[char] == nil {
                node.children[char] = Node()
            }
            node = node.children[char]!
        }
        node.values.insert(value)
    }

    /// Remove a specific value from the given key. Returns true if the value was found.
    @discardableResult
    func remove(_ key: String, value: Value) -> Bool {
        var node = root
        var path: [(Character, Node)] = []
        for char in key {
            guard let child = node.children[char] else { return false }
            path.append((char, node))
            node = child
        }
        guard node.values.remove(value) != nil else { return false }
        cleanup(path: path)
        return true
    }

    /// Find all values whose key starts with the given prefix.
    func search(prefix: String) -> [Value] {
        var node = root
        for char in prefix {
            guard let child = node.children[char] else { return [] }
            node = child
        }
        return collectValues(from: node)
    }

    private func cleanup(path: [(Character, Node)]) {
        for (char, parent) in path.reversed() {
            if let child = parent.children[char], child.isEmpty {
                parent.children.removeValue(forKey: char)
            } else {
                break
            }
        }
    }

    private func collectValues(from node: Node) -> [Value] {
        var result = Array(node.values)
        for child in node.children.values {
            result.append(contentsOf: collectValues(from: child))
        }
        return result
    }
}
