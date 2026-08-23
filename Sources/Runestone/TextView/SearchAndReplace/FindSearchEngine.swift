import Foundation

/// Outcome of a single ``FindSearchEngine`` search.
public struct FindSearchOutcome: Sendable, Equatable {
    public let matchCount: Int
    public let currentIndex: Int?
    public let currentRange: NSRange?
    public let highlightRanges: [NSRange]
    public let errorMessage: String?

    public init(matchCount: Int, currentIndex: Int?, currentRange: NSRange?, highlightRanges: [NSRange], errorMessage: String?) {
        self.matchCount = matchCount
        self.currentIndex = currentIndex
        self.currentRange = currentRange
        self.highlightRanges = highlightRanges
        self.errorMessage = errorMessage
    }

    public static let empty = FindSearchOutcome(
        matchCount: 0,
        currentIndex: nil,
        currentRange: nil,
        highlightRanges: [],
        errorMessage: nil
    )
}

/// Options for a ``FindSearchEngine`` search. Unlike ``SearchQuery``, which is bound to a live
/// `TextView`, this is a plain value type — the search engine driven by it operates purely over
/// `String`/`NSRange` and has no dependency on a text view.
public struct FindSearchOptions: Sendable, Equatable {
    public var query: String
    public var matchCase: Bool
    public var wholeWord: Bool
    public var useRegex: Bool

    public init(query: String, matchCase: Bool = false, wholeWord: Bool = false, useRegex: Bool = false) {
        self.query = query
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.useRegex = useRegex
    }

    /// Bridges from the `TextView`-oriented ``SearchQuery``, so callers already using
    /// `TextView.search(for:)` can adopt ``FindSearchEngine`` without a second query model.
    ///
    /// Lossy one way: `SearchQuery.MatchMethod.startsWith`/`.endsWith` have no boolean equivalent
    /// here and collapse to plain "contains" (`wholeWord: false, useRegex: false`).
    public init(_ searchQuery: SearchQuery) {
        self.query = searchQuery.text
        self.matchCase = searchQuery.isCaseSensitive
        switch searchQuery.matchMethod {
        case .fullWord:
            self.wholeWord = true
            self.useRegex = false
        case .regularExpression:
            self.wholeWord = false
            self.useRegex = true
        case .contains, .startsWith, .endsWith:
            self.wholeWord = false
            self.useRegex = false
        }
    }

    /// Converts to a ``SearchQuery`` usable with `TextView.search(for:)`.
    public var searchQuery: SearchQuery {
        let matchMethod: SearchQuery.MatchMethod = useRegex ? .regularExpression : (wholeWord ? .fullWord : .contains)
        return SearchQuery(text: query, matchMethod: matchMethod, isCaseSensitive: matchCase)
    }
}

/// Headless find/replace engine operating purely over `String`/`NSRange`, independent of any
/// `TextView`. Pairs with ``FindSession`` (stateful navigation/replace) and ``FindSearchScheduler``
/// (debounced, off-main-thread search) for a complete find-bar implementation that doesn't require
/// a live text view — useful for e.g. previewing search results before text is loaded into an
/// editor, or driving find/replace UI backed by a different text-storage mechanism entirely.
///
/// This is a separate, parallel implementation to ``SearchQuery``/`TextView.search(for:)` rather
/// than a replacement for it — that API stays exactly as it is. One behavioral difference to be
/// aware of if you use both: ``SearchQuery`` matches regular expressions with `.anchorsMatchLines`
/// set, so `^`/`$` match at line boundaries; this engine does not, so `^`/`$` only match the start
/// and end of the whole string.
public enum FindSearchEngine {
    public static let maxHighlightedMatches = 100
    /// Literal/regex scans above this size run off the main actor when possible (see
    /// ``FindSearchScheduler``).
    public static let offMainCharacterThreshold = 50_000

