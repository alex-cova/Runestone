import Foundation
import Combine

/// Computes and tracks the document's foldable regions, and drives collapsing/expanding them.
///
/// Collapsing a fold is implemented by setting each of its hidden lines' height to zero
/// (`LineManager.setHeight(of:to:)`). The line manager's red-black tree is already augmented with
/// each line's accumulated height, so a zero-height line contributes nothing to
/// `contentHeight`/`line(containingYOffset:)`/etc. for free — no separate "is this y-offset inside
/// a fold" bookkeeping is needed for scrolling or hit-testing. `LayoutManager` still needs to know
/// to *skip* hidden lines while walking rows during layout (see `isLineHidden(_:)`), since that walk
/// advances row-by-row rather than purely by y-offset.
///
/// Deviations from the plan this was ported from, both made to keep this a safe, well-scoped first
/// cut rather than introducing new concurrency risk into a codebase whose edit pipeline is
/// synchronous end-to-end (see the same reasoning in the Phase 1 log for why 1c/1d/1e were
/// descoped):
/// - Fold storage is a simple array sorted by starting line, not the `RedBlackTree` used elsewhere.
///   That tree is built for partitioning a contiguous space (document lines/bytes); folds are a
///   sparse, small (hundreds, not millions) set of possibly-nested ranges, which the tree's
///   `ClosedRangeValueDescriptor` search machinery isn't shaped for. A sorted array with binary
///   search is simpler and fast enough at this scale.
/// - Recomputation is synchronous, not the actor-based chunked design in the plan. `LineManager` is
///   a plain (non-`Sendable`) class mutated only on the main thread as a direct consequence of each
///   edit; making the recompute genuinely async would mean holding `DocumentLineNode` references (or
///   line indices) across a suspension point where another edit could land and delete/shift the very
///   lines being examined, which is a correctness hazard, not just a performance one, given
///   recomputation mutates `LineManager` heights. Instead, recomputation is a plain synchronous pass
///   (the same cost class as `LineManager.rebuild()`, which is already synchronous), and is
///   coalesced via a dirty flag consumed lazily from `LayoutManager.layoutIfNeeded()` rather than run
///   on every keystroke, so idle typing doesn't pay for it repeatedly within one layout pass.
final class FoldingController {
    var lineManager: LineManager
    var stringView: StringView
    let lineControllerStorage: LineControllerStorage
    let contentSizeService: ContentSizeService
    var foldProvider: LineFoldProvider = LineIndentationFoldProvider()
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else {
                return
            }
            if isEnabled {
                needsRecompute = true
            } else {
                expandAll()
                folds = []
            }
            didChangeFolds.send()
        }
    }

    private(set) var folds: [FoldRange] = []
    let didChangeFolds = PassthroughSubject<Void, Never>()

    private var hiddenLineIDs: Set<DocumentLineNodeID> = []
    private var collapsedFoldByHiddenLineID: [DocumentLineNodeID: FoldRange] = [:]
    private var collapsedFoldByHeaderLineID: [DocumentLineNodeID: FoldRange] = [:]
    private var needsRecompute = false

    init(lineManager: LineManager,
         stringView: StringView,
         lineControllerStorage: LineControllerStorage,
         contentSizeService: ContentSizeService) {
        self.lineManager = lineManager
        self.stringView = stringView
        self.lineControllerStorage = lineControllerStorage
        self.contentSizeService = contentSizeService
    }

    func setNeedsRecompute() {
        guard isEnabled else {
            return
        }
        needsRecompute = true
    }

    func recomputeIfNeeded() {
        guard isEnabled, needsRecompute else {
            return
        }
        needsRecompute = false
        recompute()
    }

    func isLineHidden(_ lineID: DocumentLineNodeID) -> Bool {
        isEnabled && hiddenLineIDs.contains(lineID)
    }

    /// The collapsed fold whose header is this line, if any — used to draw the placeholder pill.
    func collapsedFold(withHeaderLineID lineID: DocumentLineNodeID) -> FoldRange? {
        collapsedFoldByHeaderLineID[lineID]
    }

    /// The collapsed fold hiding this line, if any — used by caret movement to jump over it.
    func collapsedFold(hidingLineID lineID: DocumentLineNodeID) -> FoldRange? {
        collapsedFoldByHiddenLineID[lineID]
    }

    /// The deepest fold covering the given row, preferring a collapsed fold if one applies —
    /// used by the ribbon view to decide what a click on a given row should toggle.
    func deepestFold(atRow row: Int) -> FoldRange? {
        var best: FoldRange?
        for fold in folds where fold.lineRange.contains(row) {
            if best == nil {
                best = fold
            } else if fold.isCollapsed != best!.isCollapsed {
                if fold.isCollapsed {
                    best = fold
                }
            } else if fold.depth > best!.depth {
                best = fold
            }
        }
        return best
    }

    func toggleCollapse(_ fold: FoldRange) {
        guard let index = folds.firstIndex(where: { $0.id == fold.id }) else {
            return
        }
        folds[index].isCollapsed.toggle()
        if folds[index].isCollapsed {
            hide(folds[index])
        } else {
            reveal(folds[index])
        }
        didChangeFolds.send()
    }

    /// Returns a caret location that's always on a visible line. If `location` falls inside a
    /// collapsed fold's hidden lines, this returns the end of that fold's header line.
    func visibleCaretLocation(for location: Int) -> Int {
        guard isEnabled else {
            return location
        }
        guard let hiddenLine = line(containingCharacterAt: location),
              isLineHidden(hiddenLine.id),
              let fold = collapsedFold(hidingLineID: hiddenLine.id) else {
            return location
        }
        return endOfHeaderLine(for: fold)
    }

    /// Maps a selection so neither bound falls inside a collapsed fold's hidden lines.
    func adjustedSelection(_ range: NSRange) -> NSRange {
        guard isEnabled, range.length >= 0 else {
            return range
        }
        if range.length == 0 {
            let location = visibleCaretLocation(for: range.location)
            return NSRange(location: location, length: 0)
        }
        let start = visibleCaretLocation(for: range.location)
        let end = visibleCaretLocation(for: range.upperBound)
        if start > end {
            return NSRange(location: start, length: 0)
        }
        return NSRange(location: start, length: end - start)
    }

    /// When walking forward through the document (e.g. paragraph navigation), returns the first
    /// location outside a collapsed fold if `location` is inside one.
    func visibleLocationForForwardNavigation(from location: Int) -> Int {
        guard isEnabled else {
            return location
        }
        guard let hiddenLine = line(containingCharacterAt: location),
              isLineHidden(hiddenLine.id),
              let fold = collapsedFold(hidingLineID: hiddenLine.id) else {
            return location
        }
        let afterRow = fold.lineRange.upperBound + 1
        if afterRow < lineManager.lineCount {
            return lineManager.line(atRow: afterRow).location
        }
        return stringView.length
    }

    /// When walking backward through the document, returns the end of the fold header if
    /// `location` is inside a collapsed fold's hidden lines.
    func visibleLocationForBackwardNavigation(from location: Int) -> Int {
        guard isEnabled else {
            return location
        }
        guard let hiddenLine = line(containingCharacterAt: location),
              isLineHidden(hiddenLine.id),
              let fold = collapsedFold(hidingLineID: hiddenLine.id) else {
            return location
        }
        return endOfHeaderLine(for: fold)
    }

    func firstVisibleLine(atOrAfterRow row: Int) -> DocumentLineNode? {
        guard isEnabled else {
            guard row >= 0 && row < lineManager.lineCount else {
                return nil
            }
            return lineManager.line(atRow: row)
        }
        var currentRow = max(row, 0)
        while currentRow < lineManager.lineCount {
            let line = lineManager.line(atRow: currentRow)
            if !isLineHidden(line.id) {
                return line
            }
            currentRow += 1
        }
        return nil
    }

    func lastVisibleLine(atOrBeforeRow row: Int) -> DocumentLineNode? {
        guard isEnabled else {
            guard row >= 0 && row < lineManager.lineCount else {
                return nil
            }
            return lineManager.line(atRow: row)
        }
        var currentRow = min(row, lineManager.lineCount - 1)
        while currentRow >= 0 {
            let line = lineManager.line(atRow: currentRow)
            if !isLineHidden(line.id) {
                return line
            }
            currentRow -= 1
        }
        return nil
    }
}

