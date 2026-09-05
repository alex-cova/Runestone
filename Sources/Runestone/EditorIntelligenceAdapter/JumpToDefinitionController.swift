@preconcurrency import AppKit
import EditorIntelligence

/// Handles cmd+click navigation to symbol definitions.
@MainActor
public final class JumpToDefinitionController {
    private weak var textView: TextView?
    private let navigationEngine: NavigationEngine
    private let adapter: RunestoneEditorAdapter

    public var onNavigate: ((Location) -> Void)?

    public init(textView: TextView, adapter: RunestoneEditorAdapter, navigationEngine: NavigationEngine) {
        self.textView = textView
        self.adapter = adapter
        self.navigationEngine = navigationEngine
        installGesture(on: textView)
    }

    /// Jump to the definition of the symbol at the current cursor.
    public func jumpToDefinition() {
        guard let document = adapter.currentDocument else {
            return
        }
        jumpToDefinition(at: document.cursor.position)
    }

    public func jumpToDefinition(at position: TextPosition) {
        guard let document = adapter.currentDocument else {
            return
        }
        let context = NavigationContext(
            document: document,
            cursor: Cursor(position: position),
            selection: Selection(range: TextRange(start: position, end: position)),
            trigger: .manual
        )
        Task {
            guard let result = await navigationEngine.navigate(context: context) else {
                return
            }
            await MainActor.run {
                switch result {
                case .single(let location):
                    self.onNavigate?(location)
                    self.focus(location: location)
                case .multiple(let locations):
                    if let first = locations.first {
                        self.onNavigate?(first)
                        self.focus(location: first)
                    }
                }
            }
        }
    }

    private func focus(location: Location) {
        guard let textView else {
            return
        }
        let range = TextEditApplicator.nsRange(for: location.range, in: textView)
        textView.selectedRanges = [range]
        textView.scrollRangeToVisible(range)
    }

    private func installGesture(on textView: TextView) {
        let clickGesture = CmdClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        textView.addGestureRecognizer(clickGesture)
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard let textView else {
            return
        }
        let point = gesture.location(in: textView)
        if let index = textView.characterIndex(at: point),
           let textLocation = textView.textLocation(at: index) {
            jumpToDefinition(at: TextPosition(
                line: textLocation.lineNumber,
                column: textLocation.column,
                utf16Offset: index
            ))
            return
        }
        guard let document = adapter.currentDocument else {
            return
        }
        jumpToDefinition(at: document.cursor.position)
    }
}

private final class CmdClickGestureRecognizer: NSClickGestureRecognizer {
    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            return
        }
        super.mouseDown(with: event)
    }
}
