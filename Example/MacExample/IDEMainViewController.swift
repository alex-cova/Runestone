import AppKit
import Combine
import SwiftUI

/// AppKit root shell: SwiftUI chrome via hosting controllers, Runestone editor as a native subview.
@MainActor
final class IDEMainViewController: NSViewController {
    private let workspace: IDEWorkspace
    private var cancellables = Set<AnyCancellable>()
    private var didBootstrap = false

    private let railHosting: NSHostingController<AnyView>
    private let sidebarHosting: NSHostingController<AnyView>
    private let tabsHosting: NSHostingController<AnyView>
    private let statusHosting: NSHostingController<AnyView>
    private let dividerView = NSView()
    private var sidebarWidthConstraint: NSLayoutConstraint?

    init(workspace: IDEWorkspace) {
        self.workspace = workspace
        railHosting = NSHostingController(rootView: AnyView(IDEActivityRailView().environmentObject(workspace)))
        sidebarHosting = NSHostingController(rootView: AnyView(IDESidebarPanel().environmentObject(workspace)))
        tabsHosting = NSHostingController(rootView: AnyView(IDEEditorTabsBar().environmentObject(workspace)))
        statusHosting = NSHostingController(rootView: AnyView(IDEStatusBarPanel().environmentObject(workspace)))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(red: 0x1e / 255, green: 0x1e / 255, blue: 0x1e / 255, alpha: 1).cgColor

        let mainRow = NSView()
        mainRow.translatesAutoresizingMaskIntoConstraints = false

        let editorColumn = NSView()
        editorColumn.translatesAutoresizingMaskIntoConstraints = false

        for view in [
            railHosting.view,
            sidebarHosting.view,
            dividerView,
            editorColumn,
            tabsHosting.view,
            workspace.layoutHost,
            statusHosting.view
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor(red: 0x3c / 255, green: 0x3c / 255, blue: 0x3c / 255, alpha: 1).cgColor

        editorColumn.addSubview(tabsHosting.view)
        editorColumn.addSubview(workspace.layoutHost)

        root.addSubview(mainRow)
        root.addSubview(statusHosting.view)
        mainRow.addSubview(railHosting.view)
        mainRow.addSubview(sidebarHosting.view)
        mainRow.addSubview(dividerView)
        mainRow.addSubview(editorColumn)

        let sidebarWidth = sidebarHosting.view.widthAnchor.constraint(equalToConstant: IDEAppearance.Spacing.sidebarWidth)
        sidebarWidthConstraint = sidebarWidth

        NSLayoutConstraint.activate([
            statusHosting.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusHosting.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusHosting.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusHosting.view.heightAnchor.constraint(equalToConstant: IDEAppearance.Spacing.statusBarHeight),

            mainRow.topAnchor.constraint(equalTo: root.topAnchor),
            mainRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mainRow.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mainRow.bottomAnchor.constraint(equalTo: statusHosting.view.topAnchor),

            railHosting.view.topAnchor.constraint(equalTo: mainRow.topAnchor),
            railHosting.view.leadingAnchor.constraint(equalTo: mainRow.leadingAnchor),
            railHosting.view.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor),
            railHosting.view.widthAnchor.constraint(equalToConstant: IDEAppearance.Spacing.railWidth),

            sidebarHosting.view.topAnchor.constraint(equalTo: mainRow.topAnchor),
            sidebarHosting.view.leadingAnchor.constraint(equalTo: railHosting.view.trailingAnchor),
            sidebarHosting.view.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor),
            sidebarWidth,

            dividerView.topAnchor.constraint(equalTo: mainRow.topAnchor),
            dividerView.leadingAnchor.constraint(equalTo: sidebarHosting.view.trailingAnchor),
            dividerView.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 1),

            editorColumn.topAnchor.constraint(equalTo: mainRow.topAnchor),
            editorColumn.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            editorColumn.trailingAnchor.constraint(equalTo: mainRow.trailingAnchor),
            editorColumn.bottomAnchor.constraint(equalTo: mainRow.bottomAnchor),

            tabsHosting.view.topAnchor.constraint(equalTo: editorColumn.topAnchor),
            tabsHosting.view.leadingAnchor.constraint(equalTo: editorColumn.leadingAnchor),
            tabsHosting.view.trailingAnchor.constraint(equalTo: editorColumn.trailingAnchor),
            tabsHosting.view.heightAnchor.constraint(equalToConstant: IDEAppearance.Spacing.tabHeight),

            workspace.layoutHost.topAnchor.constraint(equalTo: tabsHosting.view.bottomAnchor),
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
                self.railHosting.view.alphaValue = alpha
                self.sidebarHosting.view.alphaValue = alpha
                self.dividerView.alphaValue = alpha
                self.tabsHosting.view.alphaValue = alpha
                self.statusHosting.view.alphaValue = alpha
            }
            .store(in: &cancellables)
    }

    private func applySidebarVisibility(_ isVisible: Bool) {
        sidebarWidthConstraint?.constant = isVisible ? IDEAppearance.Spacing.sidebarWidth : 0
        sidebarHosting.view.isHidden = !isVisible
        dividerView.isHidden = !isVisible
    }
}

struct IDEMainViewControllerRepresentable: NSViewControllerRepresentable {
    let workspace: IDEWorkspace

    func makeNSViewController(context: Context) -> IDEMainViewController {
        IDEMainViewController(workspace: workspace)
    }

    func updateNSViewController(_ nsViewController: IDEMainViewController, context: Context) {}
}
