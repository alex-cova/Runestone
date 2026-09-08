import Foundation

/// One tab-stop in a live snippet, possibly with several linked ranges (same id).
public struct SnippetTabStop: Sendable, Equatable {
    public let id: Int
    public var ranges: [NSRange]

    public init(id: Int, ranges: [NSRange]) {
        self.id = id
        self.ranges = ranges
    }
}

/// Outcome of advancing or retreating in a ``SnippetSession``.
public enum SnippetSessionStep: Sendable, Equatable {
    /// Select these document ranges (multi-caret when linked).
    case select([NSRange])
    /// Session is finished; place a caret at this UTF-16 offset.
    case finished(caret: Int)
}

/// Tracks tab-stop ranges after a snippet is inserted so Tab / Shift-Tab can cycle them
/// and typing inside a stop grows or shrinks it (and shifts later stops).
public struct SnippetSession: Sendable, Equatable {
    public private(set) var origin: Int
    public private(set) var snippetLength: Int
    public private(set) var stops: [SnippetTabStop]
    public private(set) var index: Int

    public var isActive: Bool {
        index >= 0 && index < stops.count
    }

    public var currentRanges: [NSRange] {
        guard isActive else {
            return []
        }
        return stops[index].ranges
    }

    public init(origin: Int, snippetLength: Int, stops: [SnippetTabStop], index: Int = 0) {
        self.origin = origin
        self.snippetLength = snippetLength
        self.stops = stops
        self.index = min(max(index, 0), max(stops.count - 1, 0))
    }

    /// Builds a session from an expansion inserted at `origin`.
    ///
    /// `extraIndentPerNewline` matches surround-with reindent: every `\\n` in the *unindented*
    /// expansion text is followed by that many extra UTF-16 units in the document.
    public init?(
        expansion: SnippetExpansion,
        origin: Int,
        extraIndentPerNewline: Int = 0
    ) {
        let insertedLength: Int
        if extraIndentPerNewline == 0 {
            insertedLength = (expansion.text as NSString).length
        } else {
            let newlines = expansion.text.utf16.filter { $0 == 0x0A }.count
            insertedLength = (expansion.text as NSString).length + newlines * extraIndentPerNewline
        }
        let grouped = Self.groupedStops(
            placeholders: expansion.placeholders,
            origin: origin,
            expansionText: expansion.text,
            extraIndentPerNewline: extraIndentPerNewline
        )
        guard !grouped.isEmpty else {
            return nil
        }
        let numbered = grouped.filter { $0.id != 0 }
        if numbered.isEmpty {
            return nil
        }
        self.origin = origin
        self.snippetLength = insertedLength
        self.stops = numbered + grouped.filter { $0.id == 0 }
        self.index = 0
    }

    public func currentStep() -> SnippetSessionStep {
        .select(currentRanges)
    }

    public mutating func advance() -> SnippetSessionStep {
        guard isActive else {
            return .finished(caret: origin + snippetLength)
        }
        if index + 1 >= stops.count {
            index = stops.count
            return .finished(caret: origin + snippetLength)
        }
        index += 1
        if stops[index].id == 0, index == stops.count - 1 {
            let caret = stops[index].ranges.first?.location ?? (origin + snippetLength)
            index = stops.count
            return .finished(caret: caret)
        }
        return .select(currentRanges)
    }

    public mutating func retreat() -> SnippetSessionStep {
        guard isActive else {
            return .finished(caret: origin + snippetLength)
        }
        if index == 0 {
            return .select(currentRanges)
        }
        index -= 1
        return .select(currentRanges)
    }

    /// Updates stop ranges after a document edit. Returns `false` when the edit is outside the
    /// current stop and the session should end.
    public mutating func applyEdit(range: NSRange, replacementLength: Int) -> Bool {
        let delta = replacementLength - range.length
        if range.location + range.length <= origin {
            origin += delta
            shiftStops(startingAt: 0, by: delta, excluding: nil)
            return true
        }
        if range.location > origin + snippetLength {
            return true
        }
        guard let (stopIndex, rangeIndex) = containingStop(range) else {
            return false
        }
        var updated = stops[stopIndex].ranges[rangeIndex]
        let local = range.location - updated.location
        updated.length = max(0, local + replacementLength + (updated.length - local - range.length))
        stops[stopIndex].ranges[rangeIndex] = updated
        snippetLength += delta
        shiftStops(startingAt: range.location + range.length, by: delta, excluding: (stopIndex, rangeIndex))
        return true
    }

    public func contains(offset: Int) -> Bool {
        offset >= origin && offset <= origin + snippetLength
    }

    private mutating func shiftStops(
        startingAt location: Int,
        by delta: Int,
        excluding: (Int, Int)?
    ) {
        guard delta != 0 else {
            return
        }
        for stopIndex in stops.indices {
            for rangeIndex in stops[stopIndex].ranges.indices {
                if excluding?.0 == stopIndex, excluding?.1 == rangeIndex {
                    continue
                }
                if stops[stopIndex].ranges[rangeIndex].location >= location {
                    stops[stopIndex].ranges[rangeIndex].location += delta
                }
            }
        }
    }

    private func containingStop(_ range: NSRange) -> (Int, Int)? {
        for stopIndex in stops.indices {
            for rangeIndex in stops[stopIndex].ranges.indices {
                if Self.containsEdit(range, in: stops[stopIndex].ranges[rangeIndex]) {
                    return (stopIndex, rangeIndex)
                }
            }
        }
        return nil
    }

    private static func containsEdit(_ edit: NSRange, in placeholder: NSRange) -> Bool {
        let start = placeholder.location
        let end = placeholder.location + placeholder.length
        if edit.length == 0 {
            return edit.location >= start && edit.location <= end
        }
        return edit.location >= start && edit.location + edit.length <= end
    }

    private static func groupedStops(
        placeholders: [SnippetPlaceholder],
        origin: Int,
        expansionText: String,
        extraIndentPerNewline: Int
    ) -> [SnippetTabStop] {
        var byID: [Int: [NSRange]] = [:]
        var order: [Int] = []
        for placeholder in placeholders {
            let start = mappedOffset(
                placeholder.startOffset,
                in: expansionText,
                extraIndentPerNewline: extraIndentPerNewline
            )
            let end = mappedOffset(
                placeholder.endOffset,
                in: expansionText,
                extraIndentPerNewline: extraIndentPerNewline
            )
            let range = NSRange(location: origin + start, length: max(0, end - start))
            if byID[placeholder.id] == nil {
                order.append(placeholder.id)
            }
            byID[placeholder.id, default: []].append(range)
        }
        let numbered = order.filter { $0 != 0 }.sorted()
        let zero = order.contains(0) ? [0] : []
        return (numbered + zero).compactMap { id in
            guard let ranges = byID[id] else {
                return nil
            }
            return SnippetTabStop(id: id, ranges: ranges)
        }
    }

    public static func mappedOffset(_ offset: Int, in text: String, extraIndentPerNewline: Int) -> Int {
        guard extraIndentPerNewline != 0, offset > 0 else {
            return offset
        }
        let newlines = text.utf16.prefix(offset).filter { $0 == 0x0A }.count
        return offset + newlines * extraIndentPerNewline
    }
}
