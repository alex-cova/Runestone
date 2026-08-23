import Foundation

/// Resolves what a command palette's raw query string means: either an explicit sigil prefix
/// overriding the current mode, or the current ``EditorPaletteMode`` when there's no prefix.
public enum PaletteQueryScope: Equatable {
    case commands(String)
    case files(String)
    case symbols(String)
    case textActions(String)

    /// `">"` routes to commands, `"@"` to symbols, and — intentionally, not a typo — **both**
    /// `"/"` and `"#"` route to files. Falls back to `mode` when the query has none of these
    /// prefixes. The associated string has its prefix stripped and is trimmed of whitespace for
    /// the prefixed cases; the unprefixed (mode-routed) case passes `query` through as-is.
    public static func resolve(query: String, mode: EditorPaletteMode) -> PaletteQueryScope {
        if let remainder = query.strippingPrefix(">") { return .commands(remainder) }
        if let remainder = query.strippingPrefix("/") { return .files(remainder) }
        if let remainder = query.strippingPrefix("#") { return .files(remainder) }
        if let remainder = query.strippingPrefix("@") { return .symbols(remainder) }
        switch mode {
        case .commands: return .commands(query)
        case .quickOpen: return .files(query)
        case .symbols: return .symbols(query)
        case .textActions: return .textActions(query)
        }
    }

    public var query: String {
        switch self {
        case .commands(let query), .files(let query), .symbols(let query), .textActions(let query):
            return query
        }
    }
}

private extension String {
    func strippingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
