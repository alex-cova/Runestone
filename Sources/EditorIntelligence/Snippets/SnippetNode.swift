import Foundation

/// A single node in a parsed snippet body.
///
/// Snippet bodies are parsed into a tree of nodes before expansion. The parser supports text,
/// tab stops, placeholders, variables, and transforms.
public enum SnippetNode: Sendable, Hashable {
    /// Plain text content.
    case text(String)
    /// A tab stop such as `$1` or `${1}`.
    case tabStop(id: Int)
    /// A placeholder with an optional default value, e.g. `${1:name}`.
    case placeholder(id: Int, defaultValue: [SnippetNode])
    /// A variable reference, e.g. `$TM_SELECTED_TEXT` or `${TM_FILENAME:untitled}`.
    case variable(name: String, defaultValue: String?)
    /// A transform applied to a tab stop or variable value.
    case transform(target: SnippetTransformTarget, regex: String, replacement: String, options: String)
}

/// The target of a snippet transform.
public enum SnippetTransformTarget: Sendable, Hashable {
    case tabStop(id: Int)
    case variable(name: String)
}