    public static func search(
        options: FindSearchOptions,
        in text: String,
        anchorLocation: Int,
        maxHighlights: Int = maxHighlightedMatches
    ) -> FindSearchOutcome {
        guard !options.query.isEmpty else { return .empty }
        do {
            if options.useRegex || options.wholeWord {
                return try regexSearch(options: options, in: text, anchorLocation: anchorLocation, maxHighlights: maxHighlights)
            }
            return literalSearch(options: options, in: text, anchorLocation: anchorLocation, maxHighlights: maxHighlights)
        } catch {
            return FindSearchOutcome(
                matchCount: 0,
                currentIndex: nil,
                currentRange: nil,
                highlightRanges: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    public static func findNext(options: FindSearchOptions, in text: String, after location: Int) -> NSRange? {
        guard !options.query.isEmpty else { return nil }
        let start = min(max(location, 0), (text as NSString).length)
        do {
            if options.useRegex || options.wholeWord {
                return try regexNext(options: options, in: text, from: start)
            }
            return literalNext(options: options, in: text, from: start)
        } catch {
            return nil
        }
    }

    public static func findPrevious(options: FindSearchOptions, in text: String, before location: Int) -> NSRange? {
        guard !options.query.isEmpty else { return nil }
        let limit = min(max(location, 0), (text as NSString).length)
        do {
            if options.useRegex || options.wholeWord {
                return try regexPrevious(options: options, in: text, before: limit)
            }
            return literalPrevious(options: options, in: text, before: limit)
        } catch {
            return nil
        }
    }

    public static func replaceAll(options: FindSearchOptions, in text: String, replacement: String) throws -> String {
        guard !options.query.isEmpty else { return text }
        if options.useRegex || options.wholeWord {
            let regex = try FindRegexCache.regex(pattern: regexPattern(for: options), options: regexOptions(for: options))
            let full = NSRange(location: 0, length: (text as NSString).length)
            return regex.stringByReplacingMatches(in: text, options: [], range: full, withTemplate: replacement)
        }
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])
        return (text as NSString).replacingOccurrences(
            of: options.query,
            with: replacement,
            options: compare,
            range: NSRange(location: 0, length: (text as NSString).length)
        )
    }

    // MARK: - Literal

    private static func literalSearch(
        options: FindSearchOptions,
        in text: String,
        anchorLocation: Int,
        maxHighlights: Int
    ) -> FindSearchOutcome {
        let ns = text as NSString
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])
        var matchCount = 0
        var currentIndex: Int?
        var currentRange: NSRange?
        var searchRange = NSRange(location: 0, length: ns.length)

        while searchRange.length > 0 {
            let found = ns.range(of: options.query, options: compare, range: searchRange)
            guard found.location != NSNotFound else { break }
            let index = matchCount
            matchCount += 1
            if currentIndex == nil, found.location >= anchorLocation {
                currentIndex = index
                currentRange = found
            }
            searchRange = NSRange(location: NSMaxRange(found), length: ns.length - NSMaxRange(found))
        }

        if matchCount == 0 {
            return .empty
        }
        if currentIndex == nil {
            currentIndex = 0
            currentRange = ns.range(of: options.query, options: compare, range: NSRange(location: 0, length: ns.length))
        }

        let highlights = collectLiteralHighlights(
            options: options,
            in: text,
            around: currentIndex ?? 0,
            matchCount: matchCount,
            maxHighlights: maxHighlights
        )

