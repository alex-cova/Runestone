import Foundation
import AppKit

/// Drives the find/replace panel via ``FindSession``/``FindSearchScheduler``/``FindSearchEngine``
/// instead of `TextView.search(for:)`'s synchronous `SearchController` path — search-as-you-type
/// and document-change refreshes are debounced 200ms and run off the main actor, so typing in the
/// find field (or editing the document while the panel is open) no longer blocks on a
/// whole-document scan. See PERFORMANCE_AUDIT.md Phase 2 #5 / migration step 2.
///
/// "Replace All" still goes through `target.search(for:replacingMatchesWith:)`
/// (`TextView`/`SearchController`) rather than ``FindSearchEngine/replaceAll``, since it needs
/// per-match ranges to build a ``BatchReplaceSet`` (preserving normal, delta-based undo) rather
/// than ``FindSearchEngine``'s whole-new-`String` result.
@MainActor
final class FindPanelController {
    weak var target: FindPanelTarget?
    weak var emphasisManager: EmphasisManager?

    private(set) var isVisible = false
    let panelView = FindPanelBarView()

    private let session = FindSession()
    private let scheduler = FindSearchScheduler()
    private var wrapAround = true

    init(target: FindPanelTarget) {
        self.target = target
        panelView.isHidden = true
        panelView.onFindTextChanged = { [weak self] text in
            self?.session.query = text
            self?.scheduleFind()
        }
        panelView.onPrevious = { [weak self] in self?.selectPreviousMatch() }
        panelView.onNext = { [weak self] in self?.selectNextMatch() }
        panelView.onReplace = { [weak self] in self?.replaceCurrentMatch() }
        panelView.onReplaceAll = { [weak self] in self?.replaceAllMatches() }
        panelView.onClose = { [weak self] in self?.hide() }
        panelView.onMatchCaseChanged = { [weak self] matchCase in
            self?.session.matchCase = matchCase
            self?.scheduleFind()
        }
        panelView.onWrapAroundChanged = { [weak self] wrapAround in
            self?.wrapAround = wrapAround
        }
        panelView.onUsesRegularExpressionChanged = { [weak self] usesRegex in
            self?.session.useRegex = usesRegex
            self?.scheduleFind()
        }
        panelView.onModeChanged = { [weak self] _ in
            guard let self else {
                return
            }
            self.target?.findPanelWillShow(panelHeight: self.panelHeight)
        }
    }

    var panelHeight: CGFloat {
        panelView.intrinsicContentSize.height
    }

    func show(mode: FindPanelMode = .find, initialQuery: String? = nil) {
        guard let target else {
            return
        }
        panelView.setMode(mode)
        if !isVisible {
            isVisible = true
            panelView.isHidden = false
            target.findPanelWillShow(panelHeight: panelHeight)
        }
        let query = initialQuery ?? target.selectedTextForFind()
        // Triggers `onFindTextChanged`, which updates `session.query`; the explicit `immediate:
        // true` below skips the 200ms debounce so opening the panel doesn't read as unresponsive.
        panelView.focusFindField(selecting: query)
        scheduleFind(immediate: true)
    }

    func hide() {
        guard isVisible else {
            return
        }
        isVisible = false
        scheduler.cancel()
        panelView.isHidden = true
        emphasisManager?.removeEmphases(for: EmphasisGroup.find)
        target?.findPanelWillHide(panelHeight: panelHeight)
        target?.findPanelTargetView.window?.makeFirstResponder(target?.findPanelTargetView)
    }

    func toggle(mode: FindPanelMode = .find) {
        if isVisible {
            hide()
        } else {
            show(mode: mode)
        }
    }

    /// Called on every document edit while the panel is visible. Debounced/off-main like typing in
    /// the find field — this used to run a synchronous full-document scan on every keystroke typed
    /// into the *editor* (not just the find field) whenever the panel was open.
    func refreshIfVisible() {
        guard isVisible, !session.query.isEmpty else {
            return
        }
        scheduleFind()
    }
}

