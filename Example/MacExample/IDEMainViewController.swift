import AppKit
import Combine
import SwiftUI

/// AppKit root shell: SwiftUI chrome via hosting views, Runestone editor as a native subview.
@MainActor
final class IDEMainViewController: NSViewController {
    private let workspace: IDEWorkspace
    private var cancellables = Set<AnyCancellable>()
    private var didBootstrap = false

    private let railView: UnfocusableHostingView<AnyView>
    private let sidebarView: UnfocusableHostingView<AnyView>
    private let tabsView: UnfocusableHostingView<AnyView>
    private let statusView: UnfocusableHostingView<AnyView>
    private let dividerView = NSView()
    private var sidebarWidthConstraint: NSLayoutConstraint?

    init(workspace: IDEWorkspace) {
        self.workspace = workspace
        railView = UnfocusableHostingView(rootView: AnyView(IDEActivityRailView().environmentObject(workspace)))
        sidebarView = UnfocusableHostingView(rootView: AnyView(IDESidebarPanel().environmentObject(workspace)))
        tabsView = UnfocusableHostingView(rootView: AnyView(IDEEditorTabsBar().environmentObject(workspace)))
        statusView = UnfocusableHostingView(rootView: AnyView(IDEStatusBarPanel().environmentObject(workspace)))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = IDERootView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(red: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255, alpha: 1).cgColor

        let mainRow = NSView()
        mainRow.translatesAutoresizingMaskIntoConstraints = false

        let editorColumn = NSView()
        editorColumn.translatesAutoresizingMaskIntoConstraints = false

        for view in [
            railView,
            sidebarView,
            dividerView,
            editorColumn,
            tabsView,
            workspace.layoutHost,
            statusView
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor(red: 0x3c / 255, green: 0x3c / 255, blue: 0x3c / 255, alpha: 1).cgColor

        editorColumn.addSubview(tabsView)
        editorColumn.addSubview(workspace.layoutHost)

        root.addSubview(mainRow)
        root.addSubview(statusView)
        mainRow.addSubview(railView)
        mainRow.addSubview(sidebarView)
        mainRow.addSubview(dividerView)
        mainRow.addSubview(editorColumn)

        let sidebarWidth = sidebarView.widthAnchor.constraint(equalToConstant: IDEAppearance.Spacing.sidebarWidth)
        sidebarWidthConstraint = sidebarWidth

        NSLayoutConstraint.activate([
            statusView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusView.heightAnchor.constraint(equalToConstant: IDEAppearance.Spacing.statusBarHeight),

            mainRow.topAnchor.constraint(equalTo: root.topAnchor),
            mainRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mainRow.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mainRow.bottomAnchor.constraint(equalTo: statusView.topAnchor),

            railView.topAnchor.constraint(equalTo: mainRow.topAnchor),
            railView.leadingAnchor.constraint(equalTo: mainRow.leadingAnchor),
            railView.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor),
            railView.widthAnchor.constraint(equalToConstant: IDEAppearance.Spacing.railWidth),

            sidebarView.topAnchor.constraint(equalTo: mainRow.topAnchor),
            sidebarView.leadingAnchor.constraint(equalTo: railView.trailingAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor),
            sidebarWidth,

            dividerView.topAnchor.constraint(equalTo: mainRow.topAnchor),
            dividerView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            dividerView.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 1),

            editorColumn.topAnchor.constraint(equalTo: mainRow.topAnchor),
            editorColumn.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            editorColumn.trailingAnchor.constraint(equalTo: mainRow.trailingAnchor),
            editorColumn.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor),

            tabsView.topAnchor.constraint(equalTo: editorColumn.topAnchor),
            tabsView.leadingAnchor.constraint(equalTo: editorColumn.leadingAnchor),
            tabsView.trailingAnchor.constraint(equalTo: editorColumn.trailingAnchor),
            tabsView.heightAnchor.constraint(equalToConstant: IDEAppearance.Spacing.tabHeight),

            workspace.layoutHost.topAnchor.constraint(equalTo: tabsView.bottomAnchor),
            workspace.layoutHost.leadingAnchor.constraint(equalTo: editorColumn.leadingAnchor),
            workspace.layoutHost.trailingAnchor.constraint(equalTo: editorColumn.trailingAnchor),
            workspace.layoutHost.bottomAnchor.constraint(equalTo: editorColumn.bottomAnchor)
        ])

        view = root
        applySidebarVisibility(workspace.isSidebarVisible)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !didBootstrap {
            didBootstrap = true
            workspace.bootstrap()
        }
        view.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        workspace.focusActiveEditor()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindWorkspace()
    }

    private func bindWorkspace() {
        workspace.$isSidebarVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                self?.applySidebarVisibility(isVisible)
            }
            .store(in: &cancellables)

        workspace.$windowTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                self?.view.window?.title = title
            }
            .store(in: &cancellables)

        workspace.$chromeOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] opacity in
                guard let self else { return }
                let alpha = CGFloat(opacity)
                self.railView.alphaValue = alpha
                self.sidebarView.alphaValue = alpha
                self.dividerView.alphaValue = alpha
                self.tabsView.alphaValue = alpha
                self.statusView.alphaValue = alpha
            }
            .store(in: &cancellables)
    }

    private func applySidebarVisibility(_ isVisible: Bool) {
        sidebarWidthConstraint?.constant = isVisible ? IDEAppearance.Spacing.sidebarWidth : 0
        sidebarView.isHidden = !isVisible
        dividerView.isHidden = !isVisible
    }
}

/// First click on an inactive window should both activate it and reach the editor.
private final class IDERootView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// `NSHostingView` reports `acceptsFirstResponder == true` whenever the SwiftUI graph
/// contains a `Button` (rail, tabs, sidebar). A `@Published` caret/status update then
/// makes AppKit move first responder onto the chrome, so the window looks unfocused
/// and the editor cannot be typed into.
private final class UnfocusableHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }

    override func becomeFirstResponder() -> Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct IDEMainViewControllerRepresentable: NSViewControllerRepresentable {
    let workspace: IDEWorkspace

    func makeNSViewController(context: Context) -> IDEMainViewController {
        IDEMainViewController(workspace: workspace)
    }

    func updateNSViewController(_ nsViewController: IDEMainViewController, context: Context) {}
}