        return FindSearchOutcome(
            matchCount: matchCount,
            currentIndex: currentIndex,
            currentRange: currentRange,
            highlightRanges: highlights,
            errorMessage: nil
        )
    }

    private static func collectLiteralHighlights(
        options: FindSearchOptions,
        in text: String,
        around index: Int,
        matchCount: Int,
        maxHighlights: Int
    ) -> [NSRange] {
        let half = maxHighlights / 2
        let startIndex = max(0, min(index - half, max(0, matchCount - maxHighlights)))
        let endIndex = min(matchCount, startIndex + maxHighlights)

        let ns = text as NSString
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])
        var ranges: [NSRange] = []
        var matchIndex = 0
        var searchRange = NSRange(location: 0, length: ns.length)

        while searchRange.length > 0, matchIndex < endIndex {
            let found = ns.range(of: options.query, options: compare, range: searchRange)
            guard found.location != NSNotFound else { break }
            if matchIndex >= startIndex {
                ranges.append(found)
            }
            matchIndex += 1
            searchRange = NSRange(location: NSMaxRange(found), length: ns.length - NSMaxRange(found))
        }
        return ranges
    }

    private static func literalNext(options: FindSearchOptions, in text: String, from location: Int) -> NSRange? {
        let ns = text as NSString
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])
        let range = NSRange(location: location, length: ns.length - location)
        guard range.length > 0 else { return nil }
        let found = ns.range(of: options.query, options: compare, range: range)
        return found.location == NSNotFound ? nil : found
    }

    private static func literalPrevious(options: FindSearchOptions, in text: String, before location: Int) -> NSRange? {
        let ns = text as NSString
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])
        var last: NSRange?
        var searchRange = NSRange(location: 0, length: min(location, ns.length))
        while searchRange.length > 0 {
            let found = ns.range(of: options.query, options: compare, range: searchRange)
            guard found.location != NSNotFound else { break }
            last = found
            searchRange = NSRange(location: NSMaxRange(found), length: location - NSMaxRange(found))
        }
        return last
    }

    // MARK: - Regex

    private static func regexSearch(
        options: FindSearchOptions,
        in text: String,
        anchorLocation: Int,
        maxHighlights: Int
    ) throws -> FindSearchOutcome {
        let regex = try FindRegexCache.regex(pattern: regexPattern(for: options), options: regexOptions(for: options))
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var matchCount = 0
        var currentIndex: Int?
        var currentRange: NSRange?

        regex.enumerateMatches(in: text, options: [], range: full) { result, _, _ in
            guard let range = result?.range, range.length > 0 else { return }
            let index = matchCount
            matchCount += 1
            if currentIndex == nil, range.location >= anchorLocation {
                currentIndex = index
                currentRange = range
            }
        }

        if matchCount == 0 {
            return .empty
        }
        if currentIndex == nil {
            currentIndex = 0
            currentRange = regex.firstMatch(in: text, options: [], range: full)?.range
        }

        let highlights = try collectRegexHighlights(
            regex: regex,
            in: text,
            around: currentIndex ?? 0,
            matchCount: matchCount,
            maxHighlights: maxHighlights
        )

        return FindSearchOutcome(
            matchCount: matchCount,
            currentIndex: currentIndex,
            currentRange: currentRange,
            highlightRanges: highlights,
            errorMessage: nil
        )
    }

    private static func collectRegexHighlights(
        regex: NSRegularExpression,
        in text: String,
        around index: Int,
        matchCount: Int,
        maxHighlights: Int
    ) throws -> [NSRange] {
        let half = maxHighlights / 2
        let startIndex = max(0, min(index - half, max(0, matchCount - maxHighlights)))
        let endIndex = min(matchCount, startIndex + maxHighlights)
        let full = NSRange(location: 0, length: (text as NSString).length)

        var ranges: [NSRange] = []
        var matchIndex = 0
        regex.enumerateMatches(in: text, options: [], range: full) { result, _, stop in
            guard let range = result?.range, range.length > 0 else { return }
            if matchIndex >= endIndex {
                stop.pointee = true
                return
            }
            if matchIndex >= startIndex {
                ranges.append(range)
            }
            matchIndex += 1
        }
        return ranges
    }

    private static func regexNext(options: FindSearchOptions, in text: String, from location: Int) throws -> NSRange? {
        let regex = try FindRegexCache.regex(pattern: regexPattern(for: options), options: regexOptions(for: options))
        let ns = text as NSString
        let range = NSRange(location: min(location, ns.length), length: ns.length - min(location, ns.length))
        guard range.length > 0 else { return nil }
        return regex.firstMatch(in: text, options: [], range: range)?.range
    }

    private static func regexPrevious(options: FindSearchOptions, in text: String, before location: Int) throws -> NSRange? {
        let regex = try FindRegexCache.regex(pattern: regexPattern(for: options), options: regexOptions(for: options))
        let limit = min(location, (text as NSString).length)
        let full = NSRange(location: 0, length: limit)
        var last: NSRange?
        regex.enumerateMatches(in: text, options: [], range: full) { result, _, _ in
            guard let range = result?.range, range.length > 0 else { return }
            last = range
        }
        return last
    }

    private static func regexPattern(for options: FindSearchOptions) -> String {
        if options.useRegex {
            return options.query
        }
        var escaped = NSRegularExpression.escapedPattern(for: options.query)
        if options.wholeWord {
            escaped = "\\b\(escaped)\\b"
        }
        return escaped
    }

    private static func regexOptions(for options: FindSearchOptions) -> NSRegularExpression.Options {
        options.matchCase ? [] : [.caseInsensitive]
    }
}

/// `NSRegularExpression` compile cache backing ``FindSearchEngine``'s regex/whole-word paths, so
/// repeated per-keystroke searches don't recompile the same pattern.
enum FindRegexCache {
    private struct Key: Hashable {
        let pattern: String
        let optionsRaw: UInt
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: NSRegularExpression] = [:]
    private static let maxEntries = 32

    static func regex(pattern: String, options: NSRegularExpression.Options) throws -> NSRegularExpression {
        let key = Key(pattern: pattern, optionsRaw: options.rawValue)
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let compiled = try NSRegularExpression(pattern: pattern, options: options)
        lock.lock()
        if cache[key] == nil {
            if cache.count >= maxEntries {
                cache.removeAll(keepingCapacity: true)
            }
            cache[key] = compiled
        }
        let result = cache[key] ?? compiled
        lock.unlock()
        return result
    }
}
