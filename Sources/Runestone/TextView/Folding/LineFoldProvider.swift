import Foundation

/// A fold start or end signal produced by a ``LineFoldProvider`` for a single line.
///
/// `depth` is the nesting depth *after* the event is applied. Providers may return more than one
/// event for a single line (e.g. a line that both closes one fold and opens another, such as
/// `} else {`).
enum LineFoldEvent {
    case startFold(depth: Int)
    case endFold(depth: Int)

    var depth: Int {
        switch self {
        case .startFold(let depth), .endFold(let depth):
            return depth
        }
    }
}

/// Finds foldable regions in a document.
///
/// The editor calls ``foldEvents(atLine:previousDepth:in:stringView:)`` once per line, in order,
/// while recomputing the document's fold structure. Implementations should be fast, since this is
/// called once per line of the document on every recompute.
///
/// This is currently an internal extension point — only the bundled ``LineIndentationFoldProvider``
/// is used. It is written as a protocol (rather than folded directly into ``FoldingController``) so
/// a tree-sitter-backed provider can be swapped in later, as called out in the folding plan, without
/// committing to a public third-party-pluggable API shape yet.
protocol LineFoldProvider: AnyObject {
    func foldEvents(atLine lineIndex: Int, previousDepth: Int, in lineManager: LineManager, stringView: StringView) -> [LineFoldEvent]
}
