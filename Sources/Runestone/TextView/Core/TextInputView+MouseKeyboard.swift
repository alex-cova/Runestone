import AppKit
import Foundation

extension TextInputView {
    override func mouseDown(with event: NSEvent) {
        guard delegate?.textInputViewIsSelectable(self) ?? true else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if delegate?.textInputViewIsEditable(self) ?? true {
            if !isFirstResponder {
                _ = becomeFirstResponder()
            } else {
                window?.makeFirstResponder(self)
            }
        } else {
            delegate?.textInputView(self, didRequestSelectionInteraction: true)
        }
        isMouseSelecting = true
        if isPointOnSelectionHandle(point) {
            return
        }
        if event.modifierFlags.contains(.shift) {
            let anchor = selectionAnchor ?? selection?.location ?? 0
            if let index = characterIndex(at: point) {
                setSelectedRange(from: anchor, to: index)
            }
        } else if event.clickCount >= 3 {
            selectParagraph(at: point)
            selectionAnchor = selection?.location
        } else if event.clickCount == 2 {
            selectWord(at: point)
            selectionAnchor = selection?.location
        } else if let index = characterIndex(at: point) {
            selectionAnchor = index
            selection = NSRange(location: index, length: 0)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMouseSelecting, delegate?.textInputViewIsSelectable(self) ?? true else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let anchor = selectionAnchor ?? selection?.location ?? 0
        if let index = characterIndex(at: point) {
            setSelectedRange(from: anchor, to: index)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isMouseSelecting = false
        if selection?.length == 0 {
            selectionAnchor = selection?.location
        }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard delegate?.textInputViewIsSelectable(self) ?? true else {
            super.rightMouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let index = characterIndex(at: point) {
            if selection?.contains(index) != true {
                selection = NSRange(location: index, length: 0)
            }
        }
        if delegate?.textInputViewIsEditable(self) ?? true, !isFirstResponder {
            _ = becomeFirstResponder()
        }
        showContextMenu(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if delegate?.textInputViewIsEditable(self) ?? true, inputContext?.handleEvent(event) == true {
            return
        }
        guard delegate?.textInputViewIsEditable(self) ?? true else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if handleCommandKeyDown(event) {
                return
            }
        }
        switch event.keyCode {
        case 0x7B:
            moveSelectionForArrowKey(direction: .left, flags: flags)
        case 0x7C:
            moveSelectionForArrowKey(direction: .right, flags: flags)
        case 0x7D:
            moveSelectionForArrowKey(direction: .down, flags: flags)
        case 0x7E:
            moveSelectionForArrowKey(direction: .up, flags: flags)
        case 0x73:
            moveSelectionToBoundary(.line, direction: .backward, extending: flags.contains(.shift))
        case 0x77:
            moveSelectionToBoundary(.line, direction: .forward, extending: flags.contains(.shift))
        case 0x33:
            if flags.contains(.option) {
                deleteWord(backward: true)
            } else {
                deleteBackward()
            }
        case 0x75:
            if flags.contains(.option) {
                deleteWord(backward: false)
            } else {
                deleteForward()
            }
        default:
            if let characters = event.characters, !characters.isEmpty, shouldInsert(characters: characters, flags: flags) {
                insertText(characters)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

private extension TextInputView {
    private func setSelectedRange(from anchor: Int, to index: Int) {
        let start = min(anchor, index)
        let end = max(anchor, index)
        inputDelegate?.selectionWillChange(self)
        selection = NSRange(location: start, length: end - start)
        inputDelegate?.selectionDidChange(self)
    }

    private func selectWord(at point: CGPoint) {
        guard let position = closestPosition(to: point) else {
            return
        }
        let start = tokenizer.position(from: position, toBoundary: .word, inDirection: .backward) ?? position
        let end = tokenizer.position(from: position, toBoundary: .word, inDirection: .forward) ?? position
        guard let startIndex = (start as? IndexedPosition)?.index,
              let endIndex = (end as? IndexedPosition)?.index else {
            return
        }
        inputDelegate?.selectionWillChange(self)
        selection = NSRange(location: startIndex, length: endIndex - startIndex)
        inputDelegate?.selectionDidChange(self)
    }

    private func selectParagraph(at point: CGPoint) {
        guard let position = closestPosition(to: point) else {
            return
        }
        let start = tokenizer.position(from: position, toBoundary: .paragraph, inDirection: .backward) ?? position
        let end = tokenizer.position(from: position, toBoundary: .paragraph, inDirection: .forward) ?? position
        guard let startIndex = (start as? IndexedPosition)?.index,
              let endIndex = (end as? IndexedPosition)?.index else {
            return
        }
        inputDelegate?.selectionWillChange(self)
        selection = NSRange(location: startIndex, length: endIndex - startIndex)
        inputDelegate?.selectionDidChange(self)
    }

    private func handleCommandKeyDown(_ event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        if characters == "a" {
            selectAll(nil)
            return true
        }
        return false
    }

    private func moveSelectionForArrowKey(direction: UITextLayoutDirection, flags: NSEvent.ModifierFlags) {
        if flags.contains(.command) {
            moveSelectionToBoundary(.line, direction: layoutDirectionToTextDirection(direction), extending: flags.contains(.shift))
        } else if flags.contains(.option) {
            moveSelectionToBoundary(.word, direction: layoutDirectionToTextDirection(direction), extending: flags.contains(.shift))
        } else {
            moveSelectionByCharacter(in: direction, extending: flags.contains(.shift))
        }
    }

    private func layoutDirectionToTextDirection(_ direction: UITextLayoutDirection) -> UITextDirection {
        switch direction {
        case .left, .up:
            return .backward
        case .right, .down:
            return .forward
        @unknown default:
            return .forward
        }
    }

    private func moveSelectionByCharacter(in direction: UITextLayoutDirection, extending: Bool) {
        guard let currentRange = selection else {
            return
        }
        let referenceIndex: Int
        if extending {
            switch direction {
            case .left, .up:
                referenceIndex = currentRange.upperBound
            case .right, .down:
                referenceIndex = currentRange.location
            @unknown default:
                referenceIndex = currentRange.location
            }
        } else {
            referenceIndex = direction == .left ? currentRange.location : currentRange.upperBound
        }
        let referencePosition = IndexedPosition(index: referenceIndex)
        guard let newPosition = position(from: referencePosition, in: direction, offset: 1) as? IndexedPosition else {
            return
        }
        updateSelection(activeLocation: newPosition.index, extending: extending)
    }

    private func moveSelectionToBoundary(_ granularity: UITextGranularity,
                                       direction: UITextDirection,
                                       extending: Bool) {
        guard let currentRange = selection else {
            return
        }
        let referenceIndex = extending
            ? (direction == .backward ? currentRange.upperBound : currentRange.location)
            : (direction == .backward ? currentRange.location : currentRange.upperBound)
        let position = IndexedPosition(index: referenceIndex)
        guard let boundary = tokenizer.position(from: position, toBoundary: granularity, inDirection: direction) as? IndexedPosition else {
            return
        }
        updateSelection(activeLocation: boundary.index, extending: extending)
    }

    private func updateSelection(activeLocation: Int, extending: Bool) {
        if extending {
            if selectionAnchor == nil {
                selectionAnchor = selection?.location ?? activeLocation
            }
            let anchor = selectionAnchor ?? activeLocation
            setSelectedRange(from: anchor, to: activeLocation)
            // Host notify deferred via selection mutation paths / setter.
        } else {
            selectionAnchor = activeLocation
            inputDelegate?.selectionWillChange(self)
            selection = NSRange(location: activeLocation, length: 0)
            inputDelegate?.selectionDidChange(self)
        }
    }

    private func shouldInsert(characters: String, flags: NSEvent.ModifierFlags) -> Bool {
        if flags.contains(.command) || flags.contains(.control) {
            return false
        }
        if characters == "\t" || characters == "\n" || characters == "\r" {
            return true
        }
        return characters.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private func isPointOnSelectionHandle(_ point: CGPoint) -> Bool {
        guard let selection = selection, selection.length > 0 else {
            return false
        }
        for subview in subviews.reversed() {
            guard let handle = subview as? SelectionHandleView, !handle.isHidden else {
                continue
            }
            if handle.frame.insetBy(dx: -4, dy: -4).contains(point) {
                return true
            }
        }
        return false
    }
}
