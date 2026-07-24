import AppKit
import Foundation

final class SelectionOverlayController {
    private let textInputView: TextInputView
    private let caretRectService: CaretRectService
    private let selectionRectService: SelectionRectService
    private let caretView = CaretView()
    private let selectionOverlayView = SelectionOverlayView()
    private let startHandle = SelectionHandleView(kind: .start)
    private let endHandle = SelectionHandleView(kind: .end)
    private var blinkTimer: Timer?
    private var isCaretVisible = true
    private var isAdjustingSelection = false

    var isEnabled = false {
        didSet {
            if isEnabled != oldValue {
                updateVisibility()
                if isEnabled {
                    updateLayout()
                } else {
                    stopCaretBlink()
                }
            }
        }
    }

    init(textInputView: TextInputView,
         caretRectService: CaretRectService,
         selectionRectService: SelectionRectService) {
        self.textInputView = textInputView
        self.caretRectService = caretRectService
        self.selectionRectService = selectionRectService
        configureHandles()
    }

    func install() {
        textInputView.addSubview(selectionOverlayView)
        textInputView.addSubview(caretView)
        textInputView.addSubview(startHandle)
        textInputView.addSubview(endHandle)
        updateColors()
    }

    func updateLayout() {
        guard isEnabled else {
            return
        }
        selectionOverlayView.frame = textInputView.bounds
        updateColors()
        updateSelectionOverlay()
        updateSelectionHandles()
        updateCaret()
        updateCaretBlinkState()
    }

    func updateColors() {
        caretView.caretColor = textInputView.insertionPointColor
        selectionOverlayView.highlightColor = textInputView.selectionHighlightColor
        startHandle.handleColor = textInputView.insertionPointColor
        endHandle.handleColor = textInputView.insertionPointColor
    }

    func selectionDidChange() {
        updateLayout()
    }

    func editingDidChange(isEditing: Bool) {
        if isEditing {
            updateLayout()
        } else {
            stopCaretBlink()
            caretView.isHidden = true
            selectionOverlayView.selectionRects = []
            selectionOverlayView.setNeedsDisplay()
            startHandle.isHidden = true
            endHandle.isHidden = true
        }
    }

    func enableCursorBlinks() {
        guard isEnabled else {
            return
        }
        isCaretVisible = true
        caretView.isHidden = false
        startCaretBlinkIfNeeded()
    }
}

private extension SelectionOverlayController {
    private var shouldShowCaret: Bool {
        isEnabled
            && textInputView.isEditing
            && textInputView.selection?.length == 0
            && textInputView.markedTextRange == nil
            && !isAdjustingSelection
    }

    private var shouldShowSelection: Bool {
        isEnabled && (textInputView.selection?.length ?? 0) > 0
    }

    private var shouldShowSelectionHandles: Bool {
        shouldShowSelection
            && (textInputView.delegate?.textInputViewIsSelectable(textInputView) ?? true)
    }

    private func configureHandles() {
        startHandle.onDrag = { [weak self] event in
            self?.handleStartDrag(with: event)
        }
        startHandle.onDragEnded = { [weak self] event in
            self?.handleDragEnded(with: event)
        }
        endHandle.onDrag = { [weak self] event in
            self?.handleEndDrag(with: event)
        }
        endHandle.onDragEnded = { [weak self] event in
            self?.handleDragEnded(with: event)
        }
    }

    private func updateVisibility() {
        caretView.isHidden = !isEnabled
        selectionOverlayView.isHidden = !isEnabled
        startHandle.isHidden = !isEnabled
        endHandle.isHidden = !isEnabled
    }

    private func updateSelectionOverlay() {
        guard shouldShowSelection, let selectedRange = textInputView.selection else {
            selectionOverlayView.selectionRects = []
            selectionOverlayView.setNeedsDisplay()
            return
        }
        selectionOverlayView.selectionRects = selectionRectService.selectionRects(in: selectedRange)
    }

    private func updateSelectionHandles() {
        guard shouldShowSelectionHandles, let selectedRange = textInputView.selection else {
            startHandle.isHidden = true
            endHandle.isHidden = true
            return
        }
        let startCaretRect = caretRectService.caretRect(at: selectedRange.location, allowMovingCaretToNextLineFragment: true)
        let endIndex = max(selectedRange.upperBound - 1, selectedRange.location)
        let endCaretRect = caretRectService.caretRect(at: endIndex, allowMovingCaretToNextLineFragment: false)
        startHandle.frame = startHandle.frame(anchoredTo: startCaretRect)
        endHandle.frame = endHandle.frame(anchoredTo: endCaretRect)
        startHandle.isHidden = false
        endHandle.isHidden = false
        textInputView.bringSubviewToFront(startHandle)
        textInputView.bringSubviewToFront(endHandle)
    }

    private func updateCaret() {
        guard shouldShowCaret, let selectedRange = textInputView.selection else {
            caretView.isHidden = true
            return
        }
        let caretRect = caretRectService.caretRect(at: selectedRange.location, allowMovingCaretToNextLineFragment: true)
        caretView.frame = caretRect
        caretView.isHidden = !isCaretVisible
        textInputView.bringSubviewToFront(caretView)
    }

    private func updateCaretBlinkState() {
        if shouldShowCaret {
            startCaretBlinkIfNeeded()
        } else {
            stopCaretBlink()
        }
    }

    private func startCaretBlinkIfNeeded() {
        guard shouldShowCaret else {
            stopCaretBlink()
            return
        }
        guard blinkTimer == nil else {
            return
        }
        isCaretVisible = true
        caretView.isHidden = false
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            self?.toggleCaretVisibility()
        }
    }

    private func stopCaretBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isCaretVisible = true
    }

    private func toggleCaretVisibility() {
        guard shouldShowCaret else {
            stopCaretBlink()
            return
        }
        isCaretVisible.toggle()
        caretView.isHidden = !isCaretVisible
    }

    private func handleStartDrag(with event: NSEvent) {
        guard let selection = textInputView.selection else {
            return
        }
        isAdjustingSelection = true
        stopCaretBlink()
        let point = textInputView.convert(event.locationInWindow, from: nil)
        if let index = textInputView.characterIndex(at: point) {
            textInputView.updateSelection(from: index, to: selection.upperBound)
        }
    }

    private func handleEndDrag(with event: NSEvent) {
        guard let selection = textInputView.selection else {
            return
        }
        isAdjustingSelection = true
        stopCaretBlink()
        let point = textInputView.convert(event.locationInWindow, from: nil)
        if let index = textInputView.characterIndex(at: point) {
            textInputView.updateSelection(from: selection.location, to: index)
        }
    }

    private func handleDragEnded(with event: NSEvent) {
        isAdjustingSelection = false
        textInputView.selectionAnchor = textInputView.selection?.location
        updateLayout()
    }
}