private extension FindPanelController {
    private func scheduleFind(immediate: Bool = false) {
        guard let target else {
            return
        }
        guard !session.query.isEmpty else {
            scheduler.cancel()
            session.clearHighlights()
            panelView.matchLabelText = ""
            emphasisManager?.removeEmphases(for: EmphasisGroup.find)
            return
        }
        let text = target.textForFind
        let anchorLocation = target.findSelection?.location ?? 0
        scheduler.scheduleRefresh(
            session: session,
            text: text,
            anchorLocation: anchorLocation,
            immediate: immediate,
            isCurrent: { [weak self] in self?.isVisible ?? false },
            apply: { [weak self] in self?.didUpdateSearchOutcome() }
        )
    }

    private func didUpdateSearchOutcome() {
        updateMatchLabel()
        updateFindEmphases()
        if let currentRange = session.currentRange {
            target?.setSelectedRange(currentRange)
        }
    }

    private func updateMatchLabel() {
        guard session.matchCount > 0, let currentIndex = session.currentIndex else {
            panelView.matchLabelText = session.query.isEmpty ? "" : "0/0"
            return
        }
        panelView.matchLabelText = "\(currentIndex + 1)/\(session.matchCount)"
    }

    private func updateFindEmphases() {
        guard let emphasisManager else {
            return
        }
        let activeColor = UIColor.systemYellow
        let currentRange = session.currentRange
        // `session.highlightRanges` is a capped window (FindSearchEngine.maxHighlightedMatches)
        // around the current match, not every match in the document — deliberate, so opening the
        // find panel on a huge file with millions of matches doesn't materialize/emphasize all of
        // them. See PERFORMANCE_AUDIT.md Phase 2 #5.
        let emphases = session.highlightRanges.map { range in
            Emphasis(range: range,
                     style: .standard,
                     flash: false,
                     inactive: range != currentRange,
                     selectInDocument: false)
        }
        emphasisManager.replaceEmphases(emphases, for: EmphasisGroup.find, color: activeColor)
    }

    /// Advances to the next/previous match with a cheap forward/backward scan
    /// (`FindSearchEngine.findNext`/`findPrevious`, O(distance to match) — not a full recount),
    /// so jumping between matches on a huge file stays fast. The match-count label and highlight
    /// window are refreshed separately, immediately but asynchronously (`scheduleFind(immediate:
    /// true)`), since recomputing those requires a full-document scan.
    private func selectNextMatch() {
        guard let target, session.matchCount > 0 else {
            return
        }
        let text = target.textForFind
        let options = session.searchOptions()
        // Anchor on the target's actual current selection, not `session.currentRange` — the
        // latter is only updated once the async refresh below completes, so a second Next/
        // Previous click arriving before that lands would otherwise re-anchor on a stale range
        // and fail to advance.
        let after = target.findSelection.map(NSMaxRange) ?? 0
        let next = FindSearchEngine.findNext(options: options, in: text, after: after)
            ?? (wrapAround ? FindSearchEngine.findNext(options: options, in: text, after: 0) : nil)
        guard let next else {
            return
        }
        target.setSelectedRange(next)
        target.scrollRangeToVisible(next)
        scheduleFind(immediate: true)
    }

    private func selectPreviousMatch() {
        guard let target, session.matchCount > 0 else {
            return
        }
        let text = target.textForFind
        let options = session.searchOptions()
        let before = target.findSelection?.location ?? (text as NSString).length
        let previous = FindSearchEngine.findPrevious(options: options, in: text, before: before)
            ?? (wrapAround ? FindSearchEngine.findPrevious(options: options, in: text, before: (text as NSString).length + 1) : nil)
        guard let previous else {
            return
        }
        target.setSelectedRange(previous)
        target.scrollRangeToVisible(previous)
        scheduleFind(immediate: true)
    }

    private func replaceCurrentMatch() {
        guard let target, let currentRange = session.currentRange else {
            return
        }
        target.replace(currentRange, withText: panelView.replaceText)
        scheduleFind(immediate: true)
    }

    private func replaceAllMatches() {
        guard let target, !session.query.isEmpty else {
            return
        }
        let query = session.searchOptions().searchQuery
        let replacements = target.search(for: query, replacingMatchesWith: panelView.replaceText)
        let batch = BatchReplaceSet(replacements: replacements.map { BatchReplaceSet.Replacement(range: $0.range, text: $0.replacementText) })
        target.replaceText(in: batch)
        scheduleFind(immediate: true)
    }
}
