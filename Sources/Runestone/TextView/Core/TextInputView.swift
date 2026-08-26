import Foundation
@preconcurrency import AppKit
// swiftlint:disable file_length
import Combine

@MainActor
protocol TextInputViewDelegate: AnyObject {
    func textInputViewWillBeginEditing(_ view: TextInputView)
    func textInputViewDidBeginEditing(_ view: TextInputView)
    func textInputViewDidEndEditing(_ view: TextInputView)
    func textInputViewDidCancelBeginEditing(_ view: TextInputView)
    func textInputViewDidChange(_ view: TextInputView)
    func textInputViewDidChangeSelection(_ view: TextInputView)
    func textInputView(_ view: TextInputView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
    func textInputViewDidInvalidateContentSize(_ view: TextInputView)
    func textInputView(_ view: TextInputView, didProposeContentOffsetAdjustment contentOffsetAdjustment: CGPoint)
    func textInputViewDidChangeGutterWidth(_ view: TextInputView)
    func textInputViewDidBeginFloatingCursor(_ view: TextInputView)
    func textInputViewDidEndFloatingCursor(_ view: TextInputView)
    func textInputViewDidUpdateMarkedRange(_ view: TextInputView)
    func textInputView(_ view: TextInputView, canReplaceTextIn highlightedRange: HighlightedRange) -> Bool
    func textInputView(_ view: TextInputView, replaceTextIn highlightedRange: HighlightedRange)
    func textInputViewIsSelectable(_ view: TextInputView) -> Bool
    func textInputViewIsEditable(_ view: TextInputView) -> Bool
    func textInputView(_ view: TextInputView, didRequestSelectionInteraction enabled: Bool)
    func textInputViewDidRequestToggleFindPanel(_ view: TextInputView, mode: FindPanelMode)
    func textInputView(_ view: TextInputView, shouldInterceptKeyDown event: NSEvent) -> Bool
    func textInputView(_ view: TextInputView, didReceiveKeyDown event: NSEvent)
    func textInputViewDidReceiveCaretRepositioningClick(_ view: TextInputView)
    func textInputViewDidFinishSyntaxParse(_ view: TextInputView)
    func textInputView(_ view: TextInputView, didChangeContent change: TextContentChange)
}

// swiftlint:disable:next type_body_length
final class TextInputView: UIView, UITextInput {
    // MARK: - UITextInput
    var selectedTextRange: UITextRange? {
        get {
            if let range = _selectedRange {
                return IndexedRange(range)
            } else {
                return nil
            }
        }
        set {
            // We should not use this setter. It's intended for UIKit to use. It'll invoke the setter in various scenarios, for example when navigating the text using the keyboard.
            // On the iOS 16 beta, UIKit may pass an NSRange with a negatives length (e.g. {4, -2}) when double tapping to select text. This will cause a crash when UIKit later attempts to use the selected range with NSString's -substringWithRange:. This can be tested with a string containing the following three lines:
            //    A
            //
            //    A
            // Placing the character on the second line, which is empty, and double tapping several times on the empty line to select text will cause the editor to crash. To work around this we take the non-negative value of the selected range. Last tested on August 30th, 2022.
                let newRange = (newValue as? IndexedRange)?.range.nonNegativeLength
                let sanitizedRange = sanitizedSelection(newRange)
                if sanitizedRange != _selectedRange || multiSelectionController.hasMultipleSelections {
                notifyDelegateAboutSelectionChangeInLayoutSubviews = true
                // The logic for determining whether or not to notify the input delegate is based on advice provided by Alexander Blach, developer of Textastic.
                var shouldNotifyInputDelegate = false
                if didCallPositionFromPositionInDirectionWithOffset {
                    shouldNotifyInputDelegate = true
                    didCallPositionFromPositionInDirectionWithOffset = false
                }
                // This is a consequence of our workaround that ensures multi-stage input, such as when entering Korean,
                // works correctly. The workaround causes bugs when selecting words using Shift + Option + Arrow Keys
                // followed by Shift + Arrow Keys if we do not treat it as a special case.
                // The consequence of not having this workaround is that Shift + Arrow Keys may adjust the wrong end of
                // the selected text when followed by navigating between word boundaries usign Shift + Option + Arrow Keys.
                if customTokenizer.didCallPositionFromPositionToWordBoundary && !didCallDeleteBackward {
                    shouldNotifyInputDelegate = true
                    customTokenizer.didCallPositionFromPositionToWordBoundary = false
                }
                didCallDeleteBackward = false
                notifyInputDelegateAboutSelectionChangeInLayoutSubviews = !shouldNotifyInputDelegate
                if shouldNotifyInputDelegate {
                    inputDelegate?.selectionWillChange(self)
                }
                if !isApplyingMultipleSelectionUpdate {
                    multiSelectionController.setSelections(sanitizedRange.map { [$0] } ?? [])
                }
                _selectedRange = sanitizedRange
                if shouldNotifyInputDelegate {
                    inputDelegate?.selectionDidChange(self)
                }
            }
        }
    }
    private(set) var markedTextRange: UITextRange? {
        get {
            if let imeMarkedRange = imeMarkedRange {
                return IndexedRange(imeMarkedRange)
            } else {
                return nil
            }
        }
        set {
            imeMarkedRange = (newValue as? IndexedRange)?.range.nonNegativeLength
        }
    }
    var markedTextStyle: [NSAttributedString.Key: Any]?
    var beginningOfDocument: UITextPosition {
        IndexedPosition(index: 0)
    }
    var endOfDocument: UITextPosition {
        IndexedPosition(index: string.length)
    }
    weak var inputDelegate: UITextInputDelegate?
    var hasText: Bool {
        string.length > 0
    }
    var tokenizer: UITextInputTokenizer {
        customTokenizer
    }
    private lazy var customTokenizer = TextInputStringTokenizer(textInput: self,
                                                                stringView: stringView,
                                                                lineManager: lineManager,
                                                                lineControllerStorage: lineControllerStorage)
    var autocorrectionType: UITextAutocorrectionType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var smartQuotesType: UITextSmartQuotesType = .default
    var smartDashesType: UITextSmartDashesType = .default
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .default
    var spellCheckingType: UITextSpellCheckingType = .default
    var keyboardType: UIKeyboardType = .default
    var keyboardAppearance: UIKeyboardAppearance = .default
    var returnKeyType: UIReturnKeyType = .default
    @objc var insertionPointColor: UIColor = .label {
        didSet {
            if insertionPointColor != oldValue {
                selectionOverlayController.updateColors()
                selectionOverlayController.updateLayout()
            }
        }
    }
    @objc var selectionBarColor: UIColor = .label {
        didSet {
            if selectionBarColor != oldValue {
                selectionOverlayController.updateColors()
            }
        }
    }
    @objc var selectionHighlightColor: UIColor = UIColor(srgbRed: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1) {
        didSet {
            if selectionHighlightColor != oldValue {
                // Colors only — do not call updateLayout(). Theme is often applied
                // mid-setState after stringView is swapped but before lineManager is,
                // and caretRect(at:) force-unwraps a line lookup that can fail then.
                selectionOverlayController.updateColors()
            }
        }
    }
    var isEditing = false {
        didSet {
            if isEditing != oldValue {
                layoutManager.isEditing = isEditing
                selectionOverlayController.editingDidChange(isEditing: isEditing)
            }
        }
    }
    override var undoManager: UndoManager? {
        timedUndoManager
    }

