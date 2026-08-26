import AppKit
import Runestone
import TestTreeSitterLanguages

/// Multi-tab, split-pane demo for the Runestone workbench module.
@main
struct MacExampleApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = MacExampleAppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class MacExampleAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var workbench = EditorWorkbench()
    private var workspaceBridge = RunestoneWorkbenchWorkspaceBridge()
    private var adapter: RunestoneWorkbenchEditorAdapter!
    private var layoutHost: EditorLayoutHostView!
    private var toolbar: NSStackView!
    private var paneHosts: [UUID: PaneHost] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let jsLanguage = makeJavaScriptLanguage()
        let docA = WorkbenchDocument(
            displayName: "sample.js",
            text: "function greet(name) {\n  return `Hello, ${name}`\n}\n",
            language: jsLanguage,
            languageIdentifier: "javascript"
        )
        let docB = WorkbenchDocument(
            displayName: "notes.txt",
            text: "Second tab — switch without re-parsing when warm.\n"
        )
        workbench.openDocument(docA)
        workbench.openDocument(docB)

        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Runestone MacExample"
        window.center()

        let root = NSView(frame: window.contentView?.bounds ?? CGRect(x: 0, y: 0, width: 960, height: 640))
        root.autolayout()

        toolbar = makeToolbar()
        layoutHost = EditorLayoutHostView()
        layoutHost.autolayout()

        root.addSubview(toolbar)
        root.addSubview(layoutHost)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -8),
            layoutHost.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            layoutHost.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            layoutHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            layoutHost.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        adapter = RunestoneWorkbenchEditorAdapter(workbench: workbench)
        adapter.forwardingDelegate = self
        layoutHost.onPaneActivated = { [weak self] paneID in
            self?.activatePane(paneID)
        }
        rebuildLayoutHosts()
        activatePane(workbench.activePaneID)

        window.contentView = root
        window.makeKeyAndOrderFront(nil)

        if let index = CommandLine.arguments.firstIndex(of: "--open"),
           index + 1 < CommandLine.arguments.count {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { await self.openDocument(from: url) }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)

        Task {
            await workspaceBridge.syncWorkbench(workbench)
            await workspaceBridge.workspace.connect(to: adapter)
        }
    }

    private func makeToolbar() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.autolayout()

        let splitRight = NSButton(title: "Split Right", target: self, action: #selector(splitRight))
        splitRight.bezelStyle = .rounded
        let openFile = NSButton(title: "Open…", target: self, action: #selector(openFile))
        openFile.bezelStyle = .rounded
        let splitDown = NSButton(title: "Split Down", target: self, action: #selector(splitDown))
        splitDown.bezelStyle = .rounded
        let closePane = NSButton(title: "Close Pane", target: self, action: #selector(closeActivePane))
        closePane.bezelStyle = .rounded
        let typewriter = NSButton(title: "Typewriter", target: self, action: #selector(toggleTypewriterScrolling))
        typewriter.bezelStyle = .rounded
        typewriter.setButtonType(.toggle)
        let focus = NSSegmentedControl(
            labels: ["Focus Off", "Sentence", "Paragraph"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeFocusMode(_:))
        )
        focus.selectedSegment = 0
        let distractionFree = NSButton(
            title: "Distraction Free",
            target: self,
            action: #selector(toggleDistractionFreeMode(_:))
        )
        distractionFree.bezelStyle = .rounded
        distractionFree.setButtonType(.toggle)

        stack.addArrangedSubview(openFile)
        stack.addArrangedSubview(splitRight)
        stack.addArrangedSubview(splitDown)
        stack.addArrangedSubview(closePane)
        stack.addArrangedSubview(focus)
        stack.addArrangedSubview(typewriter)
        stack.addArrangedSubview(distractionFree)
        return stack
    }

    @objc private func changeFocusMode(_ sender: NSSegmentedControl) {
        guard let textView = adapter.textView else { return }
        switch sender.selectedSegment {
        case 1:
            textView.focusGranularity = .sentence
            textView.isFocusModeEnabled = true
        case 2:
            textView.focusGranularity = .paragraph
            textView.isFocusModeEnabled = true
        default:
            textView.isFocusModeEnabled = false
        }
    }

    @objc private func toggleTypewriterScrolling(_ sender: NSButton) {
        guard let textView = adapter.textView else { return }
        textView.isTypewriterScrollingEnabled = sender.state == .on
        if textView.isTypewriterScrollingEnabled {
            textView.isAutomaticScrollEnabled = true
        }
    }

    @objc private func toggleDistractionFreeMode(_ sender: NSButton) {
        adapter.textView?.isDistractionFreeModeEnabled = sender.state == .on
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            Task { await self.openDocument(from: url) }
        }
    }

    private func openDocument(from url: URL) async {
        do {
            let language = url.pathExtension == "js" || url.pathExtension == "mjs" ? makeJavaScriptLanguage() : nil
            let document = try await WorkbenchDocument.load(
                contentsOf: url,
                language: language,
                languageIdentifier: language == nil ? nil : "javascript"
            )
            workbench.openDocument(document)
            rebuildLayoutHosts()
            activatePane(workbench.activePaneID)
            await workspaceBridge.syncWorkbench(workbench)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func splitRight() {
        workbench.splitActivePane(edge: .trailing)
        rebuildLayoutHosts()
        activatePane(workbench.activePaneID)
        Task { await workspaceBridge.syncWorkbench(workbench) }
    }

    @objc private func splitDown() {
        workbench.splitActivePane(edge: .bottom)
        rebuildLayoutHosts()
        activatePane(workbench.activePaneID)
        Task { await workspaceBridge.syncWorkbench(workbench) }
    }

    @objc private func closeActivePane() {
        let closingID = workbench.activePaneID
        workbench.closePane(closingID)
        paneHosts.removeValue(forKey: closingID)
        rebuildLayoutHosts()
        activatePane(workbench.activePaneID)
        Task { await workspaceBridge.syncWorkbench(workbench) }
    }

    private func rebuildLayoutHosts() {
        paneHosts = layoutHost.configure(
            layout: workbench.layout,
            existingHosts: paneHosts,
            makeHost: { pane in
                let host = PaneHost(pane: pane)
                host.onTabSelected = { [weak self] documentID in
                    guard let self else { return }
                    pane.selectDocument(documentID)
                    self.showDocument(in: pane, host: host)
                    self.rebuildTabBars()
                    Task { await self.workspaceBridge.syncPane(pane) }
                }
                return host
            }
        )
        rebuildTabBars()
        for pane in workbench.panes {
            if let host = paneHosts[pane.id], let document = pane.selectedDocument {
                showDocument(in: pane, host: host, reloadOnlyIfNeeded: true)
            }
        }
        updatePaneDimming()
    }

    private func rebuildTabBars() {
        for pane in workbench.panes {
            guard let host = paneHosts[pane.id] else { continue }
            host.rebuildTabBar(
                documents: pane.documents,
                selectedID: pane.selectedDocumentID
            )
        }
    }

    private func activatePane(_ paneID: UUID) {
        workbench.activatePane(paneID)
        guard let host = paneHosts[paneID] else { return }
        adapter.textView = host.textView
        host.textView.editorDelegate = adapter
        showDocument(in: workbench.activePane, host: host)
        updatePaneDimming()
        adapter.refreshCachedDocuments()
        Task { await workspaceBridge.syncPane(workbench.activePane) }
    }

    private func updatePaneDimming() {
        for (paneID, host) in paneHosts {
            host.setDimmed(paneID != workbench.activePaneID)
        }
    }

    private func showDocument(
        in pane: EditorPane,
        host: PaneHost,
        reloadOnlyIfNeeded: Bool = false
    ) {
        guard let document = pane.selectedDocument else { return }
        if reloadOnlyIfNeeded, host.loadedDocumentID == document.id {
            return
        }
        if let state = document.pendingState {
            document.pendingState = nil
            host.applyGate.bump()
            host.textView.setState(state)
            host.textView.selectedRange = document.selectedRange
            if document.scrollOffset != .zero {
                host.textView.contentOffset = document.scrollOffset
            }
            host.loadedDocumentID = document.id
            if pane.id == workbench.activePaneID {
                adapter.refreshCachedDocuments()
            }
            return
        }
        let generation = host.applyGate.bump()
        RunestoneStateBuilder.prepareAndApply(
            text: document.text,
            theme: DefaultTheme(),
            language: document.language,
            generation: generation,
            isCurrent: { [host] gen in host.applyGate.matches(gen) },
            apply: { [weak self, weak host] state in
                guard let self, let host else { return }
                host.textView.setState(state)
                host.textView.selectedRange = document.selectedRange
                if document.scrollOffset != .zero {
                    host.textView.contentOffset = document.scrollOffset
                }
                host.loadedDocumentID = document.id
                if pane.id == self.workbench.activePaneID {
                    self.adapter.refreshCachedDocuments()
                }
            }
        )
    }
}

extension MacExampleAppDelegate: TextViewDelegate {
    func textView(_ textView: TextView,
                  didChangeDistractionFreeChromeVisibility isVisible: Bool,
                  transitionDuration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            toolbar.animator().alphaValue = isVisible ? 1 : 0
        }
    }
}

// MARK: - Pane host

final class PaneHost: NSView {
    let pane: EditorPane
    let textView: TextView
    let tabBar: NSStackView
    let applyGate = RunestoneStateBuilder.GenerationGate()
    var loadedDocumentID: UUID?
    var onTabSelected: ((UUID) -> Void)?

    init(pane: EditorPane) {
        self.pane = pane
        tabBar = NSStackView()
        tabBar.orientation = .horizontal
        tabBar.spacing = 4
        tabBar.autolayout()
        textView = TextView()
        textView.autolayout()
        textView.theme = DefaultTheme()
        super.init(frame: .zero)
        autolayout()
        addSubview(tabBar)
        addSubview(textView)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            textView.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 4),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(paneClicked))
        addGestureRecognizer(click)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func paneClicked() {
        onPaneActivated?()
    }

    var onPaneActivated: (() -> Void)?

    func setDimmed(_ dimmed: Bool) {
        alphaValue = dimmed ? 0.55 : 1.0
    }

    func rebuildTabBar(documents: [WorkbenchDocument], selectedID: UUID?) {
        tabBar.arrangedSubviews.forEach { view in
            tabBar.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for document in documents {
            let button = NSButton(title: document.displayName, target: self, action: #selector(tabClicked(_:)))
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier(document.id.uuidString)
            if document.id == selectedID {
                button.contentTintColor = .controlAccentColor
            }
            tabBar.addArrangedSubview(button)
        }
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let uuid = UUID(uuidString: raw)
        else { return }
        onTabSelected?(uuid)
    }
}

// MARK: - Layout host

final class EditorLayoutHostView: NSView {
    var onPaneActivated: ((UUID) -> Void)?

    func configure(
        layout: EditorLayout,
        existingHosts: [UUID: PaneHost],
        makeHost: (EditorPane) -> PaneHost
    ) -> [UUID: PaneHost] {
        subviews.forEach { $0.removeFromSuperview() }
        var hosts: [UUID: PaneHost] = [:]

        func host(for pane: EditorPane) -> PaneHost {
            if let existing = existingHosts[pane.id] {
                hosts[pane.id] = existing
                existing.onPaneActivated = { [weak self] in
                    self?.onPaneActivated?(pane.id)
                }
                return existing
            }
            let created = makeHost(pane)
            created.onPaneActivated = { [weak self] in
                self?.onPaneActivated?(pane.id)
            }
            hosts[pane.id] = created
            return created
        }

        let built = buildView(for: layout, hostForPane: host)
        built.autolayout()
        addSubview(built)
        NSLayoutConstraint.activate([
            built.topAnchor.constraint(equalTo: topAnchor),
            built.leadingAnchor.constraint(equalTo: leadingAnchor),
            built.trailingAnchor.constraint(equalTo: trailingAnchor),
            built.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        return hosts
    }

    private func buildView(
        for layout: EditorLayout,
        hostForPane: (EditorPane) -> PaneHost
    ) -> NSView {
        switch layout {
        case .pane(let pane):
            return hostForPane(pane)
        case .vertical(let data):
            let split = NSSplitView()
            split.isVertical = true
            split.dividerStyle = .thin
            split.autolayout()
            for child in data.children {
                let childView = buildView(for: child, hostForPane: hostForPane)
                split.addArrangedSubview(childView)
            }
            return split
        case .horizontal(let data):
            let split = NSSplitView()
            split.isVertical = false
            split.dividerStyle = .thin
            split.autolayout()
            for child in data.children {
                let childView = buildView(for: child, hostForPane: hostForPane)
                split.addArrangedSubview(childView)
            }
            return split
        }
    }
}

// MARK: - Helpers

private extension NSView {
    func autolayout() {
        translatesAutoresizingMaskIntoConstraints = false
    }
}

private func makeJavaScriptLanguage() -> TreeSitterLanguage {
    TreeSitterLanguage(tree_sitter_javascript())
}
