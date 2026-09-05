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

/// Per-match replacement produced by ``FindSearchEngine/replaceAllMatches(options:in:replacement:)``.
public struct FindReplaceMatch: Sendable, Equatable {
    public let range: NSRange
    public let replacementText: String

    public init(range: NSRange, replacementText: String) {
        self.range = range
        self.replacementText = replacementText
    }
}

/// Options for a ``FindSearchEngine`` search. Unlike ``SearchQuery``, which is bound to a live
/// `TextView`, this is a plain value type — the search engine driven by it operates purely over
/// ``FindTextSource`` / `String` / `NSRange` and has no dependency on a text view.
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

/// Headless find/replace engine operating over ``FindTextSource`` or `String`/`NSRange`,
/// independent of any `TextView`. Pairs with ``FindSession`` (stateful navigation/replace) and
/// ``FindSearchScheduler`` (debounced, off-main-thread search) for a complete find-bar
/// implementation that doesn't require a live text view — useful for e.g. previewing search
/// results before text is loaded into an editor, or driving find/replace UI backed by a different
/// text-storage mechanism entirely.
///
/// This is a separate, parallel implementation to ``SearchQuery``/`TextView.search(for:)` rather
/// than a replacement for it — that API stays exactly as it is. Regular expressions use
/// `.anchorsMatchLines`, so `^`/`$` match at line boundaries (same as ``SearchQuery``). On a
/// non-contiguous ``FindTextSource``, regex and whole-word search are not windowed yet and
/// return an error outcome rather than materializing the document.
public enum FindSearchEngine {
    public static let maxHighlightedMatches = 100
    /// Literal/regex scans above this size run off the main actor when possible (see
    /// ``FindSearchScheduler``).
    public static let offMainCharacterThreshold = 50_000
    /// Unique UTF-16 units per literal window. Matcher region is unique plus a right pad.
    public static let literalWindowUTF16 = 64 * 1024
    /// Unique UTF-16 units per regex window.
    public static let regexWindowUTF16 = 1_048_576
    /// Left and right pad for regex windows.
    public static let regexOverlapUTF16 = 64 * 1024

    /// Overridable in tests so a match can be forced across a unique/right-pad cut without a 64 KB fixture.
    nonisolated(unsafe) static var debugLiteralWindowUTF16: Int?

    public static func literalCaseInsensitiveOverlapUTF16(_ query: String) -> Int {
        max(query.utf16.count * 3, 16)
    }

    static let regexWindowsNotImplementedMessage = "regex windows land in 1b"

    public static func search(
        options: FindSearchOptions,
        in text: String,
        anchorLocation: Int,
        maxHighlights: Int = maxHighlightedMatches
    ) -> FindSearchOutcome {
        search(options: options, in: StringFindTextSource(text), anchorLocation: anchorLocation, maxHighlights: maxHighlights)
    }