    // MARK: - Appearance
    var theme: Theme {
        didSet {
            applyThemeToChildren()
        }
    }
    var showLineNumbers = false {
        didSet {
            if showLineNumbers != oldValue {
                caretRectService.showLineNumbers = showLineNumbers
                gutterWidthService.showLineNumbers = showLineNumbers
                layoutManager.showLineNumbers = showLineNumbers
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var isLineFoldingEnabled = false {
        didSet {
            if isLineFoldingEnabled != oldValue {
                foldingController.isEnabled = isLineFoldingEnabled
                gutterWidthService.showFoldingRibbon = isLineFoldingEnabled
                layoutManager.showFoldingRibbon = isLineFoldingEnabled
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var isFocusModeEnabled = false {
        didSet {
            if isFocusModeEnabled != oldValue {
                focusModeController.isEnabled = isFocusModeEnabled
                updateFocusModeIfNeeded()
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var focusGranularity: FocusGranularity {
        get {
            focusModeController.granularity
        }
        set {
            if newValue != focusModeController.granularity {
                focusModeController.granularity = newValue
                updateFocusModeIfNeeded()
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var unfocusedTextAlpha: CGFloat {
        get {
            focusModeController.unfocusedAlpha
        }
        set {
            let clamped = min(max(newValue, 0), 1)
            if clamped != focusModeController.unfocusedAlpha {
                focusModeController.unfocusedAlpha = clamped
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var focusedRanges: [NSRange] {
        focusModeController.focusedRanges
    }
    var lineSelectionDisplayType: LineSelectionDisplayType {
        get {
            layoutManager.lineSelectionDisplayType
        }
        set {
            layoutManager.lineSelectionDisplayType = newValue
        }
    }
    var showTabs: Bool {
        get {
            invisibleCharacterConfiguration.showTabs
        }
        set {
            if newValue != invisibleCharacterConfiguration.showTabs {
                invisibleCharacterConfiguration.showTabs = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var showSpaces: Bool {
        get {
            invisibleCharacterConfiguration.showSpaces
        }
        set {
            if newValue != invisibleCharacterConfiguration.showSpaces {
                invisibleCharacterConfiguration.showSpaces = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var showNonBreakingSpaces: Bool {
        get {
            invisibleCharacterConfiguration.showNonBreakingSpaces
        }
        set {
            if newValue != invisibleCharacterConfiguration.showNonBreakingSpaces {
                invisibleCharacterConfiguration.showNonBreakingSpaces = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var showLineBreaks: Bool {
        get {
            invisibleCharacterConfiguration.showLineBreaks
        }
        set {
            if newValue != invisibleCharacterConfiguration.showLineBreaks {
                invisibleCharacterConfiguration.showLineBreaks = newValue
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.setNeedsDisplayOnLines()
                setNeedsLayout()
            }
        }
    }
    var showSoftLineBreaks: Bool {
        get {
            invisibleCharacterConfiguration.showSoftLineBreaks
        }
        set {
            if newValue != invisibleCharacterConfiguration.showSoftLineBreaks {
                invisibleCharacterConfiguration.showSoftLineBreaks = newValue
                invalidateLines()
                layoutManager.setNeedsLayout()
                layoutManager.setNeedsDisplayOnLines()
                setNeedsLayout()
            }
        }
    }
    var warningCharacters: Set<Character> {
        get {
            invisibleCharacterConfiguration.warningCharacters
        }
        set {
            if newValue != invisibleCharacterConfiguration.warningCharacters {
                invisibleCharacterConfiguration.warningCharacters = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var tabSymbol: String {
        get {
            invisibleCharacterConfiguration.tabSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.tabSymbol {
                invisibleCharacterConfiguration.tabSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var spaceSymbol: String {
        get {
            invisibleCharacterConfiguration.spaceSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.spaceSymbol {
                invisibleCharacterConfiguration.spaceSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var nonBreakingSpaceSymbol: String {
        get {
            invisibleCharacterConfiguration.nonBreakingSpaceSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.nonBreakingSpaceSymbol {
                invisibleCharacterConfiguration.nonBreakingSpaceSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var lineBreakSymbol: String {
        get {
            invisibleCharacterConfiguration.lineBreakSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.lineBreakSymbol {
                invisibleCharacterConfiguration.lineBreakSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var softLineBreakSymbol: String {
        get {
            invisibleCharacterConfiguration.softLineBreakSymbol
        }
        set {
            if newValue != invisibleCharacterConfiguration.softLineBreakSymbol {
                invisibleCharacterConfiguration.softLineBreakSymbol = newValue
                layoutManager.setNeedsDisplayOnLines()
            }
        }
    }
    var indentStrategy: IndentStrategy = .tab(length: 2) {
        didSet {
            if indentStrategy != oldValue {
                indentController.indentStrategy = indentStrategy
                layoutManager.setNeedsLayout()
                setNeedsLayout()
                // Do not call layoutIfNeeded() here — SwiftUI updateNSView often
                // assigns indentStrategy mid-pass; forcing layout aborts AppKit.
            }
        }
    }
    var gutterLeadingPadding: CGFloat = 8 {
        didSet {
            if gutterLeadingPadding != oldValue {
                gutterWidthService.gutterLeadingPadding = gutterLeadingPadding
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var gutterTrailingPadding: CGFloat = 6 {
        didSet {
            if gutterTrailingPadding != oldValue {
                gutterWidthService.gutterTrailingPadding = gutterTrailingPadding
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var gutterMinimumCharacterCount: Int = 3 {
        didSet {
            if gutterMinimumCharacterCount != oldValue {
                gutterWidthService.gutterMinimumCharacterCount = gutterMinimumCharacterCount
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var textContainerInset: UIEdgeInsets {
        get {
            layoutManager.textContainerInset
        }
        set {
            if newValue != layoutManager.textContainerInset {
                caretRectService.textContainerInset = newValue
                selectionRectService.textContainerInset = newValue
                contentSizeService.textContainerInset = newValue
                layoutManager.textContainerInset = newValue
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var isLineWrappingEnabled: Bool {
        get {
            layoutManager.isLineWrappingEnabled
        }
        set {
            if newValue != layoutManager.isLineWrappingEnabled {
                contentSizeService.isLineWrappingEnabled = newValue
                layoutManager.isLineWrappingEnabled = newValue
                invalidateLines()
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var lineBreakMode: LineBreakMode = .byWordWrapping {
        didSet {
            if lineBreakMode != oldValue {
                invalidateLines()
                contentSizeService.invalidateContentSize()
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var gutterWidth: CGFloat {
        gutterWidthService.gutterWidth
    }
    var lineHeightMultiplier: CGFloat = 1 {
        didSet {
            if lineHeightMultiplier != oldValue {
                selectionRectService.lineHeightMultiplier = lineHeightMultiplier
                layoutManager.lineHeightMultiplier = lineHeightMultiplier
                invalidateLines()
                lineManager.estimatedLineHeight = estimatedLineHeight
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var kern: CGFloat = 0 {
        didSet {
            if kern != oldValue {
                invalidateLines()
                pageGuideController.kern = kern
                contentSizeService.invalidateContentSize()
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    var characterPairs: [CharacterPair] = [] {
        didSet {
            maximumLeadingCharacterPairComponentLength = characterPairs.map(\.leading.utf16.count).max() ?? 0
        }
    }
    var characterPairTrailingComponentDeletionMode: CharacterPairTrailingComponentDeletionMode = .disabled
    var showPageGuide = false {
        didSet {
            if showPageGuide != oldValue {
                if showPageGuide {
                    addSubview(pageGuideController.guideView)
                    sendSubviewToBack(pageGuideController.guideView)
                    setNeedsLayout()
                } else {
                    pageGuideController.guideView.removeFromSuperview()
                    setNeedsLayout()
                }
            }
        }
    }
    var pageGuideColumn: Int {
        get {
            pageGuideController.column
        }
        set {
            if newValue != pageGuideController.column {
                pageGuideController.column = newValue
                setNeedsLayout()
            }
        }
    }
    var showReformattingGuideShading: Bool {
        get {
            pageGuideController.guideView.showReformattingGuideShading
        }
        set {
            pageGuideController.guideView.showReformattingGuideShading = newValue
            setNeedsLayout()
        }
    }
    private var estimatedLineHeight: CGFloat {
        theme.font.totalLineHeight * lineHeightMultiplier
    }
    var highlightedRanges: [HighlightedRange] {
        get {
            emphasisManager.userHighlightedRanges
        }
        set {
            if newValue != emphasisManager.userHighlightedRanges {
                emphasisManager.userHighlightedRanges = newValue
                layoutManager.setNeedsLayout()
                setNeedsLayout()
            }
        }
    }
    let emphasisManager = EmphasisManager()
    var diagnostics: [TextViewDiagnostic] {
        get {
            diagnosticEmphasisController.diagnostics
        }
        set {
            diagnosticEmphasisController.setDiagnostics(newValue)
        }
    }
    var bracketPairEmphasis: BracketPairEmphasis?

    // MARK: - Contents
    weak var delegate: TextInputViewDelegate?
    var string: NSString {
        get {
            stringView.string
        }
        set {
            if newValue != stringView.string {
                stringView.string = newValue
                lineManager.rebuild()
                if let oldSelectedRange = selection {
                    inputDelegate?.selectionWillChange(self)
                    selection = safeSelectionRange(from: oldSelectedRange)
                    inputDelegate?.selectionDidChange(self)
                }
                contentSizeService.invalidateContentSize()
                gutterWidthService.invalidateLineNumberWidth()
                invalidateLines()
                layoutManager.setNeedsLayout()
                setNeedsLayout()
                if !preserveUndoStackWhenSettingString {
                    undoManager?.removeAllActions()
                }
                startFullParse(of: newValue)
            }
        }
    }
    var viewport: CGRect {
        get {
            layoutManager.viewport
        }
        set {
            if newValue != layoutManager.viewport {
                layoutManager.viewport = newValue
                layoutManager.setNeedsLayout()
                // Must dirty the view: UIView.layout does not recurse into children,
                // and scroll updates contentOffset → viewport without a parent layout
                // pass. Without this, layoutLinesInViewport never runs and scrolled
                // regions stay blank.
                setNeedsLayout()
                ensureViewportSyntaxParse()
            }
        }
    }
    var scrollViewWidth: CGFloat = 0 {
        didSet {
            if scrollViewWidth != oldValue {
                contentSizeService.scrollViewWidth = scrollViewWidth
                layoutManager.scrollViewWidth = scrollViewWidth
                // Assigned from TextView.layoutSubviews — defer line invalidation so we
                // do not rebuild fragments mid-pass.
                if isLineWrappingEnabled {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.invalidateLines()
                        self.layoutManager.setNeedsLayout()
                        self.setNeedsLayout()
                    }
                }
            }
        }
    }
    var contentSize: CGSize {
        contentSizeService.contentSize
    }
    @nonobjc var selection: NSRange? {
        get {
            _selectedRange
        }
        set {
            let sanitizedRange = sanitizedSelection(newValue)
            if sanitizedRange != _selectedRange || multiSelectionController.hasMultipleSelections {
                if !isApplyingMultipleSelectionUpdate {
                    multiSelectionController.setSelections(sanitizedRange.map { [$0] } ?? [])
                }
                _selectedRange = sanitizedRange
                // Defer host notification — callers often assign selection during
                // setState / updateNSView / layout, and sync callbacks re-enter AppKit.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.delegate?.textInputViewDidChangeSelection(self)
                }
            }
        }
    }

    var selectedRanges: [NSRange] {
        get {
            if multiSelectionController.selections.isEmpty {
                return selection.map { [$0] } ?? []
            }
            return multiSelectionController.selections
        }
        set {
            applySelectedRanges(newValue)
        }
    }

    var isMultiCursorActive: Bool {
        multiSelectionController.hasMultipleSelections
    }

    private var _selectedRange: NSRange? {
        didSet {
            if _selectedRange != oldValue {
                if !isApplyingMultipleSelectionUpdate,
                   let selectedRange = _selectedRange,
                   multiSelectionController.selections != [selectedRange] {
                    multiSelectionController.setSelections([selectedRange])
                }
                if !isApplyingBlockSelectionUpdate, blockSelectionController.isActive {
                    blockSelectionController.end()
                }
                layoutManager.selectedRange = _selectedRange
                layoutManager.setNeedsLayoutLineSelection()
                selectionOverlayController.selectionDidChange()
                if let location = _selectedRange?.location {
                    bracketMatchingController.characterPairs = characterPairs
                    bracketMatchingController.emphasisStyle = bracketPairEmphasis
                    bracketMatchingController.emphasizePairs(at: location)
                } else {
                    bracketMatchingController.clearEmphasis()
                }
                updateFocusModeIfNeeded()
                setNeedsLayout()
            }
        }
    }
    var canBecomeFirstResponder: Bool {
        true
    }
    weak var gutterParentView: UIView? {
        get {
            layoutManager.gutterParentView
        }
        set {
            layoutManager.gutterParentView = newValue
        }
    }
    var scrollViewSafeAreaInsets: UIEdgeInsets = .zero {
        didSet {
            if scrollViewSafeAreaInsets != oldValue {
                layoutManager.safeAreaInsets = scrollViewSafeAreaInsets
            }
        }
    }
    var gutterContainerView: UIView {
        layoutManager.gutterContainerView
    }
    var isFileBacked: Bool {
        stringView.isFileBacked
    }
    var documentLength: Int {
        stringView.length
    }
    private(set) var stringView = StringView() {
        didSet {
            if stringView !== oldValue {
                caretRectService.stringView = stringView
                lineManager.stringView = stringView
                lineControllerFactory.stringView = stringView
                lineControllerStorage.stringView = stringView
                layoutManager.stringView = stringView
                indentController.stringView = stringView
                lineMovementController.stringView = stringView
                customTokenizer.stringView = stringView
                foldingController.stringView = stringView
                focusModeController.stringView = stringView
            }
        }
    }
    private(set) var lineManager: LineManager {
        didSet {
            if lineManager !== oldValue {
                indentController.lineManager = lineManager
                lineMovementController.lineManager = lineManager
                gutterWidthService.lineManager = lineManager
                contentSizeService.lineManager = lineManager
                caretRectService.lineManager = lineManager
                selectionRectService.lineManager = lineManager
                highlightService.lineManager = lineManager
                customTokenizer.lineManager = lineManager
                foldingController.lineManager = lineManager
                foldingController.setNeedsRecompute()
                focusModeController.lineManager = lineManager
            }
        }
    }
    var viewHierarchyContainsCaret: Bool {
        selectionOverlayController.isEnabled && isEditing
    }

    func setSelectionOverlayEnabled(_ enabled: Bool) {
        selectionOverlayController.isEnabled = enabled
        if enabled {
            selectionOverlayController.updateLayout()
        }
    }

    func enableSelectionCursorBlinks() {
        selectionOverlayController.enableCursorBlinks()
    }
    var lineEndings: LineEnding = .lf
    private(set) var isRestoringPreviouslyDeletedText = false

    // MARK: - Private
    private var languageMode: InternalLanguageMode = PlainTextInternalLanguageMode() {
        didSet {
            if languageMode !== oldValue {
                indentController.languageMode = languageMode
                if let treeSitterLanguageMode = languageMode as? TreeSitterInternalLanguageMode {
                    treeSitterLanguageMode.delegate = self
                    treeSitterFoldProvider.languageMode = treeSitterLanguageMode
                    foldingController.foldProvider = treeSitterFoldProvider
                    treeSitterFoldProvider.invalidate()
                    foldingController.setNeedsRecompute()
                } else {
                    foldingController.foldProvider = LineIndentationFoldProvider()
                }
            }
        }
    }
    /// Bumped on every ``setState`` / ``setLanguageMode`` so a stale deferred parse cannot
    /// invalidate highlighting or notify after the view has moved on to a newer document.
    private var syntaxParseGeneration = 0
    private var syntaxParsePolicy: SyntaxParsePolicy = .eager
    private var hasNotifiedSyntaxParse = false
    /// Window last handed to ``startViewportParse``. Prevents layout + `contentOffset` from
    /// cancelling the same in-flight expansion by starting it twice.
    private var inFlightViewportParseRange: NSRange?
    private let lineControllerFactory: LineControllerFactory
    private let lineControllerStorage: LineControllerStorage
    private let layoutManager: LayoutManager
    private let timedUndoManager = TimedUndoManager()
    private let indentController: IndentController
    private let lineMovementController: LineMovementController
    private let pageGuideController = PageGuideController()
    private let gutterWidthService: GutterWidthService
    private let contentSizeService: ContentSizeService
    private let caretRectService: CaretRectService
    private let selectionRectService: SelectionRectService
    private var selectionOverlayController: SelectionOverlayController!
    private let bracketMatchingController: BracketMatchingController
    private let diagnosticEmphasisController = DiagnosticEmphasisController()
    private let multiSelectionController = MultiSelectionController()
    private var isApplyingMultipleSelectionUpdate = false
    let blockSelectionController = BlockSelectionController()
    private var isApplyingBlockSelectionUpdate = false
    /// Set for the duration of a multi-caret batch operation that goes through
    /// `IndentControllerDelegate` (currently `insertLineBreakAtAllSelections()`), so the delegate
    /// callback can tell `replaceText` what the whole caret set should roll back to on undo,
    /// instead of the single range it would otherwise infer from `selection`.
    private var pendingMultiSelectionUndoRestore: (ranges: [NSRange], primaryIndex: Int)?
    private let highlightService: HighlightService
    private let foldingController: FoldingController
    private let focusModeController: FocusModeController
    private let treeSitterFoldProvider = TreeSitterLineFoldProvider()
    private let invisibleCharacterConfiguration = InvisibleCharacterConfiguration()
    var imeMarkedRange: NSRange? {
        get {
            layoutManager.markedRange
        }
        set {
            layoutManager.markedRange = newValue
        }
    }
    private var floatingCaretView: FloatingCaretView?
    private var insertionPointColorBeforeFloatingBegan: UIColor = .label
    private var maximumLeadingCharacterPairComponentLength = 0
    private var hasPendingFullLayout = false
    private let editMenuController = EditMenuController()
    private var notifyInputDelegateAboutSelectionChangeInLayoutSubviews = false
    private var notifyDelegateAboutSelectionChangeInLayoutSubviews = false
    private var didCallPositionFromPositionInDirectionWithOffset = false
    private var didCallDeleteBackward = false
    private var hasDeletedTextWithPendingLayoutSubviews = false
    private var preserveUndoStackWhenSettingString = false
    private var cancellables: [AnyCancellable] = []
    var selectionAnchor: Int?
    var isMouseSelecting = false
    /// An Option-click's point, held until `mouseDragged`/`mouseUp` resolve whether it was a
    /// click (add a caret) or a drag (start a block/column selection). See
    /// `TextInputView+MouseKeyboard.swift`.
    var pendingOptionClickPoint: CGPoint?
    /// Armed by a bare ⌘K, consumed by the next ⌘-key within the window — implements the ⌘K ⌘D
    /// "skip current occurrence" chord. See `handleCommandKeyDown(_:)`.
    var pendingChordPrefix: (key: String, timestamp: TimeInterval)?

    // MARK: - Lifecycle
    init(theme: Theme) {
        self.theme = theme
        lineManager = LineManager(stringView: stringView)
        highlightService = HighlightService(lineManager: lineManager)
        bracketMatchingController = BracketMatchingController(stringView: stringView)
        lineControllerFactory = LineControllerFactory(stringView: stringView,
                                                      highlightService: highlightService,
                                                      invisibleCharacterConfiguration: invisibleCharacterConfiguration)
        lineControllerStorage = LineControllerStorage(stringView: stringView, lineControllerFactory: lineControllerFactory)
        gutterWidthService = GutterWidthService(lineManager: lineManager)
        contentSizeService = ContentSizeService(lineManager: lineManager,
                                                lineControllerStorage: lineControllerStorage,
                                                gutterWidthService: gutterWidthService,
                                                invisibleCharacterConfiguration: invisibleCharacterConfiguration)
        caretRectService = CaretRectService(stringView: stringView,
                                            lineManager: lineManager,
                                            lineControllerStorage: lineControllerStorage,
                                            gutterWidthService: gutterWidthService)
        selectionRectService = SelectionRectService(lineManager: lineManager,
                                                    contentSizeService: contentSizeService,
                                                    gutterWidthService: gutterWidthService,
                                                    caretRectService: caretRectService)
        foldingController = FoldingController(lineManager: lineManager,
                                              stringView: stringView,
                                              lineControllerStorage: lineControllerStorage,
                                              contentSizeService: contentSizeService)
        focusModeController = FocusModeController(lineManager: lineManager, stringView: stringView)
        layoutManager = LayoutManager(lineManager: lineManager,
                                      languageMode: languageMode,
                                      stringView: stringView,
                                      lineControllerStorage: lineControllerStorage,
                                      contentSizeService: contentSizeService,
                                      gutterWidthService: gutterWidthService,
                                      caretRectService: caretRectService,
                                      selectionRectService: selectionRectService,
                                      highlightService: highlightService,
                                      invisibleCharacterConfiguration: invisibleCharacterConfiguration)
        indentController = IndentController(stringView: stringView,
                                            lineManager: lineManager,
                                            languageMode: languageMode,
                                            indentStrategy: indentStrategy,
                                            indentFont: theme.font)
        lineMovementController = LineMovementController(lineManager: lineManager,
                                                        stringView: stringView,
                                                        lineControllerStorage: lineControllerStorage)
        super.init(frame: .zero)
        emphasisManager.highlightService = highlightService
        emphasisManager.onEmphasesChanged = { [weak self] in
            guard let self else {
                return
            }
            self.layoutManager.setNeedsLayout()
            self.setNeedsLayout()
        }
        emphasisManager.onSelectInDocument = { [weak self] range in
            self?.selection = range
        }
        bracketMatchingController.emphasisManager = emphasisManager
        diagnosticEmphasisController.emphasisManager = emphasisManager
        layoutManager.foldingController = foldingController
        layoutManager.focusModeController = focusModeController
        lineMovementController.foldingController = foldingController
        caretRectService.foldingController = foldingController
        customTokenizer.foldingController = foldingController
        selectionOverlayController = SelectionOverlayController(textInputView: self,
                                                                caretRectService: caretRectService,
                                                                selectionRectService: selectionRectService)
        selectionOverlayController.install()
        applyThemeToChildren()
        indentController.delegate = self
        lineControllerStorage.delegate = self
        gutterWidthService.gutterLeadingPadding = gutterLeadingPadding
        gutterWidthService.gutterTrailingPadding = gutterTrailingPadding
        gutterWidthService.gutterMinimumCharacterCount = gutterMinimumCharacterCount
        layoutManager.delegate = self
        layoutManager.textInputView = self
        editMenuController.delegate = self
        setupContentSizeObserver()
        setupGutterWidthObserver()
        setupFoldingObserver()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        if canBecomeFirstResponder {
            delegate?.textInputViewWillBeginEditing(self)
        }
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            NSTextInputContext.current?.activate()
            delegate?.textInputViewDidBeginEditing(self)
        } else {
            // This is called in the case where:
            // 1. The view is the first responder.
            // 2. A view is presented modally on top of the editor.
            // 3. The modally presented view is dismissed.
            // 4. The responder chain attempts to make the text view first responder again but super.becomeFirstResponder() returns false.
            delegate?.textInputViewDidCancelBeginEditing(self)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        NSTextInputContext.current?.deactivate()
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            delegate?.textInputViewDidEndEditing(self)
        }
        return didResignFirstResponder
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hasDeletedTextWithPendingLayoutSubviews = false
        layoutManager.layoutIfNeeded()
        layoutManager.layoutLineSelectionIfNeeded()
        layoutPageGuideIfNeeded()
        selectionOverlayController.updateLayout()
        // Defer selection notifications out of layout — hosts (SwiftUI) writing state
        // from these callbacks during AppKit layout abort with Update Constraints in Window.
        let shouldNotifyInputDelegate = notifyInputDelegateAboutSelectionChangeInLayoutSubviews
        let shouldNotifyDelegate = notifyDelegateAboutSelectionChangeInLayoutSubviews
        notifyInputDelegateAboutSelectionChangeInLayoutSubviews = false
        notifyDelegateAboutSelectionChangeInLayoutSubviews = false
        if shouldNotifyInputDelegate || shouldNotifyDelegate {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if shouldNotifyInputDelegate {
                    self.inputDelegate?.selectionWillChange(self)
                    self.inputDelegate?.selectionDidChange(self)
                }
                if shouldNotifyDelegate {
                    self.delegate?.textInputViewDidChangeSelection(self)
                }
            }
        }
    }

    @objc func copy(_ sender: Any?) {
        if multiSelectionController.hasMultipleSelections {
            UIPasteboard.general.string = joinedMultiSelectionText()
        } else if let selectedTextRange = selectedTextRange, let text = text(in: selectedTextRange) {
            UIPasteboard.general.string = text
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let string = UIPasteboard.general.string else {
            return
        }
        if multiSelectionController.hasMultipleSelections {
            let selections = multiSelectionController.selections
            let clipboardLines = string.components(separatedBy: lineEndings.symbol)
            if clipboardLines.count == selections.count {
                // Clipboard has exactly one line per caret — likely a block-copy. Distribute one
                // line per caret in top-to-bottom order rather than pasting the whole clipboard
                // at every site, so block-copy -> block-paste round-trips.
                insertDistributedTextAtAllSelections(clipboardLines)
            } else {
                insertTextAtAllSelections(prepareTextForInsertion(string))
            }
            return
        }
        if let selectedTextRange = selectedTextRange {
            inputDelegate?.selectionWillChange(self)
            let preparedText = prepareTextForInsertion(string)
            replace(selectedTextRange, withText: preparedText)
            inputDelegate?.selectionDidChange(self)
        }
    }

    @objc func cut(_ sender: Any?) {
        if multiSelectionController.hasMultipleSelections {
            UIPasteboard.general.string = joinedMultiSelectionText()
            insertTextAtAllSelections("")
        } else if let selectedTextRange = selectedTextRange, let text = text(in: selectedTextRange) {
            UIPasteboard.general.string = text
            replace(selectedTextRange, withText: "")
        }
    }

    /// The text of every selected range, in top-to-bottom document order, joined by the
    /// document's line-ending symbol — used by multi-caret/block copy and cut.
    private func joinedMultiSelectionText() -> String {
        multiSelectionController.selections
            .sorted { $0.location < $1.location }
            .map { text(in: $0) ?? "" }
            .joined(separator: lineEndings.symbol)
    }

    @objc override func selectAll(_ sender: Any?) {
        notifyInputDelegateAboutSelectionChangeInLayoutSubviews = true
        selection = NSRange(location: 0, length: string.length)
    }

    /// When autocorrection is enabled and the user tap on a misspelled word, UITextInteraction will present
    /// a UIMenuController with suggestions for the correct spelling of the word. Selecting a suggestion will
    /// cause UITextInteraction to call the non-existing -replace(_:) function and pass an instance of the private
    /// UITextReplacement type as parameter. We can't make autocorrection work properly without using private API.
    @objc func replace(_ obj: NSObject) {
        if let replacementText = obj.value(forKey: "_repl" + "Ttnemeca".reversed() + "ext") as? String {
            if let indexedRange = obj.value(forKey: "_r" + "gna".reversed() + "e") as? IndexedRange {
                replace(indexedRange, withText: replacementText)
            }
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) {
            if let selectedTextRange = selectedTextRange {
                return !selectedTextRange.isEmpty
            } else {
                return false
            }
        } else if action == #selector(cut(_:)) {
            if let selectedTextRange = selectedTextRange {
                return isEditing && !selectedTextRange.isEmpty
            } else {
                return false
            }
        } else if action == #selector(paste(_:)) {
            return isEditing && UIPasteboard.general.hasStrings
        } else if action == #selector(selectAll(_:)) {
            return true
        } else if action == #selector(replace(_:)) {
            return true
        } else if action == NSSelectorFromString("replaceTextInSelectedHighlightedRange") {
            if let selection = selection, let highlightedRange = highlightedRange(for: selection) {
                return delegate?.textInputView(self, canReplaceTextIn: highlightedRange) ?? false
            } else {
                return false
            }
        } else {
            return super.canPerformAction(action, withSender: sender)
        }
    }

    func linePosition(at location: Int) -> LinePosition? {
        lineManager.linePosition(at: location)
    }

    var isSyntaxTreeReady: Bool {
        languageMode.isSyntaxTreeReady
    }

    func cancelSyntaxParse() {
        languageMode.cancelParse()
    }

    func setState(_ state: TextViewState, addUndoAction: Bool = false) {
        syntaxParseGeneration += 1
        let parseGeneration = syntaxParseGeneration
        syntaxParsePolicy = state.parsePolicy
        hasNotifiedSyntaxParse = false
        inFlightViewportParseRange = nil
        languageMode.cancelParse()
        if addUndoAction {
            let oldText = stringView.string
            let newText = state.stringView.string
            stringView = state.stringView
            theme = state.theme
            languageMode = state.languageMode
            lineControllerStorage.removeAllLineControllers()
            lineManager = state.lineManager
            lineManager.estimatedLineHeight = estimatedLineHeight
            layoutManager.languageMode = state.languageMode
            layoutManager.lineManager = state.lineManager
            contentSizeService.invalidateContentSize()
            gutterWidthService.invalidateLineNumberWidth()
            if newText != oldText {
                let newRange = NSRange(location: 0, length: newText.length)
                timedUndoManager.endUndoGrouping()
                timedUndoManager.beginUndoGrouping()
                addUndoOperation(replacing: newRange, withText: oldText as String)
                timedUndoManager.endUndoGrouping()
            }
        } else {
            stringView = state.stringView
            theme = state.theme
            languageMode = state.languageMode
            lineControllerStorage.removeAllLineControllers()
            lineManager = state.lineManager
            lineManager.estimatedLineHeight = estimatedLineHeight
            layoutManager.languageMode = state.languageMode
            layoutManager.lineManager = state.lineManager
            contentSizeService.invalidateContentSize()
            gutterWidthService.invalidateLineNumberWidth()
            timedUndoManager.removeAllActions()
        }
        if let oldSelectedRange = selection {
            inputDelegate?.selectionWillChange(self)
            selection = safeSelectionRange(from: oldSelectedRange)
            inputDelegate?.selectionDidChange(self)
        }
        if window != nil {
            performFullLayout()
        } else {
            hasPendingFullLayout = true
        }
        startDeferredParseIfNeeded(for: state, generation: parseGeneration)
    }

    func clearSelection() {
        selection = nil
    }

    func moveCaret(to point: CGPoint) {
        if let index = characterIndex(at: point) {
            selection = NSRange(location: index, length: 0)
        }
    }

    func characterIndex(at point: CGPoint) -> Int? {
        layoutManager.closestIndex(to: point)
    }

    func updateSelection(from anchor: Int, to index: Int) {
        let start = min(anchor, index)
        let end = max(anchor, index)
        inputDelegate?.selectionWillChange(self)
        selection = NSRange(location: start, length: end - start)
        inputDelegate?.selectionDidChange(self)
        // Host selection notify is deferred via `selection` setter.
    }

    func setLanguageMode(_ languageMode: LanguageMode, completion: ((Bool) -> Void)? = nil) {
        syntaxParseGeneration += 1
        let parseGeneration = syntaxParseGeneration
        self.languageMode.cancelParse()
        let internalLanguageMode = InternalLanguageModeFactory.internalLanguageMode(
            from: languageMode,
            stringView: stringView,
            lineManager: lineManager)
        self.languageMode = internalLanguageMode
        layoutManager.languageMode = internalLanguageMode
        internalLanguageMode.parse(string) { [weak self] finished in
            guard let self, parseGeneration == self.syntaxParseGeneration else {
                completion?(false)
                return
            }
            if finished {
                self.invalidateLines()
                self.layoutManager.setNeedsLayout()
                self.setNeedsLayout()
                self.delegate?.textInputViewDidFinishSyntaxParse(self)
            }
            completion?(finished)
        }
    }

    private func startDeferredParseIfNeeded(for state: TextViewState, generation: Int) {
        guard !state.isSyntaxTreeReady else {
            return
        }
        switch state.parsePolicy {
        case .eager:
            break
        case .deferred:
            startFullParse(of: string, generation: generation, state: state)
        case .viewport:
            startViewportParse(generation: generation, state: state, notifyOnCompletion: true)
        }
    }

    /// Full reparse of the current string (``string`` setter, ``setLanguageMode``). Invalidates the
    /// existing tree first so highlighting does not run against a stale AST while the new parse is
    /// in flight.
    private func startFullParse(of text: NSString) {
        guard languageMode is TreeSitterInternalLanguageMode else {
            return
        }
        syntaxParseGeneration += 1
        let generation = syntaxParseGeneration
        hasNotifiedSyntaxParse = false
        inFlightViewportParseRange = nil
        languageMode.invalidateSyntaxTree()
        if syntaxParsePolicy == .viewport {
            startViewportParse(generation: generation, state: nil, notifyOnCompletion: true)
        } else {
            startFullParse(of: text, generation: generation, state: nil)
        }
    }

    private func startFullParse(of text: NSString, generation: Int, state: TextViewState?) {
        languageMode.parse(text) { [weak self] finished in
            guard let self, generation == self.syntaxParseGeneration else {
                return
            }
            guard finished else {
                return
            }
            self.handleSyntaxParseFinished(state: state, notify: true)
        }
    }

    private func startViewportParse(generation: Int, state: TextViewState?, notifyOnCompletion: Bool) {
        guard let treeSitterMode = languageMode as? TreeSitterInternalLanguageMode else {
            return
        }
        let window = viewportUTF16Window()
        inFlightViewportParseRange = window
        treeSitterMode.parse(coveringUTF16Range: window) { [weak self] finished in
            guard let self, generation == self.syntaxParseGeneration else {
                return
            }
            self.inFlightViewportParseRange = nil
            guard finished else {
                return
            }
            let shouldNotify = notifyOnCompletion || !self.hasNotifiedSyntaxParse
            self.handleSyntaxParseFinished(state: state, notify: shouldNotify)
        }
    }

    /// Restart a deferred or viewport parse that `textDidChange` cancelled so the keystroke
    /// would not wait on `parseLock`. Incremental apply already ran if a tree existed.
    private func restartSyntaxParseAfterCancelledEdit() {
        guard !languageMode.isSyntaxTreeReady,
              languageMode is TreeSitterInternalLanguageMode else {
            return
        }
        syntaxParseGeneration += 1
        let generation = syntaxParseGeneration
        hasNotifiedSyntaxParse = false
        inFlightViewportParseRange = nil
        if syntaxParsePolicy == .viewport {
            startViewportParse(generation: generation, state: nil, notifyOnCompletion: true)
        } else {
            startFullParse(of: string, generation: generation, state: nil)
        }
    }

    /// Reparse the visible window when ``SyntaxParsePolicy/viewport`` is active and the current
    /// tree does not cover it. Called from the viewport setter, ``TextView`` layout, and after an
    /// in-flight parse finishes (so a scroll during that parse is not dropped).
    func ensureViewportSyntaxParse() {
        guard syntaxParsePolicy == .viewport,
              let treeSitterMode = languageMode as? TreeSitterInternalLanguageMode,
              treeSitterMode.isSyntaxTreeReady else {
            return
        }
        let visible = viewportUTF16Window(overscanScreens: 0)
        // An empty range at location 0 is contained by the leading window even when the
        // viewport has moved — only skip when we still have a real visible slice inside
        // the parsed range, or when we have not scrolled yet.
        if visible.length > 0, treeSitterMode.parsedRangeContains(visible) {
            return
        }
        if visible.length == 0, viewport.minY <= 0 {
            return
        }
        let window = viewportUTF16Window()
        if inFlightViewportParseRange == window {
            return
        }
        startViewportParse(generation: syntaxParseGeneration, state: nil, notifyOnCompletion: false)
    }

    private func viewportUTF16Window(
        overscanScreens: CGFloat = TreeSitterPerformanceConstants.viewportOverscanScreens
    ) -> NSRange {
        ViewportParseWindow.utf16Range(
            lineManager: lineManager,
            stringLength: string.length,
            viewport: viewport,
            overscanScreens: overscanScreens
        )
    }

    private func handleSyntaxParseFinished(state: TextViewState?, notify: Bool) {
        state?.applyDetectedIndentStrategy()
        invalidateLines()
        layoutManager.setNeedsLayout()
        setNeedsLayout()
        if notify {
            hasNotifiedSyntaxParse = true
            delegate?.textInputViewDidFinishSyntaxParse(self)
        }
        ensureViewportSyntaxParse()
    }

    func syntaxNode(at location: Int) -> SyntaxNode? {
        if let linePosition = lineManager.linePosition(at: location) {
            return languageMode.syntaxNode(at: linePosition)
        } else {
            return nil
        }
    }

    func isIndentation(at location: Int) -> Bool {
        guard let line = lineManager.line(containingCharacterAt: location) else {
            return false
        }
        let localLocation = location - line.location
        guard localLocation >= 0 else {
            return false
        }
        let indentLevel = languageMode.currentIndentLevel(of: line, using: indentStrategy)
        let indentString = indentStrategy.string(indentLevel: indentLevel)
        return localLocation <= indentString.utf16.count
    }

    func detectIndentStrategy() -> DetectedIndentStrategy {
        languageMode.detectIndentStrategy()
    }

    func textPreview(containing range: NSRange) -> TextPreview? {
        layoutManager.textPreview(containing: range)
    }

    func prepareLineForDisplay(atLocation location: Int) {
        layoutManager.prepareLineForDisplay(atLocation: location)
    }

    func lineAnchorY(at location: Int) -> CGFloat? {
        layoutManager.lineAnchorY(at: location)
    }

    func redisplayVisibleLines() {
        layoutManager.redisplayVisibleLines()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if hasPendingFullLayout && window != nil {
            hasPendingFullLayout = false
            performFullLayout()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        if result === self {
            timedUndoManager.endUndoGrouping()
        }
        return result
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            invalidateLines()
            layoutManager.setNeedsLayout()
        }
    }

    /// CoreText resolves a syntax-highlight token's `NSColor` to `CGColor` at typeset time
    /// (`LineTypesetter`), so a dynamic (appearance-adaptive) theme color is frozen against
    /// whatever the effective appearance was when a line was last typeset — typically off the
    /// main thread, well before any `draw(_:)` call. `traitCollectionDidChange` above is meant to
    /// catch this but never fires on macOS (`UITraitCollection.hasDifferentColorAppearance` is a
    /// UIKit-compat stub that always returns `false` here), so hook the real AppKit callback:
    /// force every line to re-typeset whenever the effective appearance actually changes,
    /// including when a caller forces one via `NSView.appearance` independent of the system
    /// setting.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateLines()
        layoutManager.setNeedsLayout()
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        if let keyCode = presses.first?.key?.keyCode, presses.count == 1 {
            if imeMarkedRange != nil {
                handleKeyPressDuringMultistageTextInput(keyCode: keyCode)
            }
        }
    }
}

// MARK: - Theming
private extension TextInputView {
    private func applyThemeToChildren() {
        gutterWidthService.font = theme.lineNumberFont
        lineManager.estimatedLineHeight = estimatedLineHeight
        indentController.indentFont = theme.font
        pageGuideController.font = theme.font
        pageGuideController.guideView.hairlineWidth = theme.pageGuideHairlineWidth
        pageGuideController.guideView.hairlineColor = theme.pageGuideHairlineColor
        pageGuideController.guideView.backgroundColor = theme.pageGuideBackgroundColor
        pageGuideController.guideView.shadingColor = theme.pageGuideBackgroundColor.withAlphaComponent(0.35)
        selectionHighlightColor = theme.selectionColor
        layoutManager.theme = theme
    }
}

// MARK: - Navigation
private extension TextInputView {
    private func handleKeyPressDuringMultistageTextInput(keyCode: UIKeyboardHIDUsage) {
        // When editing multistage text input (that is, we have a marked text) we let the user unmark the text
        // by pressing the arrow keys or Escape. This isn't common in iOS apps but it's the default behavior
        // on macOS and I think that works quite well for plain text editors on iOS too.
        guard let imeMarkedRange = imeMarkedRange, let markedText = stringView.substring(in: imeMarkedRange) else {
            return
        }
        // We only unmark the text if the marked text contains specific characters only.
        // Some languages use multistage text input extensively and for those iOS presents a UI when
        // navigating with the arrow keys. We do not want to interfere with that interaction.
        let characterSet = CharacterSet(charactersIn: "`´^¨")
        guard markedText.rangeOfCharacter(from: characterSet.inverted) == nil else {
            return
        }
        switch keyCode {
        case .keyboardUpArrow:
            navigate(in: .up, offset: 1)
            unmarkText()
        case .keyboardRightArrow:
            navigate(in: .right, offset: 1)
            unmarkText()
        case .keyboardDownArrow:
            navigate(in: .down, offset: 1)
            unmarkText()
        case .keyboardLeftArrow:
            navigate(in: .left, offset: 1)
            unmarkText()
        case .keyboardEscape:
            unmarkText()
        default:
            break
        }
    }

    private func navigate(in direction: UITextLayoutDirection, offset: Int) {
        if let selection = selection {
            if let location = lineMovementController.location(from: selection.location, in: direction, offset: offset) {
                self.selection = NSRange(location: location, length: 0)
            }
        }
    }
}

// MARK: - Layout
private extension TextInputView {
    private func layoutPageGuideIfNeeded() {
        if showPageGuide {
            // The width extension is used to make the page guide look "attached" to the right hand side, even when the scroll view bouncing on the right side.
            let maxContentOffsetX = contentSizeService.contentWidth - viewport.width
            let widthExtension = max(ceil(viewport.minX - maxContentOffsetX), 0)
            let xPosition = gutterWidthService.gutterWidth + textContainerInset.left + pageGuideController.columnOffset
            let width = max(bounds.width - xPosition + widthExtension, 0)
            let orrigin = CGPoint(x: xPosition, y: viewport.minY)
            let pageGuideSize = CGSize(width: width, height: viewport.height)
            pageGuideController.guideView.frame = CGRect(origin: orrigin, size: pageGuideSize)
        }
    }

    private func performFullLayout() {
        invalidateLines()
        layoutManager.setNeedsLayout()
        setNeedsLayout()
    }

    private func invalidateLines() {
        for lineController in lineControllerStorage {
            lineController.lineFragmentHeightMultiplier = lineHeightMultiplier
            lineController.tabWidth = indentController.tabWidth
            lineController.kern = kern
            lineController.lineBreakMode = lineBreakMode
            lineController.invalidateSyntaxHighlighting()
        }
    }

    private func setupContentSizeObserver() {
        contentSizeService.$isContentSizeInvalid.filter { $0 }.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textInputViewDidInvalidateContentSize(self)
            }
        }.store(in: &cancellables)
    }

    private func setupGutterWidthObserver() {
        gutterWidthService.didUpdateGutterWidth.sink { [weak self] in
            guard let self else { return }
            // Gutter width is often published while layoutGutter() reads lineNumberWidth.
            // Defer invalidation so we do not setNeedsLayout / invalidateLines mid-pass.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setNeedsLayout()
                self.invalidateLines()
                self.layoutManager.setNeedsLayout()
                self.delegate?.textInputViewDidChangeGutterWidth(self)
            }
        }.store(in: &cancellables)
    }

    private func setupFoldingObserver() {
        foldingController.didChangeFolds.sink { [weak self] in
            self?.adjustSelectionForFoldingIfNeeded()
        }.store(in: &cancellables)
    }

    private func sanitizedSelection(_ range: NSRange?) -> NSRange? {
        guard let range, foldingController.isEnabled else {
            return range
        }
        return foldingController.adjustedSelection(range)
    }

    private func adjustSelectionForFoldingIfNeeded() {
        if multiSelectionController.hasMultipleSelections {
            let adjustedSelections = multiSelectionController.selections.map { foldingController.adjustedSelection($0) }
            if adjustedSelections != multiSelectionController.selections {
                applySelectedRanges(adjustedSelections, notifyDelegate: false)
            }
            return
        }
        guard let currentSelection = _selectedRange else {
            return
        }
        let adjustedSelection = foldingController.adjustedSelection(currentSelection)
        guard adjustedSelection != currentSelection else {
            return
        }
        selection = adjustedSelection
    }
}

// MARK: - Multi Selection
extension TextInputView {
    func applySelectedRanges(_ ranges: [NSRange], primaryIndex: Int = 0, notifyDelegate: Bool = true) {
        let sanitized = ranges.compactMap { sanitizedSelection($0) }
        let normalized = MultiSelectionController.normalize(sanitized)
        isApplyingMultipleSelectionUpdate = true
        multiSelectionController.setSelections(normalized, primaryIndex: primaryIndex)
        let primary = multiSelectionController.primarySelection
        if primary != _selectedRange {
            // A nil primary (normalized to an empty set) legitimately clears the selection —
            // e.g. a block selection collapsing to nothing off the end of the document.
            _selectedRange = primary
        } else {
            layoutManager.selectedRange = _selectedRange
            layoutManager.setNeedsLayoutLineSelection()
            selectionOverlayController.selectionDidChange()
            setNeedsLayout()
        }
        isApplyingMultipleSelectionUpdate = false
        updateFocusModeIfNeeded()
        if notifyDelegate {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textInputViewDidChangeSelection(self)
            }
        }
    }

    /// Recomputes Focus Mode's focused ranges for the current selection set and redraws only if
    /// they actually changed — a caret move that stays within the same sentence/paragraph costs
    /// nothing beyond the resolver call.
    private func updateFocusModeIfNeeded() {
        guard focusModeController.updateFocusedRanges(for: selectedRanges) else {
            return
        }
        layoutManager.setNeedsLayout()
        setNeedsLayout()
    }

    func collapseMultiSelectionToPrimary() {
        guard multiSelectionController.hasMultipleSelections else {
            return
        }
        if let primary = multiSelectionController.primarySelection {
            applySelectedRanges([primary])
        }
    }

    /// Snapshots the current selection state into caret-set history before an additive multi-caret
    /// mutation, so ⌘U / `undoLastCaretChange()` can step back to it. Seeds the multi-selection
    /// controller with the current primary selection first when it isn't tracking anything yet, so
    /// the snapshot reflects the real pre-mutation state (one range) rather than an empty array.
    private func pushCaretHistory() {
        if multiSelectionController.selections.isEmpty, let primary = selection {
            multiSelectionController.setSelections([primary])
        }
        multiSelectionController.pushHistory()
    }

    func addSelection(at location: Int) {
        let range = sanitizedSelection(NSRange(location: location, length: 0)) ?? NSRange(location: location, length: 0)
        pushCaretHistory()
        guard multiSelectionController.addSelection(range) else {
            return
        }
        applySelectedRanges(multiSelectionController.selections, primaryIndex: multiSelectionController.primaryIndex)
    }

    func addSelectionsOnEachLine() {
        guard let currentSelection = selection, currentSelection.length > 0 else {
            return
        }
        guard let (startLine, endLine) = lineManager.startAndEndLine(in: currentSelection) else {
            return
        }
        var ranges: [NSRange] = []
        for row in startLine.index...endLine.index {
            let line = lineManager.line(atRow: row)
            ranges.append(NSRange(location: line.location, length: 0))
        }
        pushCaretHistory()
        applySelectedRanges(ranges)
    }

    func selectNextOccurrence() {
        let string = stringView.string
        if selection?.length == 0,
           let wordRange = SelectNextOccurrence.wordRange(at: selection?.location ?? 0, in: string, tokenizer: tokenizer) {
            pushCaretHistory()
            applySelectedRanges([wordRange])
            return
        }
        guard let queryRange = selection, queryRange.length > 0,
              let query = text(in: queryRange), !query.isEmpty else {
            return
        }
        var ranges = selectedRanges.filter { $0.length == queryRange.length }
        if ranges.isEmpty {
            ranges = [queryRange]
        }
        let searchStart = ranges.map(\.upperBound).max() ?? queryRange.upperBound
        guard let next = SelectNextOccurrence.nextMatch(for: query,
                                                          length: queryRange.length,
                                                          in: string,
                                                          after: searchStart) else {
            return
        }
        guard !ranges.contains(where: { $0.location == next.location }) else {
            return
        }
        ranges.append(next)
        pushCaretHistory()
        applySelectedRanges(ranges)
    }

    /// Replaces the most recently added occurrence range (the one with the highest `location`,
    /// since `selectNextOccurrence()` always searches forward from the maximum upper bound) with
    /// the next match after it, rather than appending — lets you skip a match you don't want to
    /// rename without losing the ones already selected. No-op with fewer than two ranges.
    func skipCurrentOccurrence() {
        let string = stringView.string
        var ranges = selectedRanges
        guard ranges.count > 1, let mostRecent = ranges.max(by: { $0.location < $1.location }) else {
            return
        }
        let query = text(in: mostRecent) ?? ""
        guard !query.isEmpty else {
            return
        }
        let searchStart = mostRecent.upperBound
        guard let next = SelectNextOccurrence.nextMatch(for: query,
                                                          length: mostRecent.length,
                                                          in: string,
                                                          after: searchStart),
              !ranges.contains(where: { $0.location == next.location }) else {
            return
        }
        ranges.removeAll { $0.location == mostRecent.location && $0.length == mostRecent.length }
        ranges.append(next)
        pushCaretHistory()
        applySelectedRanges(ranges)
    }

    /// Selects every occurrence of the current query in the document. If the selection is empty,
    /// the word under the caret becomes the query first (matching `selectNextOccurrence()`).
    func selectAllOccurrences() {
        let string = stringView.string
        let queryRange: NSRange?
        if let selection, selection.length > 0 {
            queryRange = selection
        } else {
            queryRange = SelectNextOccurrence.wordRange(at: selection?.location ?? 0, in: string, tokenizer: tokenizer)
        }
        guard let queryRange, let query = text(in: queryRange), !query.isEmpty else {
            return
        }
        let matches = SelectNextOccurrence.allMatches(for: query, in: string)
        guard !matches.isEmpty else {
            return
        }
        pushCaretHistory()
        applySelectedRanges(matches)
    }

    /// Adds a new caret one visual line above the topmost caret (`.up`) or below the bottommost
    /// caret (`.down`), reusing the same fragment-local vertical movement plain arrow keys use.
    /// No-op at a document edge, where movement can't advance past the existing caret.
    private func addCaret(in direction: UITextLayoutDirection) {
        let carets = selectedRanges.filter { $0.length == 0 }
        guard let source = direction == .up
            ? carets.min(by: { $0.location < $1.location })
            : carets.max(by: { $0.location < $1.location }) else {
            return
        }
        guard let newLocation = lineMovementController.location(from: source.location, in: direction, offset: 1),
              newLocation != source.location else {
            return
        }
        // addSelection(at:) pushes its own caret-history snapshot before mutating.
        addSelection(at: newLocation)
    }

    func addCaretAbove() {
        addCaret(in: .up)
    }

    func addCaretBelow() {
        addCaret(in: .down)
    }

    func undoLastCaretChange() {
        guard multiSelectionController.undoLastCaretChange() else {
            return
        }
        applySelectedRanges(multiSelectionController.selections, primaryIndex: multiSelectionController.primaryIndex)
    }

    /// Replaces, at every selection, the range beginning `relativeStartOffset` UTF-16 units from
    /// that selection's own start and extending `length` units — the same relative edit applied
    /// identically at every caret. Used by EditorIntelligence completion acceptance to apply a
    /// completion at every multi-cursor site once its replacement range relative to the primary
    /// caret is known. No-op when only one selection is active.
    func replaceAtAllSelections(relativeStartOffset: Int, length: Int, with text: String) {
        guard multiSelectionController.hasMultipleSelections else {
            return
        }
        let documentLength = stringView.length
        let editRanges = multiSelectionController.selections.map { selection -> NSRange in
            let location = min(max(selection.location + relativeStartOffset, 0), documentLength)
            let clampedLength = min(max(length, 0), documentLength - location)
            return NSRange(location: location, length: clampedLength)
        }
        insertTextAtAllSelections(text, at: editRanges)
    }

    func moveAllSelections(in direction: UITextLayoutDirection) {
        var newSelections: [NSRange] = []
        for range in selectedRanges {
            if range.length > 0 {
                newSelections.append(range)
                continue
            }
            guard let newLocation = lineMovementController.location(from: range.location, in: direction, offset: 1) else {
                newSelections.append(range)
                continue
            }
            newSelections.append(NSRange(location: newLocation, length: 0))
        }
        applySelectedRanges(MultiSelectionController.normalize(newSelections))
        if let primary = selection {
            selectionAnchor = primary.length == 0 ? primary.location : primary.upperBound
        }
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }
}

// MARK: - Block Selection
extension TextInputView {
    func beginBlockSelection(at point: CGPoint) {
        let row = layoutManager.lineIndex(forYPosition: point.y)
        blockSelectionController.begin(at: BlockSelectionAnchor(lineIndex: row, xPosition: point.x))
        applyMaterializedBlockSelection()
    }

    func extendBlockSelection(to point: CGPoint) {
        guard blockSelectionController.isActive else {
            beginBlockSelection(at: point)
            return
        }
        let row = layoutManager.lineIndex(forYPosition: point.y)
        blockSelectionController.extend(to: BlockSelectionAnchor(lineIndex: row, xPosition: point.x))
        applyMaterializedBlockSelection()
    }

    func endBlockSelection() {
        blockSelectionController.end()
    }

    /// Starts a block selection anchored at the current primary caret, if one isn't already
    /// active. Shared by keyboard block-extension (⌃⇧←/→/↑/↓) and Option+Shift-drag, both of
    /// which need to *extend* a block from wherever editing already is rather than requiring an
    /// existing block to already be in progress.
    func beginBlockSelectionAtCurrentCaretIfNeeded() {
        guard !blockSelectionController.isActive else {
            return
        }
        let origin = selection?.location ?? 0
        guard let line = lineManager.line(containingCharacterAt: origin) else {
            return
        }
        let originX = caretRectService.caretRect(at: origin, allowMovingCaretToNextLineFragment: true).minX
        blockSelectionController.begin(at: BlockSelectionAnchor(lineIndex: line.index, xPosition: originX))
    }

    /// Grows or shrinks the active block selection by one row/character via the keyboard
    /// (⌃⇧←/→/↑/↓). Starts a block at the current primary caret if one isn't already active.
    func extendBlockSelection(in direction: UITextLayoutDirection) {
        beginBlockSelectionAtCurrentCaretIfNeeded()
        guard let active = blockSelectionController.active else {
            return
        }
        var newRow = active.lineIndex
        var newX = active.xPosition
        switch direction {
        case .up:
            newRow = max(active.lineIndex - 1, 0)
        case .down:
            newRow = min(active.lineIndex + 1, max(lineManager.lineCount - 1, 0))
        case .left, .right:
            let currentIndex = layoutManager.closestIndex(toXPosition: newX, inLineAtRow: active.lineIndex)
            let newIndex = lineMovementController.location(from: currentIndex, in: direction, offset: 1) ?? currentIndex
            newX = caretRectService.caretRect(at: newIndex, allowMovingCaretToNextLineFragment: true).minX
        @unknown default:
            break
        }
        blockSelectionController.extend(to: BlockSelectionAnchor(lineIndex: newRow, xPosition: newX))
        applyMaterializedBlockSelection()
    }

    private func applyMaterializedBlockSelection() {
        let ranges = blockSelectionController.materializedRanges(lineCount: lineManager.lineCount) { [layoutManager] row, x in
            layoutManager.closestIndex(toXPosition: x, inLineAtRow: row)
        }
        guard !ranges.isEmpty else {
            return
        }
        isApplyingBlockSelectionUpdate = true
        applySelectedRanges(ranges)
        isApplyingBlockSelectionUpdate = false
    }
}

// MARK: - Floating Caret
extension TextInputView {
    func beginFloatingCursor(at point: CGPoint) {
        if floatingCaretView == nil, let position = closestPosition(to: point) {
            insertionPointColorBeforeFloatingBegan = insertionPointColor
            selectionOverlayController.isEnabled = false
            let caretRect = self.caretRect(for: position)
            let caretOrigin = CGPoint(x: point.x - caretRect.width / 2, y: point.y - caretRect.height / 2)
            let floatingCaretView = FloatingCaretView()
            floatingCaretView.backgroundColor = insertionPointColorBeforeFloatingBegan
            floatingCaretView.frame = CGRect(origin: caretOrigin, size: caretRect.size)
            addSubview(floatingCaretView)
            self.floatingCaretView = floatingCaretView
            delegate?.textInputViewDidBeginFloatingCursor(self)
        }
    }

    func updateFloatingCursor(at point: CGPoint) {
        if let floatingCaretView = floatingCaretView {
            let caretSize = floatingCaretView.frame.size
            let caretOrigin = CGPoint(x: point.x - caretSize.width / 2, y: point.y - caretSize.height / 2)
            floatingCaretView.frame = CGRect(origin: caretOrigin, size: caretSize)
        }
    }

    func endFloatingCursor() {
        if isEditing {
            selectionOverlayController.isEnabled = true
            selectionOverlayController.updateLayout()
        }
        floatingCaretView?.removeFromSuperview()
        floatingCaretView = nil
        delegate?.textInputViewDidEndFloatingCursor(self)
    }
}

// MARK: - Rects
extension TextInputView {
    func caretRect(for position: UITextPosition) -> CGRect {
        guard let indexedPosition = position as? IndexedPosition else {
            fatalError("Expected position to be of type \(IndexedPosition.self)")
        }
        return caretRectService.caretRect(at: indexedPosition.index, allowMovingCaretToNextLineFragment: true)
    }

    func caretRect(at location: Int) -> CGRect {
        caretRectService.caretRect(at: location, allowMovingCaretToNextLineFragment: true)
    }

    func firstRect(for range: UITextRange) -> CGRect {
        guard let indexedRange = range as? IndexedRange else {
            fatalError("Expected range to be of type \(IndexedRange.self)")
        }
        return layoutManager.firstRect(for: indexedRange.range)
    }
}

// MARK: - Editing
extension TextInputView {
    func insertText(_ text: String) {
        let preparedText = prepareTextForInsertion(text)
        isRestoringPreviouslyDeletedText = hasDeletedTextWithPendingLayoutSubviews
        hasDeletedTextWithPendingLayoutSubviews = false
        defer {
            isRestoringPreviouslyDeletedText = false
        }
        if multiSelectionController.hasMultipleSelections {
            if LineEnding(symbol: text) != nil {
                insertLineBreakAtAllSelections()
            } else {
                insertTextAtAllSelections(preparedText)
            }
            return
        }
        // If there is no marked range or selected range then we fallback to appending text to the end of our string.
        let replacementRange = imeMarkedRange ?? selection ?? NSRange(location: stringView.length, length: 0)
        guard shouldChangeText(in: replacementRange, replacementText: preparedText) else {
            isRestoringPreviouslyDeletedText = false
            return
        }
        // If we're inserting text then we can't have a marked range. However, UITextInput doesn't always clear the marked range
        // before calling -insertText(_:), so we do it manually. This issue can be tested by entering a backtick (`) in an empty
        // document, then pressing any arrow key (up, right, down or left) followed by the return key.
        // The backtick will remain marked unless we manually clear the marked range.
        imeMarkedRange = nil
        if LineEnding(symbol: text) != nil {
            indentController.insertLineBreak(in: replacementRange, using: lineEndings)
            setNeedsLayout()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textInputViewDidChangeSelection(self)
            }
        } else {
            replaceText(in: replacementRange, with: preparedText)
            setNeedsLayout()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textInputViewDidChangeSelection(self)
            }
        }
    }

    func deleteBackward() {
        didCallDeleteBackward = true
        if multiSelectionController.hasMultipleSelections {
            deleteBackwardAtAllSelections()
            return
        }
        guard let currentSelection = imeMarkedRange ?? selection else {
            return
        }
        let deleteSelection: NSRange
        if currentSelection.length == 0 {
            guard currentSelection.location > 0 else {
                return
            }
            let characterRange = string.customRangeOfComposedCharacterSequence(at: currentSelection.location - 1)
            deleteSelection = NSRange(location: characterRange.location, length: currentSelection.location - characterRange.location)
        } else {
            deleteSelection = currentSelection
        }
        let deleteRange = rangeForDeletingText(in: deleteSelection)
        // If we're deleting everything in the marked range then we clear the marked range. UITextInput doesn't do that for us.
        // Can be tested by entering a backtick (`) in an empty document and deleting it.
        if deleteRange == imeMarkedRange {
            imeMarkedRange = nil
        }
        guard shouldChangeText(in: deleteRange, replacementText: "") else {
            return
        }
        // Set a flag indicating that we have deleted text. This is reset in -layoutSubviews() but if this has not been reset before insertText() is called, then UIKit deleted characters prior to inserting combined characters. This happens when UIKit turns Korean characters into a single character. E.g. when typing ㅇ followed by ㅓ UIKit will perform the following operations:
        // 1. Delete ㅇ.
        // 2. Delete the character before ㅇ. I'm unsure why this is needed.
        // 3. Insert the character that was previously before ㅇ.
        // 4. Insert the ㅇ and ㅓ but combined into the single character delete ㅇ and then insert 어.
        // We can detect this case in insertText() by checking if this variable is true.
        hasDeletedTextWithPendingLayoutSubviews = true
        // Disable notifying delegate in layout subviews to prevent sending the selected range with length > 0 when deleting text. This aligns with the behavior of UITextView and was introduced to resolve issue #158: https://github.com/simonbs/Runestone/issues/158
        notifyDelegateAboutSelectionChangeInLayoutSubviews = false
        // Disable notifying input delegate in layout subviews to prevent issues when entering Korean text. This workaround is inspired by a dialog with Alexander Black (@lextar), developer of Textastic.
        notifyInputDelegateAboutSelectionChangeInLayoutSubviews = false
        // Just before calling deleteBackward(), UIKit will set the selected range to a range of length 1, if the selected range has a length of 0.
        // In that case we want to undo to a selected range of length 0, so we construct our range here and pass it all the way to the undo operation.
        let selectedRangeAfterUndo: NSRange
        if deleteRange.length == 1 {
            selectedRangeAfterUndo = NSRange(location: deleteSelection.upperBound, length: 0)
        } else {
            selectedRangeAfterUndo = deleteSelection
        }
        let isDeletingMultipleCharacters = deleteSelection.length > 1
        if isDeletingMultipleCharacters {
            timedUndoManager.endUndoGrouping()
            timedUndoManager.beginUndoGrouping()
        }
        replaceText(in: deleteRange, with: "", selectedRangeAfterUndo: selectedRangeAfterUndo)
        // Sending selection changed without calling the input delegate directly. This ensures that both inputting Korean letters and deleting entire words with Option+Backspace works properly.
        sendSelectionChangedToTextSelectionView()
        if isDeletingMultipleCharacters {
            timedUndoManager.endUndoGrouping()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.textInputViewDidChangeSelection(self)
        }
    }

    func deleteForward() {
        if multiSelectionController.hasMultipleSelections {
            deleteForwardAtAllSelections()
            return
        }
        guard let currentSelection = imeMarkedRange ?? selection else {
            return
        }
        let range: NSRange
        if currentSelection.length == 0 {
            guard currentSelection.location < string.length else {
                return
            }
            range = string.customRangeOfComposedCharacterSequence(at: currentSelection.location)
        } else {
            range = currentSelection
        }
        replace(IndexedRange(range), withText: "")
    }

    func deleteWord(backward: Bool) {
        guard let currentRange = selection else {
            return
        }
        let position = IndexedPosition(index: backward ? currentRange.location : currentRange.upperBound)
        let direction: UITextDirection = backward ? .backward : .forward
        guard let boundary = tokenizer.position(from: position, toBoundary: .word, inDirection: direction) as? IndexedPosition else {
            return
        }
        let deleteRange: NSRange
        if backward {
            deleteRange = NSRange(location: boundary.index, length: currentRange.upperBound - boundary.index)
        } else {
            deleteRange = NSRange(location: currentRange.location, length: boundary.index - currentRange.location)
        }
        guard deleteRange.length > 0 else {
            return
        }
        selection = deleteRange
        deleteBackward()
    }

    func replace(_ range: UITextRange, withText text: String) {
        let preparedText = prepareTextForInsertion(text)
        if let indexedRange = range as? IndexedRange, shouldChangeText(in: indexedRange.range.nonNegativeLength, replacementText: preparedText) {
            replaceText(in: indexedRange.range.nonNegativeLength, with: preparedText)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.textInputViewDidChangeSelection(self)
            }
        }
    }

    func replaceText(in batchReplaceSet: BatchReplaceSet) {
        guard !batchReplaceSet.replacements.isEmpty else {
            return
        }
        var oldLinePosition: LinePosition?
        if let oldSelectedRange = selection {
            oldLinePosition = lineManager.linePosition(at: oldSelectedRange.location)
        }
        let textEditHelper = TextEditHelper(stringView: stringView, lineManager: lineManager, lineEndings: lineEndings)
        let application = textEditHelper.apply(batchReplaceSet)
        registerBatchUndo(inverseReplacements: application.inverseReplacements)
        invalidateLines()
        layoutManager.setNeedsLayout()
        setNeedsLayout()
        contentSizeService.invalidateContentSize()
        gutterWidthService.invalidateLineNumberWidth()
        delegate?.textInputViewDidChange(self)
        if let oldLinePosition = oldLinePosition {
            // By restoring the selected range using the old line position we can better preserve the old selected language.
            moveCaret(to: oldLinePosition)
        }
    }

    func text(in range: UITextRange) -> String? {
        if let indexedRange = range as? IndexedRange {
            return text(in: indexedRange.range.nonNegativeLength)
        } else {
            return nil
        }
    }

    func text(in range: NSRange) -> String? {
        stringView.substring(in: range)
    }

    /// `inverseReplacements` is a delta list (range + old text, sized to what was edited) rather
    /// than a full-document snapshot — undoing replays it through `replaceText(in:)`, which
    /// computes its own inverse in turn, so redo/undo/redo... never holds more than one edit's
    /// worth of text per step, regardless of document size. See PERFORMANCE_AUDIT.md Phase 2 #7.
    private func registerBatchUndo(inverseReplacements: [BatchReplaceSet.Replacement]) {
        let isNestedInUndoOrRedo = timedUndoManager.isUndoing || timedUndoManager.isRedoing
        if !isNestedInUndoOrRedo {
            timedUndoManager.endUndoGrouping()
            timedUndoManager.beginUndoGrouping()
            timedUndoManager.setActionName(L10n.Undo.ActionName.replaceAll)
        }
        timedUndoManager.registerUndo(withTarget: self) { textInputView in
            textInputView.replaceText(in: BatchReplaceSet(replacements: inverseReplacements))
        }
        if !isNestedInUndoOrRedo {
            timedUndoManager.endUndoGrouping()
        }
    }

    private func setStringWithUndoAction(_ newString: NSString, inverseReplacements: [BatchReplaceSet.Replacement]) {
        guard newString != string else {
            return
        }
        // When this runs as the body of an undo/redo invocation (i.e. `registerUndo`'s closure,
        // below, calling back into this method), `UndoManager` already has its own implicit group
        // open around the invocation, to collect whatever `registerUndo` call happens inside it as
        // the opposite-direction action. Unconditionally closing/reopening a group here — as this
        // method used to, pre-existing bug independent of the delta-vs-snapshot change above —
        // ends that implicit group early; when the manager tries to finalize it after this method
        // returns, its bookkeeping is already inconsistent and it raises
        // "endUndoGrouping called with no matching begin". Only manage grouping explicitly for a
        // top-level (non-nested) call; a nested call relies on the manager's own grouping.
        let isNestedInUndoOrRedo = timedUndoManager.isUndoing || timedUndoManager.isRedoing
        if !isNestedInUndoOrRedo {
            timedUndoManager.endUndoGrouping()
        }
        let oldSelectedRange = selection
        preserveUndoStackWhenSettingString = true
        string = newString
        preserveUndoStackWhenSettingString = false
        if !isNestedInUndoOrRedo {
            timedUndoManager.beginUndoGrouping()
            timedUndoManager.setActionName(L10n.Undo.ActionName.replaceAll)
        }
        timedUndoManager.registerUndo(withTarget: self) { textInputView in
            textInputView.replaceText(in: BatchReplaceSet(replacements: inverseReplacements))
        }
        if !isNestedInUndoOrRedo {
            timedUndoManager.endUndoGrouping()
        }
        delegate?.textInputViewDidChange(self)
        if let oldSelectedRange = oldSelectedRange {
            selection = safeSelectionRange(from: oldSelectedRange)
        }
    }

    private func rangeForDeletingText(in range: NSRange) -> NSRange {
        var resultingRange = range
        if range.length == 1, let indentRange = indentController.indentRangeInFrontOfLocation(range.upperBound) {
            resultingRange = indentRange
        } else {
            resultingRange = string.customRangeOfComposedCharacterSequences(for: range)
        }
        // If deleting the leading component of a character pair we may also expand the range to delete the trailing component.
        if characterPairTrailingComponentDeletionMode == .immediatelyFollowingLeadingComponent
            && maximumLeadingCharacterPairComponentLength > 0
            && resultingRange.length <= maximumLeadingCharacterPairComponentLength {
            let stringToDelete = stringView.substring(in: resultingRange)
            if let characterPair = characterPairs.first(where: { $0.leading == stringToDelete }) {
                let trailingComponentLength = characterPair.trailing.utf16.count
                let trailingComponentRange = NSRange(location: resultingRange.upperBound, length: trailingComponentLength)
                if stringView.substring(in: trailingComponentRange) == characterPair.trailing {
                    let deleteRange = trailingComponentRange.upperBound - resultingRange.lowerBound
                    resultingRange = NSRange(location: resultingRange.lowerBound, length: deleteRange)
                }
            }
        }
        return resultingRange
    }

    private func replaceText(in range: NSRange,
                             with newString: String,
                             selectedRangeAfterUndo: NSRange? = nil,
                             selectedRangesAfterUndo: [NSRange]? = nil,
                             primaryIndexAfterUndo: Int = 0,
                             undoActionName: String = L10n.Undo.ActionName.typing,
                             updateSelection: Bool = true) {
        let nsNewString = newString as NSString
        let currentText = text(in: range) ?? ""
        let newRange = NSRange(location: range.location, length: nsNewString.length)
        multiSelectionController.clearHistory()
        addUndoOperation(replacing: newRange,
                         withText: currentText,
                         selectedRangeAfterUndo: selectedRangeAfterUndo,
                         selectedRangesAfterUndo: selectedRangesAfterUndo,
                         primaryIndexAfterUndo: primaryIndexAfterUndo,
                         actionName: undoActionName)
        if updateSelection {
            _selectedRange = NSRange(location: newRange.upperBound, length: 0)
            if !isApplyingMultipleSelectionUpdate {
                multiSelectionController.setSelections(_selectedRange.map { [$0] } ?? [])
            }
        }
        let textEditHelper = TextEditHelper(stringView: stringView, lineManager: lineManager, lineEndings: lineEndings)
        let textEditResult = textEditHelper.replaceText(in: range, with: newString)
        let textChange = textEditResult.textChange
        let lineChangeSet = textEditResult.lineChangeSet
        let languageModeLineChangeSet = languageMode.textDidChange(textChange)
        lineChangeSet.union(with: languageModeLineChangeSet)
        applyLineChangesToLayoutManager(lineChangeSet)
        restartSyntaxParseAfterCancelledEdit()
        let updatedTextEditResult = TextEditResult(textChange: textChange, lineChangeSet: lineChangeSet)
        let change = TextContentChange(
            range: range,
            replacementText: newString,
            start: TextLocation(textChange.startLinePosition),
            oldEnd: TextLocation(textChange.oldEndLinePosition)
        )
        delegate?.textInputView(self, didChangeContent: change)
        delegate?.textInputViewDidChange(self)
        if updatedTextEditResult.didAddOrRemoveLines {
            delegate?.textInputViewDidInvalidateContentSize(self)
        }
    }

    private func applyLineChangesToLayoutManager(_ lineChangeSet: LineChangeSet) {
        let didAddOrRemoveLines = !lineChangeSet.insertedLines.isEmpty || !lineChangeSet.removedLines.isEmpty
        if didAddOrRemoveLines {
            contentSizeService.invalidateContentSize()
            for removedLine in lineChangeSet.removedLines {
                lineControllerStorage.removeLineController(withID: removedLine.id)
                contentSizeService.removeLine(withID: removedLine.id)
            }
        }
        let editedLineIDs = Set(lineChangeSet.editedLines.map(\.id))
        layoutManager.redisplayLines(withIDs: editedLineIDs)
        if didAddOrRemoveLines {
            gutterWidthService.invalidateLineNumberWidth()
        }
        if foldingController.foldProvider is TreeSitterLineFoldProvider {
            treeSitterFoldProvider.invalidate()
        }
        foldingController.setNeedsRecompute()
        layoutManager.setNeedsLayout()
        setNeedsLayout()
    }

    private func shouldChangeText(in range: NSRange, replacementText text: String) -> Bool {
        delegate?.textInputView(self, shouldChangeTextIn: range, replacementText: text) ?? true
    }

    private func addUndoOperation(replacing range: NSRange,
                                  withText text: String,
                                  selectedRangeAfterUndo: NSRange? = nil,
                                  selectedRangesAfterUndo: [NSRange]? = nil,
                                  primaryIndexAfterUndo: Int = 0,
                                  actionName: String = L10n.Undo.ActionName.typing) {
        let oldSelectedRange = selectedRangeAfterUndo ?? selection
        timedUndoManager.beginUndoGrouping()
        timedUndoManager.setActionName(actionName)
        timedUndoManager.registerUndo(withTarget: self) { textInputView in
            textInputView.inputDelegate?.selectionWillChange(textInputView)
            textInputView.replaceText(in: range, with: text)
            // A multi-range restore target (captured once, before a whole batch of edits) takes
            // priority over the single-range one: every edit within a multi-caret/block batch
            // registers its own undo step with the *same* pre-batch set, so however many of them
            // the grouped undo replays, the caret set that lands is that same full pre-batch set —
            // not just the primary caret, which is what a single `NSRange` restore would collapse to.
            if let selectedRangesAfterUndo, !selectedRangesAfterUndo.isEmpty {
                textInputView.applySelectedRanges(selectedRangesAfterUndo, primaryIndex: primaryIndexAfterUndo, notifyDelegate: false)
            } else {
                textInputView.selection = oldSelectedRange
            }
            textInputView.inputDelegate?.selectionDidChange(textInputView)
        }
    }

    private func prepareTextForInsertion(_ text: String) -> String {
        // Ensure all line endings match our preferred line endings.
        var preparedText = text
        let lineEndingsToReplace: [LineEnding] = [.crlf, .cr, .lf].filter { $0 != lineEndings }
        for lineEnding in lineEndingsToReplace {
            if #available(macOS 13.0, iOS 16.0, *) {
                preparedText = preparedText.replacing(lineEnding.symbol, with: lineEndings.symbol)
            } else {
                preparedText = preparedText.replacingOccurrences(of: lineEnding.symbol, with: lineEndings.symbol)
            }
        }
        return preparedText
    }

    /// Replaces `explicitRanges` (defaulting to the current selections) with `text` at every
    /// site, in one undo group. `explicitRanges`, when given, is purely which ranges get edited —
    /// undo still restores the real pre-edit *selections*, not those ranges, since a caller like
    /// `replaceAtAllSelections(relativeStartOffset:length:with:)` derives them from the selections
    /// rather than using the selections themselves as the edit ranges.
    func insertTextAtAllSelections(_ text: String, at explicitRanges: [NSRange]? = nil) {
        let originalSelections = multiSelectionController.selections
        let editRanges = (explicitRanges ?? originalSelections).sorted { $0.location > $1.location }
        guard !editRanges.isEmpty else {
            return
        }
        guard editRanges.allSatisfy({ shouldChangeText(in: $0, replacementText: text) }) else {
            return
        }
        imeMarkedRange = nil
        timedUndoManager.beginUndoGrouping()
        let primaryIndex = multiSelectionController.primaryIndex
        var newSelections: [NSRange] = []
        for range in editRanges {
            replaceText(in: range, with: text, selectedRangesAfterUndo: originalSelections, primaryIndexAfterUndo: primaryIndex, updateSelection: false)
            newSelections.append(NSRange(location: range.location + text.utf16.count, length: 0))
        }
        timedUndoManager.endUndoGrouping()
        applySelectedRanges(newSelections.sorted { $0.location < $1.location }, notifyDelegate: false)
        setNeedsLayout()
        delegate?.textInputViewDidChange(self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.textInputViewDidChangeSelection(self)
        }
    }

    /// Inserts a language-aware line break (indentation and all — the same as the single-caret
    /// path) at every selection. `IndentController` reports the resulting per-site caret through
    /// its `shouldSelect` delegate callback (or implicitly via `replaceText`'s own default when it
    /// doesn't fire one), which lands in `_selectedRange` after each call — read that back rather
    /// than letting each iteration's single-range assignment stand, since only the very last one
    /// would otherwise survive and every other caret would be lost.
    private func insertLineBreakAtAllSelections() {
        let selections = multiSelectionController.selections.sorted { $0.location > $1.location }
        guard !selections.isEmpty else {
            return
        }
        guard selections.allSatisfy({ shouldChangeText(in: $0, replacementText: lineEndings.symbol) }) else {
            return
        }
        imeMarkedRange = nil
        timedUndoManager.beginUndoGrouping()
        pendingMultiSelectionUndoRestore = (selections, multiSelectionController.primaryIndex)
        var newSelections: [NSRange] = []
        for selection in selections {
            indentController.insertLineBreak(in: selection, using: lineEndings)
            newSelections.append(_selectedRange ?? NSRange(location: selection.location, length: 0))
        }
        pendingMultiSelectionUndoRestore = nil
        timedUndoManager.endUndoGrouping()
        applySelectedRanges(newSelections.sorted { $0.location < $1.location }, notifyDelegate: false)
        setNeedsLayout()
        delegate?.textInputViewDidChange(self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.textInputViewDidChangeSelection(self)
        }
    }

    /// Pairs `lines[i]` with the i-th selection in ascending document order (top row gets the
    /// first line) and replaces each selection with its paired line — used for block-paste after
    /// a block-copy produced one line per caret, so distribution stays row-for-row rather than
    /// pasting the same text at every site.
    private func insertDistributedTextAtAllSelections(_ lines: [String]) {
        let ascendingSelections = multiSelectionController.selections.sorted { $0.location < $1.location }
        guard ascendingSelections.count == lines.count else {
            return
        }
        let pairs = zip(ascendingSelections, lines).sorted { $0.0.location > $1.0.location }
        guard pairs.allSatisfy({ shouldChangeText(in: $0.0, replacementText: $0.1) }) else {
            return
        }
        imeMarkedRange = nil
        timedUndoManager.beginUndoGrouping()
        let restoreRanges = multiSelectionController.selections
        let primaryIndex = multiSelectionController.primaryIndex
        var newSelections: [NSRange] = []
        for (selection, text) in pairs {
            replaceText(in: selection,
                       with: text,
                       selectedRangesAfterUndo: restoreRanges,
                       primaryIndexAfterUndo: primaryIndex,
                       updateSelection: false)
            newSelections.append(NSRange(location: selection.location + (text as NSString).length, length: 0))
        }
        timedUndoManager.endUndoGrouping()
        applySelectedRanges(newSelections.sorted { $0.location < $1.location }, notifyDelegate: false)
        setNeedsLayout()
        delegate?.textInputViewDidChange(self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.textInputViewDidChangeSelection(self)
        }
    }

    private func deleteBackwardAtAllSelections() {
        let selections = multiSelectionController.selections.sorted { $0.location > $1.location }
        var deleteOperations: [(deleteRange: NSRange, caretLocation: Int)] = []
        for selection in selections {
            if selection.length > 0 {
                deleteOperations.append((selection, selection.location))
                continue
            }
            guard selection.location > 0 else {
                continue
            }
            let characterRange = string.customRangeOfComposedCharacterSequence(at: selection.location - 1)
            let deleteRange = NSRange(location: characterRange.location, length: selection.location - characterRange.location)
            deleteOperations.append((deleteRange, deleteRange.location))
        }
        guard !deleteOperations.isEmpty else {
            return
        }
        guard deleteOperations.allSatisfy({ shouldChangeText(in: $0.deleteRange, replacementText: "") }) else {
            return
        }
        timedUndoManager.beginUndoGrouping()
        let primaryIndex = multiSelectionController.primaryIndex
        var newSelections: [NSRange] = []
        for operation in deleteOperations {
            replaceText(in: operation.deleteRange,
                       with: "",
                       selectedRangesAfterUndo: selections,
                       primaryIndexAfterUndo: primaryIndex,
                       updateSelection: false)
            newSelections.append(NSRange(location: operation.caretLocation, length: 0))
        }
        for selection in selections where selection.length == 0 && selection.location == 0 {
            newSelections.append(selection)
        }
        timedUndoManager.endUndoGrouping()
        applySelectedRanges(newSelections.sorted { $0.location < $1.location }, notifyDelegate: false)
        sendSelectionChangedToTextSelectionView()
        delegate?.textInputViewDidChange(self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.textInputViewDidChangeSelection(self)
        }
    }

    private func deleteForwardAtAllSelections() {
        let selections = multiSelectionController.selections.sorted { $0.location > $1.location }
        var deleteOperations: [(deleteRange: NSRange, caretLocation: Int)] = []
        for selection in selections {
            if selection.length > 0 {
                deleteOperations.append((selection, selection.location))
                continue
            }
            guard selection.location < string.length else {
                continue
            }
            let deleteRange = string.customRangeOfComposedCharacterSequence(at: selection.location)
            deleteOperations.append((deleteRange, selection.location))
        }
        guard !deleteOperations.isEmpty else {
            return
        }
        guard deleteOperations.allSatisfy({ shouldChangeText(in: $0.deleteRange, replacementText: "") }) else {
            return
        }
        timedUndoManager.beginUndoGrouping()
        let primaryIndex = multiSelectionController.primaryIndex
        var newSelections: [NSRange] = []
        for operation in deleteOperations {
            replaceText(in: operation.deleteRange,
                       with: "",
                       selectedRangesAfterUndo: selections,
                       primaryIndexAfterUndo: primaryIndex,
                       updateSelection: false)
            newSelections.append(NSRange(location: operation.caretLocation, length: 0))
        }
        timedUndoManager.endUndoGrouping()
        applySelectedRanges(newSelections.sorted { $0.location < $1.location }, notifyDelegate: false)
        delegate?.textInputViewDidChange(self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.textInputViewDidChangeSelection(self)
        }
    }
}

// MARK: - Selection
extension TextInputView {
    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        if let indexedRange = range as? IndexedRange {
            return selectionRectService.selectionRects(in: indexedRange.range.nonNegativeLength)
        } else {
            return []
        }
    }

    private func safeSelectionRange(from range: NSRange) -> NSRange {
        let stringLength = stringView.length
        let cappedLocation = min(max(range.location, 0), stringLength)
        let cappedLength = min(max(range.length, 0), stringLength - cappedLocation)
        return NSRange(location: cappedLocation, length: cappedLength)
    }

    private func moveCaret(to linePosition: LinePosition) {
        if linePosition.row < lineManager.lineCount {
            let line = lineManager.line(atRow: linePosition.row)
            let location = line.location + min(linePosition.column, line.data.length)
            selection = NSRange(location: location, length: 0)
        } else {
            selection = nil
        }
    }

    private func sendSelectionChangedToTextSelectionView() {
        // The only way I've found to get the selection change to be reflected properly while still supporting Korean, Chinese, and deleting words with Option+Backspace is to call a private API in some cases. However, as pointed out by Alexander Blach in the following PR, there is another workaround to the issue.
        // When passing nil to the input delete, the text selection is update but the text input ignores it.
        // Even the Swift Playgrounds app does not get this right for all languages in all cases, so there seems to be some workarounds needed to due bugs in internal classes in UIKit that communicate with instances of UITextInput.
        inputDelegate?.selectionDidChange(nil)
    }
}

// MARK: - Indent and Outdent
extension TextInputView {
    func shiftLeft() {
        if multiSelectionController.hasMultipleSelections {
            shiftAllSelections(right: false)
        } else if let selection = selection {
            inputDelegate?.textWillChange(self)
            indentController.shiftLeft(in: selection)
            inputDelegate?.textDidChange(self)
        }
    }

    func shiftRight() {
        if multiSelectionController.hasMultipleSelections {
            shiftAllSelections(right: true)
        } else if let selection = selection {
            inputDelegate?.textWillChange(self)
            indentController.shiftRight(in: selection)
            inputDelegate?.textDidChange(self)
        }
    }

    /// Multi-cursor indent/outdent. `IndentController.shiftLeft/shiftRight(in:)` reports a single
    /// aggregate resulting range for whatever it's given, which can't be decomposed back into N
    /// independent carets when several selections land on the same or adjacent lines. Since
    /// neither operation is actually language-aware (both just prepend/remove one level of
    /// `indentStrategy.string(indentLevel: 1)` per line), it's simpler and exact to reimplement
    /// them here per distinct touched row — insert/remove directly, track the resulting delta for
    /// that row, and recompute every original selection's (row, column) against it afterward.
    private func shiftAllSelections(right: Bool) {
        let originalSelections = multiSelectionController.selections
        guard !originalSelections.isEmpty else {
            return
        }
        var rows = Set<Int>()
        for range in originalSelections {
            for line in lineManager.lines(in: range) {
                rows.insert(line.index)
            }
        }
        guard !rows.isEmpty else {
            return
        }
        var boundPairs: [(start: LinePosition, end: LinePosition)] = []
        for range in originalSelections {
            guard let startPosition = lineManager.linePosition(at: range.location),
                  let endPosition = lineManager.linePosition(at: range.upperBound) else {
                return
            }
            boundPairs.append((startPosition, endPosition))
        }
        let indentString = indentController.indentStrategy.string(indentLevel: 1)
        let indentLength = indentString.utf16.count
        var deltaByRow: [Int: Int] = [:]
        let primaryIndex = multiSelectionController.primaryIndex
        inputDelegate?.textWillChange(self)
        timedUndoManager.beginUndoGrouping()
        // Descending row order: an edit at one row's start never shifts the location of a row
        // above it, so rows still to be processed are unaffected by ones already done.
        for row in rows.sorted(by: >) {
            let line = lineManager.line(atRow: row)
            if right {
                replaceText(in: NSRange(location: line.location, length: 0),
                           with: indentString,
                           selectedRangesAfterUndo: originalSelections,
                           primaryIndexAfterUndo: primaryIndex,
                           updateSelection: false)
                deltaByRow[row] = indentLength
            } else {
                let lineString = stringView.substring(in: NSRange(location: line.location, length: line.data.length)) ?? ""
                if lineString.hasPrefix(indentString) {
                    replaceText(in: NSRange(location: line.location, length: indentLength),
                               with: "",
                               selectedRangesAfterUndo: originalSelections,
                               primaryIndexAfterUndo: primaryIndex,
                               updateSelection: false)
                    deltaByRow[row] = -indentLength
                } else {
                    deltaByRow[row] = 0
                }
            }
        }
        timedUndoManager.endUndoGrouping()
        inputDelegate?.textDidChange(self)
        var newSelections: [NSRange] = []
        for pair in boundPairs {
            guard let startLocation = adjustedLocation(forRow: pair.start.row, column: pair.start.column, deltaByRow: deltaByRow),
                  let endLocation = adjustedLocation(forRow: pair.end.row, column: pair.end.column, deltaByRow: deltaByRow) else {
                continue
            }
            newSelections.append(NSRange(location: min(startLocation, endLocation), length: abs(endLocation - startLocation)))
        }
        guard !newSelections.isEmpty else {
            return
        }
        applySelectedRanges(newSelections.sorted { $0.location < $1.location })
    }

    /// Maps a pre-edit (row, column) to its post-edit document offset, using the per-row delta
    /// recorded while indenting/outdenting. Line count is unaffected by these operations, so rows
    /// still line up directly; only each row's own start (and thus every column on it) may have
    /// shifted by the row's own delta.
    private func adjustedLocation(forRow row: Int, column: Int, deltaByRow: [Int: Int]) -> Int? {
        location(forRow: row, column: column + (deltaByRow[row] ?? 0))
    }

    /// Resolves a (row, column) pair — as produced by `LineManager.linePosition(at:)` — back to a
    /// document offset, clamping the column to the row's own length. Shared by the multi-cursor
    /// indent and move-line batch operations, which both need to reconstruct carets from
    /// pre-edit (row, column) captures once their edits are done.
    private func location(forRow row: Int, column: Int) -> Int? {
        guard row >= 0, row < lineManager.lineCount else {
            return nil
        }
        let line = lineManager.line(atRow: row)
        return line.location + min(max(column, 0), line.data.length)
    }
}

// MARK: - Move Lines
extension TextInputView {
    func moveSelectedLinesUp() {
        if multiSelectionController.hasMultipleSelections {
            moveAllSelectedLines(byOffset: -1, undoActionName: L10n.Undo.ActionName.moveLinesUp)
        } else {
            moveSelectedLine(byOffset: -1, undoActionName: L10n.Undo.ActionName.moveLinesUp)
        }
    }

    func moveSelectedLinesDown() {
        if multiSelectionController.hasMultipleSelections {
            moveAllSelectedLines(byOffset: 1, undoActionName: L10n.Undo.ActionName.moveLinesDown)
        } else {
            moveSelectedLine(byOffset: 1, undoActionName: L10n.Undo.ActionName.moveLinesDown)
        }
    }

    private func moveSelectedLine(byOffset lineOffset: Int, undoActionName: String) {
        guard let oldSelectedRange = selection else {
            return
        }
        let moveLinesService = MoveLinesService(stringView: stringView, lineManager: lineManager, lineEndingSymbol: lineEndings.symbol)
        guard let operation = moveLinesService.operationForMovingLines(in: oldSelectedRange, byOffset: lineOffset) else {
            return
        }
        timedUndoManager.endUndoGrouping()
        timedUndoManager.beginUndoGrouping()
        replaceText(in: operation.removeRange, with: "", undoActionName: undoActionName)
        replaceText(in: operation.replacementRange, with: operation.replacementString, undoActionName: undoActionName)
        notifyInputDelegateAboutSelectionChangeInLayoutSubviews = true
        selection = operation.selectedRange
        timedUndoManager.endUndoGrouping()
    }

    /// Multi-cursor move-line. `MoveLinesService` computes one group's move as a pure row-range
    /// relocation that preserves relative row order and column offsets within the group and
    /// leaves the total document length unchanged, so every original selection's row simply
    /// becomes `row + lineOffset` afterward with its column unchanged — no per-character delta
    /// bookkeeping is needed here, unlike indent.
    ///
    /// Groups are built from strictly contiguous rows, same as `shiftAllSelections`. Each group
    /// also touches one row *beyond* itself — its target row, immediately above (up) or below
    /// (down) the group — but that never collides with a neighboring group's own rows as long as
    /// the two aren't directly adjacent: a gap of >=1 row always leaves at least one full row of
    /// clearance between one group's target and the next group's nearest row, in either
    /// direction. Two directly-adjacent groups (gap 0) are already merged into one by the
    /// contiguous-row grouping itself, so no extra gap tolerance is needed here.
    ///
    /// Processing order is top-to-bottom for an upward move and bottom-to-top for a downward one,
    /// so a group's target row is always still in its pre-move position when that group is
    /// processed. The whole operation aborts — leaving nothing modified, since operations are
    /// only applied after every group has been validated — if any group would run off the
    /// document edge.
    private func moveAllSelectedLines(byOffset lineOffset: Int, undoActionName: String) {
        let originalSelections = multiSelectionController.selections
        guard !originalSelections.isEmpty else {
            return
        }
        var rows = Set<Int>()
        for range in originalSelections {
            for line in lineManager.lines(in: range) {
                rows.insert(line.index)
            }
        }
        guard !rows.isEmpty else {
            return
        }
        var boundPairs: [(start: LinePosition, end: LinePosition)] = []
        for range in originalSelections {
            guard let startPosition = lineManager.linePosition(at: range.location),
                  let endPosition = lineManager.linePosition(at: range.upperBound) else {
                return
            }
            boundPairs.append((startPosition, endPosition))
        }
        let sortedRows = rows.sorted()
        var groups: [ClosedRange<Int>] = []
        for row in sortedRows {
            if let last = groups.last, row == last.upperBound + 1 {
                groups[groups.count - 1] = last.lowerBound...row
            } else {
                groups.append(row...row)
            }
        }
        let orderedGroups = lineOffset < 0
            ? groups.sorted { $0.lowerBound < $1.lowerBound }
            : groups.sorted { $0.lowerBound > $1.lowerBound }
        var operations: [MoveLinesOperation] = []
        let moveLinesService = MoveLinesService(stringView: stringView, lineManager: lineManager, lineEndingSymbol: lineEndings.symbol)
        for group in orderedGroups {
            let firstLine = lineManager.line(atRow: group.lowerBound)
            let lastLine = lineManager.line(atRow: group.upperBound)
            let groupRange = NSRange(location: firstLine.location, length: (lastLine.location + lastLine.data.length) - firstLine.location)
            guard let operation = moveLinesService.operationForMovingLines(in: groupRange, byOffset: lineOffset) else {
                // A group would run off the document edge -- abort without modifying anything.
                return
            }
            operations.append(operation)
        }
        timedUndoManager.endUndoGrouping()
        timedUndoManager.beginUndoGrouping()
        let primaryIndex = multiSelectionController.primaryIndex
        for operation in operations {
            replaceText(in: operation.removeRange,
                       with: "",
                       selectedRangesAfterUndo: originalSelections,
                       primaryIndexAfterUndo: primaryIndex,
                       undoActionName: undoActionName,
                       updateSelection: false)
            replaceText(in: operation.replacementRange,
                       with: operation.replacementString,
                       selectedRangesAfterUndo: originalSelections,
                       primaryIndexAfterUndo: primaryIndex,
                       undoActionName: undoActionName,
                       updateSelection: false)
        }
        notifyInputDelegateAboutSelectionChangeInLayoutSubviews = true
        var newSelections: [NSRange] = []
        for pair in boundPairs {
            guard let startLocation = location(forRow: pair.start.row + lineOffset, column: pair.start.column),
                  let endLocation = location(forRow: pair.end.row + lineOffset, column: pair.end.column) else {
                continue
            }
            newSelections.append(NSRange(location: min(startLocation, endLocation), length: abs(endLocation - startLocation)))
        }
        timedUndoManager.endUndoGrouping()
        guard !newSelections.isEmpty else {
            return
        }
        applySelectedRanges(newSelections.sorted { $0.location < $1.location })
    }
}

// MARK: - Marking
extension TextInputView {
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        applyMarkedText(markedText, selectedRange: selectedRange)
    }

    private func applyMarkedText(_ markedText: String?, selectedRange markedSelectedRange: NSRange) {
        guard let range = imeMarkedRange ?? self.selection else {
            return
        }
        let markedText = markedText ?? ""
        guard shouldChangeText(in: range, replacementText: markedText) else {
            return
        }
        imeMarkedRange = markedText.isEmpty ? nil : NSRange(location: range.location, length: markedText.utf16.count)
        replaceText(in: range, with: markedText)
        // The selected range passed to setMarkedText(_:selectedRange:) is local to the marked range.
        let preferredSelectedRange = NSRange(location: range.location + markedSelectedRange.location, length: markedSelectedRange.length)
        inputDelegate?.selectionWillChange(self)
        _selectedRange = safeSelectionRange(from: preferredSelectedRange)
        inputDelegate?.selectionDidChange(self)
        delegate?.textInputViewDidUpdateMarkedRange(self)
    }

    func unmarkText() {
        inputDelegate?.selectionWillChange(self)
        imeMarkedRange = nil
        inputDelegate?.selectionDidChange(self)
        delegate?.textInputViewDidUpdateMarkedRange(self)
    }
}

// MARK: - Ranges and Positions
extension TextInputView {
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        // This implementation seems to match the behavior of UITextView.
        guard let indexedRange = range as? IndexedRange else {
            return nil
        }
        switch direction {
        case .left, .up:
            return IndexedPosition(index: indexedRange.range.lowerBound)
        case .right, .down:
            return IndexedPosition(index: indexedRange.range.upperBound)
        @unknown default:
            return nil
        }
    }

    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? {
        guard let indexedPosition = position as? IndexedPosition else {
            return nil
        }
        didCallPositionFromPositionInDirectionWithOffset = true
        guard let newLocation = lineMovementController.location(from: indexedPosition.index, in: direction, offset: offset) else {
            return nil
        }
        return IndexedPosition(index: newLocation)
    }

    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? {
        // This implementation seems to match the behavior of UITextView.
        guard let indexedPosition = position as? IndexedPosition else {
            return nil
        }
        switch direction {
        case .left, .up:
            let leftIndex = max(indexedPosition.index - 1, 0)
            return IndexedRange(location: leftIndex, length: indexedPosition.index - leftIndex)
        case .right, .down:
            let rightIndex = min(indexedPosition.index + 1, stringView.length)
            return IndexedRange(location: indexedPosition.index, length: rightIndex - indexedPosition.index)
        @unknown default:
            return nil
        }
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        guard let index = layoutManager.closestIndex(to: point) else {
            return nil
        }
        let cappedIndex = max(index - 1, 0)
        let range = stringView.rangeOfComposedCharacterSequence(at: cappedIndex)
        return IndexedRange(range)
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        if let index = layoutManager.closestIndex(to: point) {
            return IndexedPosition(index: index)
        } else {
            return nil
        }
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard let indexedRange = range as? IndexedRange else {
            return nil
        }
        guard let index = layoutManager.closestIndex(to: point) else {
            return nil
        }
        let minimumIndex = indexedRange.range.lowerBound
        let maximumIndex = indexedRange.range.upperBound
        let cappedIndex = min(max(index, minimumIndex), maximumIndex)
        return IndexedPosition(index: cappedIndex)
    }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard let fromIndexedPosition = fromPosition as? IndexedPosition, let toIndexedPosition = toPosition as? IndexedPosition else {
            return nil
        }
        let range = NSRange(location: fromIndexedPosition.index, length: toIndexedPosition.index - fromIndexedPosition.index)
        return IndexedRange(range)
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let indexedPosition = position as? IndexedPosition else {
            return nil
        }
        let newPosition = indexedPosition.index + offset
        guard newPosition >= 0 && newPosition <= string.length else {
            return nil
        }
        return IndexedPosition(index: newPosition)
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard let indexedPosition = position as? IndexedPosition, let otherIndexedPosition = other as? IndexedPosition else {
            #if targetEnvironment(macCatalyst)
            // Mac Catalyst may pass <uninitialized> to `position`. I'm not sure what the right way to deal with that is but returning .orderedSame seems to work.
            return .orderedSame
            #else
            fatalError("Positions must be of type \(IndexedPosition.self)")
            #endif
        }
        if indexedPosition.index < otherIndexedPosition.index {
            return .orderedAscending
        } else if indexedPosition.index > otherIndexedPosition.index {
            return .orderedDescending
        } else {
            return .orderedSame
        }
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        if let fromPosition = from as? IndexedPosition, let toPosition = toPosition as? IndexedPosition {
            return toPosition.index - fromPosition.index
        } else {
            return 0
        }
    }
}

// MARK: - Writing Direction
extension TextInputView {
    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection {
        .natural
    }

    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}
}

// MARK: - Context Menu
extension TextInputView {
    func presentEditMenuForText(in range: NSRange) {
        editMenuController.presentEditMenu(from: self, forTextIn: range)
    }

    func showContextMenu(with event: NSEvent) {
        editMenuController.presentContextMenu(for: self, with: event)
    }

    @objc func replaceTextInSelectedHighlightedRange() {
        if let selection = selection, let highlightedRange = highlightedRange(for: selection) {
            delegate?.textInputView(self, replaceTextIn: highlightedRange)
        }
    }

    private func highlightedRange(for range: NSRange) -> HighlightedRange? {
        highlightedRanges.first { $0.range == range }
    }
}

// MARK: - TreeSitterLanguageModeDeleage
extension TextInputView: TreeSitterLanguageModeDelegate {
    nonisolated func treeSitterLanguageMode(_ languageMode: TreeSitterInternalLanguageMode, bytesAt byteIndex: ByteCount) -> TreeSitterTextProviderResult? {
        guard byteIndex.value >= 0 && byteIndex < stringView.byteCount else {
            return nil
        }
        let targetByteCount: ByteCount = 4 * 1_024
        let endByte = min(byteIndex + targetByteCount, stringView.byteCount)
        let byteRange = ByteRange(from: byteIndex, to: endByte)
        if let result = stringView.bytes(in: byteRange) {
            return TreeSitterTextProviderResult(bytes: result.bytes, length: UInt32(result.length.value))
        } else {
            return nil
        }
    }
}

// MARK: - LineControllerStorageDelegate
extension TextInputView: @preconcurrency LineControllerStorageDelegate {
    func lineControllerStorage(_ storage: LineControllerStorage, didCreate lineController: LineController) {
        lineController.delegate = self
        lineController.constrainingWidth = layoutManager.constrainingLineWidth
        lineController.estimatedLineFragmentHeight = theme.font.totalLineHeight
        lineController.lineFragmentHeightMultiplier = lineHeightMultiplier
        lineController.tabWidth = indentController.tabWidth
        lineController.theme = theme
        lineController.lineBreakMode = lineBreakMode
    }
}

// MARK: - LineControllerDelegate
extension TextInputView: @preconcurrency LineControllerDelegate {
    func lineSyntaxHighlighter(for lineController: LineController) -> LineSyntaxHighlighter? {
        languageMode.createLineSyntaxHighlighter()
    }

    func lineControllerDidInvalidateLineWidthDuringAsyncSyntaxHighlight(_ lineController: LineController) {
        setNeedsLayout()
        layoutManager.setNeedsLayout()
    }
}

// MARK: - LayoutManagerDelegate
extension TextInputView: LayoutManagerDelegate {
    func layoutManager(_ layoutManager: LayoutManager, didProposeContentOffsetAdjustment contentOffsetAdjustment: CGPoint) {
        delegate?.textInputView(self, didProposeContentOffsetAdjustment: contentOffsetAdjustment)
    }
}

// MARK: - IndentControllerDelegate
extension TextInputView: IndentControllerDelegate {
    func indentController(_ controller: IndentController, shouldInsert text: String, in range: NSRange) {
        if let restore = pendingMultiSelectionUndoRestore {
            replaceText(in: range, with: text, selectedRangesAfterUndo: restore.ranges, primaryIndexAfterUndo: restore.primaryIndex)
        } else {
            replaceText(in: range, with: text)
        }
    }

    func indentController(_ controller: IndentController, shouldSelect range: NSRange) {
        inputDelegate?.selectionWillChange(self)
        selection = range
        inputDelegate?.selectionDidChange(self)
    }

    func indentControllerDidUpdateTabWidth(_ controller: IndentController) {
        invalidateLines()
    }
}

// MARK: - EditMenuControllerDelegate
extension TextInputView: EditMenuControllerDelegate {
    func editMenuController(_ controller: EditMenuController, caretRectAt location: Int) -> CGRect {
        caretRectService.caretRect(at: location, allowMovingCaretToNextLineFragment: false)
    }

    func editMenuControllerShouldReplaceText(_ controller: EditMenuController) {
        replaceTextInSelectedHighlightedRange()
    }

    func editMenuController(_ controller: EditMenuController, canReplaceTextIn highlightedRange: HighlightedRange) -> Bool {
        delegate?.textInputView(self, canReplaceTextIn: highlightedRange) ?? false
    }

    func editMenuController(_ controller: EditMenuController, highlightedRangeFor range: NSRange) -> HighlightedRange? {
        highlightedRange(for: range)
    }

    func selectedRange(for controller: EditMenuController) -> NSRange? {
        selection
    }

    func editMenuControllerIsEditable(_ controller: EditMenuController) -> Bool {
        delegate?.textInputViewIsEditable(self) ?? true
    }
}
