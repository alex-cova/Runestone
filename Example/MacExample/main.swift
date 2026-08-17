import AppKit
import Runestone
import TestTreeSitterLanguages

/// Minimal multi-tab demo for the Runestone workbench module.
@main
struct MacExampleApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = MacExampleAppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class MacExampleAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var workbench = EditorWorkbench()
    private var workspaceBridge = RunestoneWorkbenchWorkspaceBridge()
    private var adapter: RunestoneWorkbenchEditorAdapter!
    private var textView: TextView!
    private var tabBar: NSStackView!
    private var applyGate = RunestoneStateBuilder.GenerationGate()

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
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Runestone MacExample"
        window.center()

        let root = NSView(frame: window.contentView?.bounds ?? CGRect(x: 0, y: 0, width: 900, height: 600))
        root.autoresizingMask = [.width, .height]

        tabBar = NSStackView()
        tabBar.orientation = .horizontal
        tabBar.spacing = 4
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        textView = TextView(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.theme = DefaultTheme()

        adapter = RunestoneWorkbenchEditorAdapter(workbench: workbench, textView: textView)
        Task {
            await workspaceBridge.syncWorkbench(workbench)
            await workspaceBridge.workspace.connect(to: adapter)
        }

        root.addSubview(tabBar)
        root.addSubview(textView)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -8),
            textView.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        window.contentView = root
        rebuildTabBar()
        showSelectedDocument()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func rebuildTabBar() {
        tabBar.arrangedSubviews.forEach { view in
            tabBar.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for document in workbench.activePane.documents {
            let button = NSButton(title: document.displayName, target: self, action: #selector(tabClicked(_:)))
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier(document.id.uuidString)
            if document.id == workbench.activePane.selectedDocumentID {
                button.contentTintColor = .controlAccentColor
            }
            tabBar.addArrangedSubview(button)
        }
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let uuid = UUID(uuidString: raw)
        else { return }
        workbench.activePane.selectDocument(uuid)
        showSelectedDocument()
        rebuildTabBar()
        Task { await workspaceBridge.syncPane(workbench.activePane) }
    }

    private func showSelectedDocument() {
        guard let document = workbench.activePane.selectedDocument else { return }
        let generation = applyGate.bump()
        RunestoneStateBuilder.prepareAndApply(
            text: document.text,
            theme: DefaultTheme(),
            language: document.language,
            generation: generation,
            isCurrent: { [applyGate] gen in applyGate.matches(gen) },
            apply: { [weak self] state in
                guard let self else { return }
                self.textView.setState(state)
                self.textView.selectedRange = document.selectedRange
                if document.scrollOffset != .zero {
                    self.textView.contentOffset = document.scrollOffset
                }
                self.adapter.refreshCachedDocuments()
            }
        )
    }
}

private func makeJavaScriptLanguage() -> TreeSitterLanguage {
    TreeSitterLanguage(tree_sitter_javascript())
}
