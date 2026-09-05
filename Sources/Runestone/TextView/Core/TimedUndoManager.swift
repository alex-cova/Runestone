import Foundation

final class TimedUndoManager: UndoManager {
    private let endGroupingInterval: TimeInterval = 1
    private var endGroupingTimer: Timer?
    private var hasOpenGroup: Bool {
        groupingLevel > 0
    }

    override init() {
        super.init()
        groupsByEvent = false
    }

    override func removeAllActions() {
        cancelTimer()
        super.removeAllActions()
    }

    override func beginUndoGrouping() {
        if !hasOpenGroup {
            super.beginUndoGrouping()
            if endGroupingTimer == nil {
                scheduleTimer()
            }
        }
    }

    /// Closes a coalesced typing group if one is open, then opens a fresh group.
    /// Multi-caret and other batch edits must use this so `endUndoGrouping()` does not
    /// close the in-progress 1s typing group.
    func beginIsolatedUndoGrouping() {
        endUndoGrouping()
        beginUndoGrouping()
    }

    override func endUndoGrouping() {
        cancelTimer()
        if hasOpenGroup {
            super.endUndoGrouping()
        }
    }

    override func undo() {
        endUndoGrouping()
        super.undo()
    }
}

private extension TimedUndoManager {
    private func scheduleTimer() {
        let timer = Timer(timeInterval: endGroupingInterval, target: self, selector: #selector(timerDidTrigger), userInfo: nil, repeats: false)
        endGroupingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelTimer() {
        endGroupingTimer?.invalidate()
        endGroupingTimer = nil
    }

    @objc private func timerDidTrigger() {
        cancelTimer()
        endUndoGrouping()
    }
}
