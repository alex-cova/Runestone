import Foundation
@preconcurrency import AppKit

@MainActor
protocol FindPanelTarget: AnyObject {
    var findPanelTargetView: NSView { get }
    var findSelection: NSRange? { get }
    /// Full document text, bridged from the live buffer. Used by ``FindSearchEngine`` (via
    /// ``FindSession``/``FindSearchScheduler``), which operates on plain `String`/`NSRange` rather
    /// than reading the target's buffer directly.
    var textForFind: String { get }
    func selectedTextForFind() -> String?
    func setSelectedRange(_ range: NSRange)
    func scrollRangeToVisible(_ range: NSRange)
    func search(for query: SearchQuery) -> [SearchResult]
    func search(for query: SearchQuery, replacingMatchesWith replacementText: String) -> [SearchReplaceResult]
    func replace(_ range: NSRange, withText text: String)
    func replaceText(in batchReplaceSet: BatchReplaceSet)
    func findPanelWillShow(panelHeight: CGFloat)
    func findPanelWillHide(panelHeight: CGFloat)
}
