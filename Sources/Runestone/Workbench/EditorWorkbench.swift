import Foundation

/// Coordinates split editor layout and per-pane tab groups.
public final class EditorWorkbench: Identifiable {
    public let id: UUID
    public var layout: EditorLayout
    public var activePaneID: UUID

    public var panes: [EditorPane] {
        layout.flattenedPanes()
    }

    public var activePane: EditorPane {
        layout.findPane(id: activePaneID) ?? panes[0]
    }

    public init(id: UUID = UUID()) {
        let pane = EditorPane()
        self.id = id
        self.layout = .horizontal(EditorSplitData(axis: .horizontal, children: [.pane(pane)]))
        self.activePaneID = pane.id
    }

    public func activatePane(_ paneID: UUID) {
        guard layout.findPane(id: paneID) != nil else { return }
        activePaneID = paneID
    }

    public func openDocument(
        _ document: WorkbenchDocument,
        in pane: EditorPane? = nil,
        asTemporary: Bool = false
    ) {
        let target = pane ?? activePane
        target.openDocument(document, asTemporary: asTemporary)
    }

    public func allDocuments() -> [WorkbenchDocument] {
        var seen = Set<UUID>()
        var documents: [WorkbenchDocument] = []
        for pane in panes {
            for document in pane.documents where !seen.contains(document.id) {
                seen.insert(document.id)
                documents.append(document)
            }
        }
        return documents
    }

    @discardableResult
    public func splitActivePane(
        edge: EditorSplitEdge,
        newPane: EditorPane? = nil
    ) -> EditorPane {
        let pane = newPane ?? EditorPane()
        layout.splitPane(activePaneID, edge: edge, newPane: pane)
        activePaneID = pane.id
        return pane
    }

    public func closePane(_ paneID: UUID) {
        if activePaneID == paneID {
            if let replacement = layout.findSomePane(except: paneID) {
                activePaneID = replacement.id
            }
        }
        layout.closePane(paneID)
        layout.flatten()
        if panes.isEmpty {
            initCleanLayout()
        } else if layout.findPane(id: activePaneID) == nil {
            activePaneID = panes[0].id
        }
    }

    public func makeRestorationState() -> EditorRestorationState {
        EditorRestorationState(activePaneID: activePaneID, layout: EditorLayoutSnapshot(layout: layout))
    }

  public func restore(
        from state: EditorRestorationState,
        languageResolver: (WorkbenchDocumentSnapshot) -> TreeSitterLanguage? = { _ in nil }
    ) {
        layout = state.layout.makeLayout(languageResolver: languageResolver)
        layout.flatten()
        if layout.flattenedPanes().isEmpty {
            initCleanLayout()
            return
        }
        if let restoredActive = layout.findPane(id: state.activePaneID) {
            activePaneID = restoredActive.id
        } else if let fallback = layout.findSomePane() {
            activePaneID = fallback.id
        } else {
            initCleanLayout()
        }
    }

    public func initCleanLayout() {
        let pane = EditorPane()
        layout = .horizontal(EditorSplitData(axis: .horizontal, children: [.pane(pane)]))
        activePaneID = pane.id
    }
}