    public static func search(
        options: FindSearchOptions,
        in source: any FindTextSource,
        anchorLocation: Int,
        maxHighlights: Int = maxHighlightedMatches
    ) -> FindSearchOutcome {
        guard !options.query.isEmpty else { return .empty }
        do {
            if options.useRegex || options.wholeWord {
                guard let ns = source.contiguousNSString else {
                    return FindSearchOutcome(
                        matchCount: 0,
                        currentIndex: nil,
                        currentRange: nil,
                        highlightRanges: [],
                        errorMessage: regexWindowsNotImplementedMessage
                    )
                }
                return try regexSearch(
                    options: options,
                    in: ns as String,
                    anchorLocation: anchorLocation,
                    maxHighlights: maxHighlights
                )
            }
            return literalSearch(
                options: options,
                in: source,
                anchorLocation: anchorLocation,
                maxHighlights: maxHighlights
            )
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
        findNext(options: options, in: StringFindTextSource(text), after: location)
    }

    public static func findNext(options: FindSearchOptions, in source: any FindTextSource, after location: Int) -> NSRange? {
        guard !options.query.isEmpty else { return nil }
        if options.useRegex || options.wholeWord {
            guard let ns = source.contiguousNSString else { return nil }
            let start = min(max(location, 0), ns.length)
            return try? regexNext(options: options, in: ns as String, from: start)
        }
        let start = min(max(location, 0), source.utf16Length)
        var found: NSRange?
        _ = enumerateLiteralMatches(options: options, in: source, from: start) { range in
            found = range
            return false
        }
        return found
    }

    public static func findPrevious(options: FindSearchOptions, in text: String, before location: Int) -> NSRange? {
        findPrevious(options: options, in: StringFindTextSource(text), before: location)
    }

    public static func findPrevious(options: FindSearchOptions, in source: any FindTextSource, before location: Int) -> NSRange? {
        guard !options.query.isEmpty else { return nil }
        if options.useRegex || options.wholeWord {
            guard let ns = source.contiguousNSString else { return nil }
            let limit = min(max(location, 0), ns.length)
            return try? regexPrevious(options: options, in: ns as String, before: limit)
        }
        if let ns = source.contiguousNSString {
            let limit = min(max(location, 0), ns.length)
            return contiguousLiteralPrevious(options: options, in: ns, before: limit)
        }
        return windowedLiteralPrevious(options: options, in: source, before: location)
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

    /// Expands a replacement string for a single match range (VS Code `$0`/`$1` placeholders).
    public static func replacementText(
        options: FindSearchOptions,
        in text: String,
        matching range: NSRange,
        replacement: String
    ) throws -> String {
        try replacementText(options: options, in: StringFindTextSource(text), matching: range, replacement: replacement)
    }

    public static func replacementText(
        options: FindSearchOptions,
        in source: any FindTextSource,
        matching range: NSRange,
        replacement: String
    ) throws -> String {
        guard options.useRegex || options.wholeWord else {
            return replacement
        }
        guard let ns = source.contiguousNSString else {
            throw FindRegexWindowsNotImplementedError()
        }
        let text = ns as String
        guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else {
            return replacement
        }
        let parsed = ReplacementStringParser(string: replacement).parse()
        guard parsed.containsPlaceholder else {
            return replacement
        }
        let regex = try FindRegexCache.regex(pattern: regexPattern(for: options), options: regexOptions(for: options))
        guard let result = regex.firstMatch(in: text, options: [], range: range), result.range == range else {
            return replacement
        }
        return parsed.string(byMatching: result, in: ns)
    }

    /// Per-match ranges and replacement strings for building a ``BatchReplaceSet``.
    ///
    /// Unlike ``replaceAll(options:in:replacement:)``, which returns a whole new `String` and
    /// expands ICU `$n` templates, this keeps VS Code-style capture groups (`$0`, `$1`, `\u$1`,
    /// …) so Replace All can apply the same edits as
    /// ``TextView/search(for:replacingMatchesWith:)`` without replacing the entire buffer (and
    /// without a whole-document undo snapshot).
    public static func replaceAllMatches(
        options: FindSearchOptions,
        in text: String,
        replacement: String
    ) throws -> [FindReplaceMatch] {
        try replaceAllMatches(options: options, in: StringFindTextSource(text), replacement: replacement)
    }

    public static func replaceAllMatches(
        options: FindSearchOptions,
        in source: any FindTextSource,
        replacement: String
    ) throws -> [FindReplaceMatch] {
        guard !options.query.isEmpty else { return [] }
        if options.useRegex || options.wholeWord {
            guard let ns = source.contiguousNSString else {
                throw FindRegexWindowsNotImplementedError()
            }
            return try regexReplaceAllMatches(options: options, in: ns as String, replacement: replacement)
        }
        return try literalReplaceAllMatches(options: options, in: source, replacement: replacement)
    }

    // MARK: - Literal

    private static func literalSearch(
        options: FindSearchOptions,
        in source: any FindTextSource,
        anchorLocation: Int,
        maxHighlights: Int
    ) -> FindSearchOutcome {
        var matchCount = 0
        var currentIndex: Int?
        var currentRange: NSRange?
        let result = enumerateLiteralMatches(options: options, in: source) { found in
            let index = matchCount
            matchCount += 1
            if currentIndex == nil, found.location >= anchorLocation {
                currentIndex = index
                currentRange = found
            }
            return true
        }

        if result == .cancelled {
            return .empty
        }
        if matchCount == 0 {
            return .empty
        }
        if currentIndex == nil {
            currentIndex = 0
            currentRange = firstLiteralMatch(options: options, in: source)
        }

        let highlights = collectLiteralHighlights(
            options: options,
            in: source,
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

    private static func firstLiteralMatch(options: FindSearchOptions, in source: any FindTextSource) -> NSRange? {
        var found: NSRange?
        _ = enumerateLiteralMatches(options: options, in: source) { range in
            found = range
            return false
        }
        return found
    }

    private static func collectLiteralHighlights(
        options: FindSearchOptions,
        in source: any FindTextSource,
        around index: Int,
        matchCount: Int,
        maxHighlights: Int
    ) -> [NSRange] {
        let half = maxHighlights / 2
        let startIndex = max(0, min(index - half, max(0, matchCount - maxHighlights)))
        let endIndex = min(matchCount, startIndex + maxHighlights)
        var ranges: [NSRange] = []
        var matchIndex = 0
        _ = enumerateLiteralMatches(options: options, in: source) { found in
            if matchIndex >= endIndex {
                return false
            }
            if matchIndex >= startIndex {
                ranges.append(found)
            }
            matchIndex += 1
            return true
        }
        return ranges
    }

    private static func literalReplaceAllMatches(
        options: FindSearchOptions,
        in source: any FindTextSource,
        replacement: String
    ) throws -> [FindReplaceMatch] {
        var matches: [FindReplaceMatch] = []
        let result = enumerateLiteralMatches(options: options, in: source) { found in
            guard found.length > 0 else {
                return false
            }
            matches.append(FindReplaceMatch(range: found, replacementText: replacement))
            return true
        }
        if result == .cancelled {
            throw CancellationError()
        }
        return matches
    }

    private enum LiteralEnumerateResult {
        case completed
        case cancelled
        case stopped
    }

    /// Invokes `body` for each accepted literal match in document coordinates.
    /// `body` returns `false` to stop.
    private static func enumerateLiteralMatches(
        options: FindSearchOptions,
        in source: any FindTextSource,
        from startOffset: Int = 0,
        body: (NSRange) -> Bool
    ) -> LiteralEnumerateResult {
        if let ns = source.contiguousNSString {
            return enumerateContiguousLiteralMatches(options: options, in: ns, from: startOffset, body: body)
        }
        return enumerateWindowedLiteralMatches(options: options, in: source, from: startOffset, body: body)
    }

    private static func enumerateContiguousLiteralMatches(
        options: FindSearchOptions,
        in ns: NSString,
        from startOffset: Int,
        body: (NSRange) -> Bool
    ) -> LiteralEnumerateResult {
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])
        let origin = min(max(startOffset, 0), ns.length)
        var searchRange = NSRange(location: origin, length: ns.length - origin)
        while searchRange.length > 0 {
            if Task.isCancelled {
                return .cancelled
            }
            let found = ns.range(of: options.query, options: compare, range: searchRange)
            guard found.location != NSNotFound else { break }
            if !body(found) {
                return .stopped
            }
            let next = NSMaxRange(found)
            guard next > searchRange.location else { break }
            searchRange = NSRange(location: next, length: ns.length - next)
        }
        return .completed
    }

    private static func enumerateWindowedLiteralMatches(
        options: FindSearchOptions,
        in source: any FindTextSource,
        from startOffset: Int,
        body: (NSRange) -> Bool
    ) -> LiteralEnumerateResult {
        let utf16Length = source.utf16Length
        var offset = min(max(startOffset, 0), utf16Length)
        let window = effectiveLiteralWindowUTF16()
        let rightPadWanted = literalRightPadUTF16(query: options.query, matchCase: options.matchCase)
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])

        while offset < utf16Length {
            if Task.isCancelled {
                return .cancelled
            }
            let plannedUnique = min(window, utf16Length - offset)
            let uniqueEnd = offset + plannedUnique
            var rightPad = min(rightPadWanted, utf16Length - uniqueEnd)
            let searchEnd = uniqueEnd + rightPad
            if searchEnd < utf16Length,
               let unit = utf16Unit(in: source, at: searchEnd), isHighSurrogate(unit),
               let next = utf16Unit(in: source, at: searchEnd + 1), isLowSurrogate(next) {
                rightPad += 1
            }

            var substrStart = offset
            var leftPad = 0
            if offset > 0, let unit = utf16Unit(in: source, at: offset), isLowSurrogate(unit) {
                substrStart = offset - 1
                leftPad = 1
            }

            let windowString = source.substring(utf16Offset: substrStart, length: leftPad + plannedUnique + rightPad)
            let ns = windowString as NSString
            let searchLength = min(plannedUnique + rightPad, max(0, ns.length - leftPad))
            var localSearch = NSRange(location: leftPad, length: searchLength)
            while localSearch.length > 0 {
                if Task.isCancelled {
                    return .cancelled
                }
                let found = ns.range(of: options.query, options: compare, range: localSearch)
                guard found.location != NSNotFound else { break }
                let docStart = substrStart + found.location
                if docStart >= uniqueEnd {
                    break
                }
                if docStart >= offset {
                    let docRange = NSRange(location: docStart, length: found.length)
                    if !body(docRange) {
                        return .stopped
                    }
                }
                let next = NSMaxRange(found)
                guard next > localSearch.location else { break }
                localSearch = NSRange(location: next, length: NSMaxRange(localSearch) - next)
            }

            prefetchNextLiteralWindow(
                in: source,
                from: uniqueEnd,
                unique: window,
                rightPad: rightPadWanted
            )
            offset = uniqueEnd
        }
        return .completed
    }

