import Foundation

/// Manages multiple zero-length carets for multi-cursor editing.
final class MultiSelectionController {
    private(set) var selections: [NSRange] = []
    private(set) var primaryIndex: Int = 0

    var hasMultipleSelections: Bool {
        selections.count > 1
    }

    var primarySelection: NSRange? {
        guard selections.indices.contains(primaryIndex) else {
            return selections.first
        }
        return selections[primaryIndex]
    }

    func setSelections(_ ranges: [NSRange], primaryIndex: Int = 0) {
        let normalized = Self.normalize(ranges)
        selections = normalized
        self.primaryIndex = normalized.isEmpty ? 0 : min(primaryIndex, normalized.count - 1)
    }

    @discardableResult
    func addSelection(_ range: NSRange) -> Bool {
        let normalized = Self.normalize([range])
        guard let selection = normalized.first else {
            return false
        }
        guard selection.length == 0 else {
            setSelections([selection])
            return true
        }
        if selections.contains(where: { $0.location == selection.location && $0.length == 0 }) {
            return false
        }
        selections.append(selection)
        selections.sort { $0.location < $1.location }
        if let primary = primarySelection,
           let index = selections.firstIndex(where: { $0.location == primary.location && $0.length == primary.length }) {
            primaryIndex = index
        }
        return true
    }

    func collapseToPrimary() {
        guard let primary = primarySelection else {
            selections = []
            primaryIndex = 0
            return
        }
        setSelections([primary])
    }

    static func normalize(_ ranges: [NSRange]) -> [NSRange] {
        guard !ranges.isEmpty else {
            return []
        }
        let nonEmpty = ranges.filter { $0.length > 0 }
        if !nonEmpty.isEmpty {
            let expectedLength = nonEmpty[0].length
            var result: [NSRange] = []
            for range in nonEmpty where range.length == expectedLength {
                if !result.contains(where: { $0.location == range.location && $0.length == range.length }) {
                    result.append(range)
                }
            }
            return result.sorted { $0.location < $1.location }
        }
        var collapsedRanges: [NSRange] = []
        for range in ranges {
            let location = max(range.location, 0)
            if !collapsedRanges.contains(where: { $0.location == location }) {
                collapsedRanges.append(NSRange(location: location, length: 0))
            }
        }
        return collapsedRanges.sorted { $0.location < $1.location }
    }

    var isMultiCaretMode: Bool {
        selections.count > 1 && selections.allSatisfy { $0.length == 0 }
    }

    var isMultiRangeSelectionMode: Bool {
        selections.count > 1 && selections.allSatisfy { $0.length > 0 }
    }
}