private extension FoldingController {
    private func line(containingCharacterAt location: Int) -> DocumentLineNode? {
        guard location >= 0 else {
            return nil
        }
        let safeLocation = min(location, max(stringView.length - 1, 0))
        guard stringView.length > 0 else {
            return nil
        }
        return lineManager.line(containingCharacterAt: safeLocation)
    }

    private func endOfHeaderLine(for fold: FoldRange) -> Int {
        let headerLine = lineManager.line(atRow: fold.lineRange.lowerBound)
        return headerLine.location + headerLine.data.length
    }

    private func expandAll() {
        for fold in folds where fold.isCollapsed {
            reveal(fold)
        }
    }

    private func hide(_ fold: FoldRange) {
        guard let hiddenLineRange = fold.hiddenLineRange else {
            return
        }
        for row in hiddenLineRange where row < lineManager.lineCount {
            let line = lineManager.line(atRow: row)
            lineManager.setHeight(of: line, to: 0)
            hiddenLineIDs.insert(line.id)
            collapsedFoldByHiddenLineID[line.id] = fold
        }
        contentSizeService.invalidateContentSize()
        let headerLine = lineManager.line(atRow: fold.lineRange.lowerBound)
        collapsedFoldByHeaderLineID[headerLine.id] = fold
    }

