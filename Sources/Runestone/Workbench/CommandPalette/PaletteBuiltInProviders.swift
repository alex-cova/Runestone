import Foundation
import EditorIntelligence

/// A file candidate for the files / recent-files palette sections.
public struct PaletteFileEntry: Sendable, Hashable {
    public let url: URL
    /// Optional display name override (defaults to the last path component).
    public let displayName: String?

    public init(url: URL, displayName: String? = nil) {
        self.url = url
        self.displayName = displayName
    }
}

/// Commands registered with a ``CommandRegistry`` (also the home of "Find Action").
public final class CommandsPaletteProvider: SearchEverywhereProvider {
    public let sectionTitle: String
    public let sectionOrder = 10
    private let registry: CommandRegistry

    public init(registry: CommandRegistry, sectionTitle: String = "Actions") {
        self.registry = registry
        self.sectionTitle = sectionTitle
    }

    public func items(matching query: String, limit: Int) async -> [PaletteItem] {
        let registry = self.registry
        let matches = await MainActor.run { registry.filteredWithMatches(query: query, limit: limit) }
        return matches.enumerated().map { index, entry in
            PaletteItem(
                id: "command:\(entry.command.id)",
                title: entry.command.title,
                subtitle: entry.command.shortcutDisplay,
                sectionTitle: sectionTitle,
                matchedIndices: entry.match.matchedIndices,
                score: limit - index,
                action: entry.command.action
            )
        }
    }
}

/// Fuzzy file lookup over a caller-supplied list of URLs (Runestone has no on-disk index).
/// The list and root are snapshotted on the main actor per query.
public final class FilesPaletteProvider: SearchEverywhereProvider {
    public let sectionTitle = "Files"
    public let sectionOrder = 20
    private let files: @MainActor @Sendable () -> [PaletteFileEntry]
    private let root: @MainActor @Sendable () -> URL?
    private let onOpen: @MainActor @Sendable (URL) -> Void

    public init(
        files: @escaping @MainActor @Sendable () -> [PaletteFileEntry],
        root: @escaping @MainActor @Sendable () -> URL? = { nil },
        onOpen: @escaping @MainActor @Sendable (URL) -> Void
    ) {
        self.files = files
        self.root = root
        self.onOpen = onOpen
    }

    public func items(matching query: String, limit: Int) async -> [PaletteItem] {
        let files = self.files
        let root = self.root
        let (entries, rootURL) = await MainActor.run { (files(), root()) }
        let ranked = QuickOpenFileRanker.rank(query: query, files: entries.map(\.url), root: rootURL, limit: limit)
        return ranked.map { url in
            let onOpen = self.onOpen
            return PaletteItem(
                id: "file:\(url.path)",
                title: entries.first { $0.url == url }?.displayName ?? url.lastPathComponent,
                subtitle: Self.relativeDirectory(of: url, root: rootURL),
                sectionTitle: sectionTitle,
                action: { onOpen(url) }
            )
        }
    }

    static func relativeDirectory(of url: URL, root: URL?) -> String? {
        let directory = url.deletingLastPathComponent()
        guard let root else { return directory.path }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if directory.path.hasPrefix(rootPath) {
            let relative = String(directory.path.dropFirst(rootPath.count))
            return relative.isEmpty ? nil : relative
        }
        return directory.path
    }
}

/// Most-recently-used documents.
public final class RecentFilesPaletteProvider: SearchEverywhereProvider {
    public let sectionTitle = "Recent Files"
    public let sectionOrder = 5
    private let entries: @MainActor @Sendable () -> [PaletteFileEntry]
    private let onOpen: @MainActor @Sendable (URL) -> Void

    public init(
        entries: @escaping @MainActor @Sendable () -> [PaletteFileEntry],
        onOpen: @escaping @MainActor @Sendable (URL) -> Void
    ) {
        self.entries = entries
        self.onOpen = onOpen
    }

    public func items(matching query: String, limit: Int) async -> [PaletteItem] {
        let entriesProvider = self.entries
        let all = await MainActor.run { entriesProvider() }
        let ranked = FuzzyMatcher.rankedWithMatches(
            query: query,
            items: all,
            key: { $0.displayName ?? $0.url.lastPathComponent },
            limit: limit
        )
        return ranked.enumerated().map { index, entry in
            let onOpen = self.onOpen
            let url = entry.item.url
            return PaletteItem(
                id: "recent:\(url.path)",
                title: entry.item.displayName ?? url.lastPathComponent,
                subtitle: url.deletingLastPathComponent().lastPathComponent,
                sectionTitle: sectionTitle,
                matchedIndices: entry.match.matchedIndices,
                score: limit - index,
                action: { onOpen(url) }
            )
        }
    }
}

/// Workspace symbols. `SymbolIndex` only does prefix/exact lookups, so this layers
/// ``FuzzyMatcher`` over `allSymbols()`.
public final class SymbolsPaletteProvider: SearchEverywhereProvider {
    public let sectionTitle = "Symbols"
    public let sectionOrder = 30
    private let index: SymbolIndex
    private let onSelect: @MainActor @Sendable (EditorIntelligence.Symbol) -> Void

    public init(index: SymbolIndex, onSelect: @escaping @MainActor @Sendable (EditorIntelligence.Symbol) -> Void) {
        self.index = index
        self.onSelect = onSelect
    }

    public func items(matching query: String, limit: Int) async -> [PaletteItem] {
        guard !query.isEmpty else { return [] }
        let all = await index.allSymbols()
        let ranked = FuzzyMatcher.rankedWithMatches(query: query, items: all, key: { $0.name }, limit: limit)
        return ranked.map { entry in
            let onSelect = self.onSelect
            let symbol = entry.item
            return PaletteItem(
                id: "symbol:\(symbol.id)",
                title: symbol.name,
                subtitle: symbol.signature ?? String(describing: symbol.kind),
                sectionTitle: sectionTitle,
                matchedIndices: entry.match.matchedIndices,
                action: { onSelect(symbol) }
            )
        }
    }
}
