import Foundation
import AppKit

final class FindPanelController {
    weak var target: FindPanelTarget?
    weak var emphasisManager: EmphasisManager?

    private(set) var isVisible = false
    let panelView = FindPanelBarView()

    private var matches: [SearchResult] = []
    private var currentMatchIndex: Int?
    private var wrapAround = true
    private var matchCase = false
    private var usesRegularExpression = false

    init(target: FindPanelTarget) {
        self.target = target
        panelView.isHidden = true
        panelView.onFindTextChanged = { [weak self] _ in self?.performFind() }
        panelView.onPrevious = { [weak self] in self?.selectPreviousMatch() }
        panelView.onNext = { [weak self] in self?.selectNextMatch() }
        panelView.onReplace = { [weak self] in self?.replaceCurrentMatch() }
        panelView.onReplaceAll = { [weak self] in self?.replaceAllMatches() }
        panelView.onClose = { [weak self] in self?.hide() }
        panelView.onMatchCaseChanged = { [weak self] matchCase in
            self?.matchCase = matchCase
            self?.performFind()
        }
        panelView.onWrapAroundChanged = { [weak self] wrapAround in
            self?.wrapAround = wrapAround
        }
        panelView.onUsesRegularExpressionChanged = { [weak self] usesRegex in
            self?.usesRegularExpression = usesRegex
            self?.performFind()
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
        panelView.focusFindField(selecting: query)
        performFind()
    }

    func hide() {
        guard isVisible else {
            return
        }
        isVisible = false
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

    func refreshIfVisible() {
        guard isVisible, !panelView.findText.isEmpty else {
            return
        }
        performFind()
    }
}

private extension FindPanelController {
    private func performFind() {
        guard let target else {
            return
        }
        let queryText = panelView.findText
        guard !queryText.isEmpty else {
            matches = []
            currentMatchIndex = nil
            panelView.matchLabelText = ""
            emphasisManager?.removeEmphases(for: EmphasisGroup.find)
            return
        }
        let query = SearchQuery(text: queryText,
                                matchMethod: usesRegularExpression ? .regularExpression : .contains,
                                isCaseSensitive: matchCase)
        matches = target.search(for: query)
        currentMatchIndex = nearestMatchIndex()
        updateMatchLabel()
        updateFindEmphases()
        if let currentMatchIndex, matches.indices.contains(currentMatchIndex) {
            selectMatch(at: currentMatchIndex, scroll: false)
        }
    }

    private func nearestMatchIndex() -> Int? {
        guard !matches.isEmpty else {
            return nil
        }
        guard let caretLocation = target?.findSelection?.location else {
            return 0
        }
        var bestIndex = 0
        var bestDiff = Int.max
        for (index, match) in matches.enumerated() {
            let diff = abs(match.range.location - caretLocation)
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func updateMatchLabel() {
        guard !matches.isEmpty, let currentMatchIndex else {
            panelView.matchLabelText = matches.isEmpty ? "0/0" : ""
            return
        }
        panelView.matchLabelText = "\(currentMatchIndex + 1)/\(matches.count)"
    }

    private func updateFindEmphases() {
        guard let emphasisManager else {
            return
        }
        let activeColor = UIColor.systemYellow
        let emphases = matches.enumerated().map { index, match in
            Emphasis(range: match.range,
                     style: .standard,
                     flash: false,
                     inactive: index != currentMatchIndex,
                     selectInDocument: false)
        }
        emphasisManager.replaceEmphases(emphases, for: EmphasisGroup.find, color: activeColor)
    }

    private func selectMatch(at index: Int, scroll: Bool) {
        guard matches.indices.contains(index) else {
            return
        }
        currentMatchIndex = index
        let match = matches[index]
        target?.setSelectedRange(match.range)
        if scroll {
            target?.scrollRangeToVisible(match.range)
        }
        updateMatchLabel()
        updateFindEmphases()
    }

    private func selectNextMatch() {
        guard !matches.isEmpty else {
            return
        }
        let nextIndex: Int
        if let currentMatchIndex {
            if currentMatchIndex + 1 < matches.count {
                nextIndex = currentMatchIndex + 1
            } else if wrapAround {
                nextIndex = 0
            } else {
                return
            }
        } else {
            nextIndex = 0
        }
        selectMatch(at: nextIndex, scroll: true)
    }

    private func selectPreviousMatch() {
        guard !matches.isEmpty else {
            return
        }
        let previousIndex: Int
        if let currentMatchIndex {
            if currentMatchIndex > 0 {
                previousIndex = currentMatchIndex - 1
            } else if wrapAround {
                previousIndex = matches.count - 1
            } else {
                return
            }
        } else {
            previousIndex = matches.count - 1
        }
        selectMatch(at: previousIndex, scroll: true)
    }

    private func replaceCurrentMatch() {
        guard let target, let currentMatchIndex, matches.indices.contains(currentMatchIndex) else {
            return
        }
        let match = matches[currentMatchIndex]
        target.replace(match.range, withText: panelView.replaceText)
        performFind()
    }

    private func replaceAllMatches() {
        guard let target, !panelView.findText.isEmpty else {
            return
        }
        let query = SearchQuery(text: panelView.findText,
                                matchMethod: usesRegularExpression ? .regularExpression : .contains,
                                isCaseSensitive: matchCase)
        let replacements = target.search(for: query, replacingMatchesWith: panelView.replaceText)
        let batch = BatchReplaceSet(replacements: replacements.map { BatchReplaceSet.Replacement(range: $0.range, text: $0.replacementText) })
        target.replaceText(in: batch)
        performFind()
    }
}