    /// Restores a fold's hidden lines to a real (typesettable) height. Rather than trying to
    /// remember each line's pre-collapse height ourselves, this invalidates the line and resets
    /// its height to the shared estimate — the same state a freshly-inserted line starts in — so
    /// the next `layoutLinesInViewport()` pass naturally re-typesets it and self-corrects, exactly
    /// like an ordinary newly-scrolled-into-view line does.
    private func reveal(_ fold: FoldRange) {
        guard let hiddenLineRange = fold.hiddenLineRange else {
            return
        }
        for row in hiddenLineRange where row < lineManager.lineCount {
            let line = lineManager.line(atRow: row)
            hiddenLineIDs.remove(line.id)
            collapsedFoldByHiddenLineID.removeValue(forKey: line.id)
            let lineController = lineControllerStorage.getOrCreateLineController(for: line)
            lineController.invalidateEverything()
            lineManager.setHeight(of: line, to: lineController.lineHeight)
        }
        contentSizeService.invalidateContentSize()
        if fold.lineRange.lowerBound < lineManager.lineCount {
            let headerLine = lineManager.line(atRow: fold.lineRange.lowerBound)
            collapsedFoldByHeaderLineID.removeValue(forKey: headerLine.id)
        }
    }

    // swiftlint:disable:next function_body_length
    private func recompute() {
        RunestoneSignposts.interval("FoldingController.recompute") {
        let lineCount = lineManager.lineCount
        var newFolds: [FoldRange] = []
        var openFolds: [Int: Int] = [:] // depth -> starting row
        var currentDepth = 0
        var nextID = 0
        var row = 0
        while row < lineCount {
            let events = foldProvider.foldEvents(atLine: row, previousDepth: currentDepth, in: lineManager, stringView: stringView)
            for event in events {
                switch event {
                case .startFold(let depth):
                    openFolds[depth] = row
                case .endFold(let depth):
                    for (openDepth, startRow) in openFolds where openDepth > depth {
                        openFolds.removeValue(forKey: openDepth)
                        if row - 1 > startRow {
                            newFolds.append(FoldRange(id: nextID, depth: openDepth, lineRange: startRow ... (row - 1), isCollapsed: false))
                            nextID += 1
                        }
                    }
                }
                currentDepth = event.depth
            }
            row += 1
        }
        for (depth, startRow) in openFolds {
            let endRow = lineCount - 1
            if endRow > startRow {
                newFolds.append(FoldRange(id: nextID, depth: depth, lineRange: startRow ... endRow, isCollapsed: false))
                nextID += 1
            }
        }
        newFolds.sort { $0.lineRange.lowerBound < $1.lineRange.lowerBound }
        applyRecomputedFolds(newFolds)
        }
    }

    /// Reconciles freshly-recomputed (always-uncollapsed) folds against the previous collapse
    /// state, matching by which lines were hidden before rather than by fold identity — fold IDs
    /// are freshly assigned on every recompute, but `DocumentLineNodeID`s survive edits to
    /// unrelated lines, so a fold whose exact line range is unaffected by the edit keeps its
    /// collapsed state. A fold whose range shifted because of the edit is treated as new (and
    /// starts expanded) — a known, minor rough edge rather than a correctness issue.
    private func applyRecomputedFolds(_ newFolds: [FoldRange]) {
        let previouslyHiddenLineIDs = hiddenLineIDs
        hiddenLineIDs = []
        collapsedFoldByHiddenLineID = [:]
        collapsedFoldByHeaderLineID = [:]
        var resultFolds: [FoldRange] = []
        resultFolds.reserveCapacity(newFolds.count)
        for fold in newFolds {
            var updatedFold = fold
            if let hiddenLineRange = fold.hiddenLineRange {
                var lines: [DocumentLineNode] = []
                lines.reserveCapacity(hiddenLineRange.count)
                for row in hiddenLineRange where row < lineManager.lineCount {
                    lines.append(lineManager.line(atRow: row))
                }
                let wasCollapsed = !lines.isEmpty && lines.allSatisfy { previouslyHiddenLineIDs.contains($0.id) }
                updatedFold.isCollapsed = wasCollapsed
                if wasCollapsed {
                    for line in lines {
                        lineManager.setHeight(of: line, to: 0)
                        hiddenLineIDs.insert(line.id)
                        collapsedFoldByHiddenLineID[line.id] = updatedFold
                    }
                    let headerLine = lineManager.line(atRow: fold.lineRange.lowerBound)
                    collapsedFoldByHeaderLineID[headerLine.id] = updatedFold
                }
            }
            resultFolds.append(updatedFold)
        }
        // Any previously-hidden line that isn't covered by a still-collapsed fold needs to be
        // restored to a real height. We only have IDs for these (not live nodes, since holding
        // node references across a recompute would be the exact staleness hazard this class
        // avoids), so walk the document once — the same O(n) cost class as computing the folds
        // themselves, which this recompute already pays.
        let stillHiddenLineIDs = hiddenLineIDs
        if previouslyHiddenLineIDs.contains(where: { !stillHiddenLineIDs.contains($0) }) {
            let iterator = lineManager.createLineIterator()
            while let line = iterator.next() {
                if previouslyHiddenLineIDs.contains(line.id) && !stillHiddenLineIDs.contains(line.id) {
                    let lineController = lineControllerStorage.getOrCreateLineController(for: line)
                    lineController.invalidateEverything()
                    lineManager.setHeight(of: line, to: lineController.lineHeight)
                }
            }
        }
        folds = resultFolds
        contentSizeService.invalidateContentSize()
        didChangeFolds.send()
    }
}
