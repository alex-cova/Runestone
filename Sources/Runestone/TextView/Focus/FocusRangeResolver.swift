import Foundation

/// Resolves the ranges of text that Focus Mode should keep at full opacity for a given set of
/// selections, following the same stateless-namespace shape as ``SelectNextOccurrence``.
///
/// A "paragraph" is a blank-line-delimited block of one or more document lines (which, in this
/// engine, are hard-newline-delimited — see `LineManager`). A "sentence" is resolved with
/// `NSString.enumerateSubstrings(options: .bySentences)` scoped to the paragraph block containing
/// it, so scanning never touches more than one block regardless of document size.
enum FocusRangeResolver {
    /// A sentence's "tight" range (what gets lit — excludes trailing whitespace) alongside its
    /// "enclosing" range (includes trailing whitespace/punctuation — used to decide which
    /// sentence a caret sitting in that trailing whitespace belongs to).
    private struct SentenceRange {
        let substring: NSRange
        let enclosing: NSRange
    }

    /// Returns the union of focus ranges for `selections` at the given `granularity`, merged and
    /// normalized via `MultiSelectionController.normalize(_:)` so overlapping/adjacent units from
    /// different cursors collapse into one span.
    static func focusRanges(for selections: [NSRange],
                            granularity: FocusGranularity,
                            lineManager: LineManager,
                            stringView: StringView) -> [NSRange] {
        var allRanges: [NSRange] = []
        for selection in selections {
            switch granularity {
            case .paragraph:
                allRanges += paragraphFocusRanges(for: selection, lineManager: lineManager, stringView: stringView)
            case .sentence:
                allRanges += sentenceFocusRanges(for: selection, lineManager: lineManager, stringView: stringView)
            }
        }
        let documentRange = NSRange(location: 0, length: stringView.string.length)
        return MultiSelectionController.normalize(allRanges).map { $0.capped(to: documentRange) }
    }
}

// MARK: - Paragraph resolution

private extension FocusRangeResolver {
    /// The paragraph blocks touched by `selection`: for a collapsed caret, the single block
    /// containing it (empty if the caret sits on a blank line); for a range, every distinct block
    /// any part of the selection overlaps.
    static func paragraphFocusRanges(for selection: NSRange, lineManager: LineManager, stringView: StringView) -> [NSRange] {
        if selection.length == 0 {
            guard let line = lineManager.line(containingCharacterAt: selection.location), !isBlank(line, stringView: stringView) else {
                return []
            }
            return [blockRange(containingLine: line, lineManager: lineManager, stringView: stringView)]
        }
        var ranges: [NSRange] = []
        for line in lineManager.lines(in: selection) where !isBlank(line, stringView: stringView) {
            if let last = ranges.last, line.location >= last.location, line.location < last.upperBound {
                continue // Already covered by the block appended for a preceding line.
            }
            ranges.append(blockRange(containingLine: line, lineManager: lineManager, stringView: stringView))
        }
        return ranges
    }

    /// Expands `line` to the full blank-line-delimited block it belongs to.
    static func blockRange(containingLine line: DocumentLineNode, lineManager: LineManager, stringView: StringView) -> NSRange {
        var startRow = line.index
        while startRow > 0, !isBlank(lineManager.line(atRow: startRow - 1), stringView: stringView) {
            startRow -= 1
        }
        var endRow = line.index
        while endRow < lineManager.lineCount - 1, !isBlank(lineManager.line(atRow: endRow + 1), stringView: stringView) {
            endRow += 1
        }
        let startLine = lineManager.line(atRow: startRow)
        let endLine = lineManager.line(atRow: endRow)
        return NSRange(location: startLine.location, length: endLine.location + endLine.data.length - startLine.location)
    }

    static func isBlank(_ line: DocumentLineNode, stringView: StringView) -> Bool {
        guard line.data.length > 0 else {
            return true
        }
        guard let content = stringView.substring(in: NSRange(location: line.location, length: line.data.length)) else {
            return true
        }
        return content.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Sentence resolution

private extension FocusRangeResolver {
    static func sentenceFocusRanges(for selection: NSRange, lineManager: LineManager, stringView: StringView) -> [NSRange] {
        let blocks = paragraphFocusRanges(for: selection, lineManager: lineManager, stringView: stringView)
        guard !blocks.isEmpty else {
            return []
        }
        if selection.length == 0 {
            guard let block = blocks.first else {
                return []
            }
            let sentences = sentenceRanges(in: block, stringView: stringView)
            let location = selection.location
            if let match = sentences.first(where: { location >= $0.enclosing.location && location < $0.enclosing.upperBound }) {
                return match.substring.length > 0 ? [match.substring] : [block]
            } else if let last = sentences.last, location >= last.enclosing.upperBound {
                return [last.substring]
            } else {
                return [block]
            }
        } else {
            var result: [NSRange] = []
            for block in blocks {
                let sentences = sentenceRanges(in: block, stringView: stringView)
                for sentence in sentences where sentence.enclosing.overlaps(selection) {
                    result.append(sentence.substring)
                }
            }
            return result.isEmpty ? blocks : result
        }
    }

    /// Every sentence within `block`, in the block's absolute document coordinates.
    private static func sentenceRanges(in block: NSRange, stringView: StringView) -> [SentenceRange] {
        guard block.length > 0, let substring = stringView.substring(in: block) else {
            return []
        }
        let nsSubstring = substring as NSString
        var result: [SentenceRange] = []
        nsSubstring.enumerateSubstrings(in: NSRange(location: 0, length: nsSubstring.length), options: [.bySentences, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            let absoluteSubstringRange = NSRange(location: substringRange.location + block.location, length: substringRange.length)
            let absoluteEnclosingRange = NSRange(location: enclosingRange.location + block.location, length: enclosingRange.length)
            result.append(SentenceRange(substring: absoluteSubstringRange, enclosing: absoluteEnclosingRange))
        }
        return result
    }
}
