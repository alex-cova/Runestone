import Foundation

/// Pure tab-list index math shared by editor panes and host-app tab bars.
public enum TabListEngine {
    public static func canOpen(count: Int, max: Int) -> Bool {
        count < max
    }

    /// Index to select after closing tab at `closing` (count is tab count *before* removal).
    public static func selectionIndexAfterClose(closing: Int, selected: Int, count: Int) -> Int? {
        guard count > 1 else { return nil }
        if closing != selected {
            return selected > closing ? selected - 1 : selected
        }
        return closing < count - 1 ? closing : closing - 1
    }

    public static func nextIndex(after index: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return (index + 1) % count
    }

    public static func previousIndex(before index: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return (index - 1 + count) % count
    }

    public static func reorderDestination(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }

    public static func clamp(count: Int, selectedIndex: Int?, maxCount: Int) -> (count: Int, selectedIndex: Int?) {
        let capped = min(count, maxCount)
        guard capped > 0 else { return (0, nil) }
        let clampedSelection = selectedIndex.map { max(0, min($0, capped - 1)) } ?? 0
        return (capped, clampedSelection)
    }
}
