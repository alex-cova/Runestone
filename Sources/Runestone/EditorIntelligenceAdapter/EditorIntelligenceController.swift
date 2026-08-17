import AppKit
import EditorIntelligence

/// Wires Editor Intelligence Platform services into a live `TextView`.
///
/// Owns the `RunestoneEditorAdapter`, mounts completion/hover/ghost-text UI, and drives
/// completion, hover, and diagnostics from editor events.
@MainActor
public final class EditorIntelligenceController {
    public let adapter: RunestoneEditorAdapter
    public let completionEngine: CompletionEngine
    public let hoverEngine: HoverEngine
    public let diagnosticEngine: DiagnosticEngine
    public let navigationEngine: NavigationEngine?
    public let refactoringEngine: RefactoringEngine?

    private weak var textView: TextView?
    private var eventTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?

    private let overlayContainer = NSView()
    private let completionPanelView: CompletionPanelView
    private let hoverWindowView: HoverWindowView
    private let ghostTextView: GhostTextView
    private let parameterHintsView: ParameterHintsView

    private var completionItems: [CompletionItem] = []
    private var selectedCompletionIndex = 0
    private var isCompletionVisible = false
    private var currentReplacementRange: EditorIntelligence.TextRange?
    private var ghostTextModel: GhostTextModel?
    private let forwardingDelegateBox: EditorIntelligenceForwardingDelegate

    /// Create a controller that connects EIP services to a text view.
    public init(
        textView: TextView,
        context: EditorContext = EditorContext(),
        completionEngine: CompletionEngine,
        hoverEngine: HoverEngine,
        diagnosticEngine: DiagnosticEngine,
        navigationEngine: NavigationEngine? = nil,
        refactoringEngine: RefactoringEngine? = nil,
        forwardingDelegate: TextViewDelegate? = nil
    ) {
        self.textView = textView
        self.completionEngine = completionEngine
        self.hoverEngine = hoverEngine
        self.diagnosticEngine = diagnosticEngine
        self.navigationEngine = navigationEngine
        self.refactoringEngine = refactoringEngine

        let placeholderRange = EditorIntelligence.TextRange(
            start: TextPosition(line: 0, column: 0, utf16Offset: 0),
            end: TextPosition(line: 0, column: 0, utf16Offset: 0)
        )
        completionPanelView = CompletionPanelView(
            model: CompletionPanelModel(items: [], replacementRange: placeholderRange)
        )
        hoverWindowView = HoverWindowView(
            model: HoverWindowModel(contents: "", anchorRange: placeholderRange)
        )
        ghostTextView = GhostTextView(
            model: GhostTextModel(text: "", anchorPosition: placeholderRange.start)
        )
        parameterHintsView = ParameterHintsView(
            model: ParameterHintsModel(signatures: [])
        )
        let forwarding = EditorIntelligenceForwardingDelegate(userDelegate: forwardingDelegate)
        forwardingDelegateBox = forwarding

        adapter = RunestoneEditorAdapter(textView: textView, context: context)
        adapter.forwardingDelegate = forwarding

        installOverlayViews(on: textView)
        textView.keyDownHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        forwarding.attach(controller: self)
        startObservingEvents()
    }

    deinit {
        eventTask?.cancel()
        hoverTask?.cancel()
        completionTask?.cancel()
    }

    // MARK: - Public API

    /// Manually trigger a completion request at the current cursor.
    public func triggerCompletion() {
        requestCompletion(trigger: .manual)
    }

    /// Dismiss any visible completion UI.
    public func dismissCompletion() {
        hideCompletionPanel()
        completionTask?.cancel()
        Task { await completionEngine.cancel() }
    }

    /// Apply the currently selected completion item.
    public func acceptSelectedCompletion() {
        guard isCompletionVisible,
              completionItems.indices.contains(selectedCompletionIndex),
              let replacementRange = currentReplacementRange else {
            return
        }
        applyCompletion(completionItems[selectedCompletionIndex], replacementRange: replacementRange)
        hideCompletionPanel()
    }

    /// Request hover information for the current cursor position.
    public func requestHover() {
        guard let document = adapter.currentDocument else {
            return
        }
        hoverTask?.cancel()
        let context = HoverContext(
            document: document,
            cursor: document.cursor,
            selection: document.selection,
            trigger: .manual
        )
        hoverTask = Task { [weak self] in
            guard let self else { return }
            if let result = await hoverEngine.hover(context: context) {
                await MainActor.run {
                    self.showHover(result, document: document)
                }
            }
        }
    }