    private static func windowedLiteralPrevious(
        options: FindSearchOptions,
        in source: any FindTextSource,
        before location: Int
    ) -> NSRange? {
        let utf16Length = source.utf16Length
        guard utf16Length > 0, location > 0 else {
            return nil
        }
        let window = effectiveLiteralWindowUTF16()
        let rightPadWanted = literalRightPadUTF16(query: options.query, matchCase: options.matchCase)
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])
        var cursor = min(location, utf16Length)

        while cursor > 0 {
            if Task.isCancelled {
                return nil
            }
            let plannedUnique = min(window, cursor)
            let uniqueStart = cursor - plannedUnique
            var rightPad = min(rightPadWanted, utf16Length - cursor)
            let searchEnd = cursor + rightPad
            if searchEnd < utf16Length,
               let unit = utf16Unit(in: source, at: searchEnd), isHighSurrogate(unit),
               let next = utf16Unit(in: source, at: searchEnd + 1), isLowSurrogate(next) {
                rightPad += 1
            }

            var substrStart = uniqueStart
            var leftPad = 0
            if uniqueStart > 0, let unit = utf16Unit(in: source, at: uniqueStart), isLowSurrogate(unit) {
                substrStart = uniqueStart - 1
                leftPad = 1
            }

            let windowString = source.substring(utf16Offset: substrStart, length: leftPad + plannedUnique + rightPad)
            let ns = windowString as NSString
            let searchLength = min(plannedUnique + rightPad, max(0, ns.length - leftPad))
            var localSearch = NSRange(location: leftPad, length: searchLength)
            var last: NSRange?
            while localSearch.length > 0 {
                if Task.isCancelled {
                    return nil
                }
                let found = ns.range(of: options.query, options: compare, range: localSearch)
                guard found.location != NSNotFound else { break }
                let docStart = substrStart + found.location
                if docStart >= cursor {
                    break
                }
                if docStart >= uniqueStart, docStart < location {
                    last = NSRange(location: docStart, length: found.length)
                }
                let next = NSMaxRange(found)
                guard next > localSearch.location else { break }
                localSearch = NSRange(location: next, length: NSMaxRange(localSearch) - next)
            }
            if let last {
                return last
            }
            cursor = uniqueStart
        }
        return nil
    }

    private static func contiguousLiteralPrevious(options: FindSearchOptions, in ns: NSString, before location: Int) -> NSRange? {
        let compare = NSString.CompareOptions(options.matchCase ? [] : [.caseInsensitive])
        var last: NSRange?
        var searchRange = NSRange(location: 0, length: min(location, ns.length))
        while searchRange.length > 0 {
            if Task.isCancelled {
                return nil
            }
            let found = ns.range(of: options.query, options: compare, range: searchRange)
            guard found.location != NSNotFound else { break }
            last = found
            searchRange = NSRange(location: NSMaxRange(found), length: location - NSMaxRange(found))
        }
        return last
    }

    private static func effectiveLiteralWindowUTF16() -> Int {
        max(debugLiteralWindowUTF16 ?? literalWindowUTF16, 1)
    }

    private static func literalRightPadUTF16(query: String, matchCase: Bool) -> Int {
        if matchCase {
            return max(query.utf16.count, 1)
        }
        return literalCaseInsensitiveOverlapUTF16(query)
    }

    private static func prefetchNextLiteralWindow(
        in source: any FindTextSource,
        from offset: Int,
        unique: Int,
        rightPad: Int
    ) {
        guard let snapshot = source as? PieceTreeContentSnapshot, offset < snapshot.utf16Length else {
            return
        }
        let nextUnique = min(unique, snapshot.utf16Length - offset)
        let nextPad = min(rightPad, max(0, snapshot.utf16Length - offset - nextUnique))
        snapshot.prefetch(utf16Range: NSRange(location: offset, length: nextUnique + nextPad))
    }

    private static func utf16Unit(in source: any FindTextSource, at offset: Int) -> unichar? {
        guard offset >= 0, offset < source.utf16Length else {
            return nil
        }
        let slice = source.substring(utf16Offset: offset, length: 1)
        let ns = slice as NSString
        guard ns.length > 0 else {
            return nil
        }
        return ns.character(at: 0)
    }

    private static func isHighSurrogate(_ unit: unichar) -> Bool {
        unit >= 0xD800 && unit <= 0xDBFF
    }

    private static func isLowSurrogate(_ unit: unichar) -> Bool {
        unit >= 0xDC00 && unit <= 0xDFFF
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
        var wasCancelled = false

        regex.enumerateMatches(in: text, options: [], range: full) { result, _, stop in
            if Task.isCancelled {
                wasCancelled = true
                stop.pointee = true
                return
            }
            guard let range = result?.range, range.location != NSNotFound else { return }
            let index = matchCount
            matchCount += 1
            if currentIndex == nil, range.location >= anchorLocation {
                currentIndex = index
                currentRange = range
            }
        }

        if wasCancelled {
            return .empty
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
            if Task.isCancelled {
                stop.pointee = true
                return
            }
            guard let range = result?.range, range.location != NSNotFound else { return }
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
        regex.enumerateMatches(in: text, options: [], range: full) { result, _, stop in
            if Task.isCancelled {
                stop.pointee = true
                return
            }
            guard let range = result?.range, range.location != NSNotFound else { return }
            last = range
        }
        return last
    }

    private static func regexReplaceAllMatches(
        options: FindSearchOptions,
        in text: String,
        replacement: String
    ) throws -> [FindReplaceMatch] {
        let regex = try FindRegexCache.regex(pattern: regexPattern(for: options), options: regexOptions(for: options))
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let parsed = ReplacementStringParser(string: replacement).parse()
        var matches: [FindReplaceMatch] = []
        var wasCancelled = false
        regex.enumerateMatches(in: text, options: [], range: full) { result, _, stop in
            if Task.isCancelled {
                wasCancelled = true
                stop.pointee = true
                return
            }
            guard let result, result.range.location != NSNotFound else { return }
            let replacementText = parsed.containsPlaceholder
                ? parsed.string(byMatching: result, in: ns)
                : replacement
            matches.append(FindReplaceMatch(range: result.range, replacementText: replacementText))
        }
        if wasCancelled {
            throw CancellationError()
        }
        return matches
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
        var regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.matchCase {
            regexOptions.insert(.caseInsensitive)
        }
        return regexOptions
    }
}

private struct FindRegexWindowsNotImplementedError: Error, LocalizedError {
    var errorDescription: String? {
        FindSearchEngine.regexWindowsNotImplementedMessage
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