    /// Refresh diagnostics and apply squiggles to the text view.
    public func refreshDiagnostics() {
        guard let document = adapter.currentDocument, let textView else {
            return
        }
        Task {
            let report = await diagnosticEngine.diagnostics(for: document)
            await MainActor.run {
                textView.diagnostics = report.diagnostics.map(TextViewDiagnostic.init)
            }
        }
    }

    // MARK: - Setup

    private func installOverlayViews(on textView: TextView) {
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.isHidden = true
        textView.addSubview(overlayContainer)

        for view in [completionPanelView, hoverWindowView, ghostTextView, parameterHintsView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = true
            overlayContainer.addSubview(view)
        }

        NSLayoutConstraint.activate([
            overlayContainer.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            overlayContainer.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            overlayContainer.topAnchor.constraint(equalTo: textView.topAnchor),
            overlayContainer.bottomAnchor.constraint(equalTo: textView.bottomAnchor)
        ])
    }

    private func startObservingEvents() {
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in adapter.events {
                await MainActor.run {
                    self.handleEditorEvent(event)
                }
            }
        }
    }

    private func handleEditorEvent(_ event: EditorEvent) {
        switch event {
        case .documentChanged:
            refreshDiagnostics()
            if isCompletionVisible {
                requestCompletion(trigger: .idle)
            }
        case .cursorMoved, .selectionChanged:
            scheduleHoverRequest()
        case .documentOpened:
            refreshDiagnostics()
        default:
            break
        }
    }

    // MARK: - Completion

    private func requestCompletion(trigger: RequestTrigger) {
        guard let document = adapter.currentDocument else {
            return
        }
        let context = makeCompletionContext(document: document, trigger: trigger)
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await completionEngine.complete(context: context)
                await MainActor.run {
                    self.presentCompletion(items, replacementRange: context.range)
                }
            } catch {
                await MainActor.run {
                    self.hideCompletionPanel()
                }
            }
        }
    }

    private func presentCompletion(_ items: [CompletionItem], replacementRange: EditorIntelligence.TextRange) {
        guard !items.isEmpty, let textView else {
            hideCompletionPanel()
            return
        }
        completionItems = items
        selectedCompletionIndex = 0
        currentReplacementRange = replacementRange
        isCompletionVisible = true

        let model = CompletionPanelModel(
            items: items,
            selectedIndex: selectedCompletionIndex,
            replacementRange: replacementRange
        )
        completionPanelView.update(model: model)
        positionPanel(completionPanelView, near: replacementRange.end.utf16Offset, in: textView)
        completionPanelView.isHidden = false
        overlayContainer.isHidden = false

        if let first = items.first, first.insertText != first.label {
            showGhostText(first.insertText, at: replacementRange.end)
        }
    }

    private func hideCompletionPanel() {
        isCompletionVisible = false
        completionItems = []
        selectedCompletionIndex = 0
        currentReplacementRange = nil
        completionPanelView.isHidden = true
        hideGhostText()
        updateOverlayVisibility()
    }

    private func applyCompletion(_ item: CompletionItem, replacementRange: EditorIntelligence.TextRange) {
        guard let textView else {
            return
        }
        let nsRange = NSRange(
            location: replacementRange.start.utf16Offset,
            length: replacementRange.end.utf16Offset - replacementRange.start.utf16Offset
        )
        if item.kind == .snippet {
            let parser = SnippetParser()
            let nodes = parser.parse(item.insertText)
            let expander = SnippetExpander(
                nodes: nodes,
                context: SnippetExpansionContext(selectedText: textView.text(in: nsRange) ?? "")
            )
            let expansion = expander.expand()
            textView.replace(nsRange, withText: expansion.text)
        } else {
            textView.replace(nsRange, withText: item.insertText)
        }
    }

    private func moveCompletionSelection(delta: Int) {
        guard isCompletionVisible, !completionItems.isEmpty,
              let replacementRange = currentReplacementRange else {
            return
        }
        selectedCompletionIndex = (selectedCompletionIndex + delta + completionItems.count) % completionItems.count
        let model = CompletionPanelModel(
            items: completionItems,
            selectedIndex: selectedCompletionIndex,
            replacementRange: replacementRange
        )
        completionPanelView.update(model: model)
        let item = completionItems[selectedCompletionIndex]
        showGhostText(item.insertText, at: replacementRange.end)
    }

    // MARK: - Hover

    private func scheduleHoverRequest() {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                self.requestHover()
            }
        }
    }

    private func showHover(_ result: HoverResult, document: Document) {
        guard let textView else {
            return
        }
        let anchorRange = result.range ?? document.selection.range
        let model = HoverWindowModel(
            contents: result.contents,
            anchorRange: anchorRange,
            isMarkdown: true
        )
        hoverWindowView.update(model: model)
        positionPanel(hoverWindowView, near: anchorRange.start.utf16Offset, in: textView, size: NSSize(width: 280, height: 80))
        hoverWindowView.isHidden = false
        overlayContainer.isHidden = false
    }

    private func hideHover() {
        hoverWindowView.isHidden = true
        updateOverlayVisibility()
    }

    // MARK: - Ghost Text

    private func showGhostText(_ text: String, at position: TextPosition) {
        guard let textView else {
            return
        }
        let model = GhostTextModel(text: text, anchorPosition: position)
        ghostTextModel = model
        ghostTextView.update(model: model)
        positionPanel(ghostTextView, near: position.utf16Offset, in: textView, size: NSSize(width: 200, height: 20))
        ghostTextView.isHidden = false
        overlayContainer.isHidden = false
    }

    private func hideGhostText() {
        ghostTextModel = nil
        ghostTextView.isHidden = true
        updateOverlayVisibility()
    }

    // MARK: - Parameter Hints

    /// Show parameter hints anchored near the cursor.
    public func showParameterHints(_ model: ParameterHintsModel) {
        guard let textView, let document = adapter.currentDocument else {
            return
        }
        parameterHintsView.update(model: model)
        positionPanel(
            parameterHintsView,
            near: document.cursor.position.utf16Offset,
            in: textView,
            size: NSSize(width: 360, height: 28)
        )
        parameterHintsView.isHidden = false
        overlayContainer.isHidden = false
    }

    public func hideParameterHints() {
        parameterHintsView.isHidden = true
        updateOverlayVisibility()
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isCompletionVisible else {
            if event.keyCode == 0x35 {
                hideHover()
            }
            return false
        }

        switch event.keyCode {
        case 0x35:
            dismissCompletion()
            return true
        case 0x7D:
            moveCompletionSelection(delta: 1)
            return true
        case 0x7E:
            moveCompletionSelection(delta: -1)
            return true
        case 0x24, 0x4C:
            acceptSelectedCompletion()
            return true
        case 0x09 where !event.modifierFlags.contains(.shift):
            acceptSelectedCompletion()
            return true
        default:
            if let characters = event.characters, characters.count == 1,
               shouldTriggerCompletion(for: characters) {
                return false
            }
            return false
        }
    }

    private func shouldTriggerCompletion(for text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else {
            return false
        }
        return CharacterSet.alphanumerics.contains(scalar) || text == "." || text == ":"
    }

    func handleTextInsertion(_ text: String) {
        if shouldTriggerCompletion(for: text) {
            requestCompletion(trigger: .keystroke(text))
        } else if isCompletionVisible {
            dismissCompletion()
        }
    }

    // MARK: - Layout Helpers

    private func positionPanel(_ panel: NSView, near location: Int, in textView: TextView, size: NSSize = NSSize(width: 240, height: 120)) {
        let caretRect = textView.caretRect(for: IndexedPosition(index: location))
        let origin = CGPoint(
            x: caretRect.minX + textView.textContainerInset.left,
            y: caretRect.maxY + 4
        )
        panel.frame = CGRect(origin: origin, size: size)
    }

    private func updateOverlayVisibility() {
        let hasVisibleChild = !completionPanelView.isHidden
            || !hoverWindowView.isHidden
            || !ghostTextView.isHidden
            || !parameterHintsView.isHidden
        overlayContainer.isHidden = !hasVisibleChild
    }
}

// MARK: - Text change hook via forwarding delegate wrapper

/// Delegate wrapper that forwards editor callbacks to an intelligence controller.
@MainActor
public final class EditorIntelligenceForwardingDelegate: TextViewDelegate {
    private weak var controller: EditorIntelligenceController?
    public weak var userDelegate: TextViewDelegate?

    public init(userDelegate: TextViewDelegate? = nil) {
        self.userDelegate = userDelegate
    }

    func attach(controller: EditorIntelligenceController) {
        self.controller = controller
    }

  public func textViewDidChange(_ textView: TextView) {
    userDelegate?.textViewDidChange(textView)
  }

  public func textView(_ textView: TextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    let allowed = userDelegate?.textView(textView, shouldChangeTextIn: range, replacementText: text) ?? true
    if allowed, text.count == 1 {
      controller?.handleTextInsertion(text)
    }
    return allowed
  }

  public func textViewDidChangeSelection(_ textView: TextView) {
    userDelegate?.textViewDidChangeSelection(textView)
  }
}
