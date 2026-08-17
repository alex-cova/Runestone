import Foundation

/// Coordinates one or more ``EditorPane`` instances. Phase 3 adds split layout trees.
public final class EditorWorkbench: Identifiable {
    public let id: UUID
    public var panes: [EditorPane]
    public var activePaneID: UUID

    public var activePane: EditorPane {
        panes.first { $0.id == activePaneID } ?? panes[0]
    }

    public init(id: UUID = UUID()) {
        let pane = EditorPane()
        self.id = id
        self.panes = [pane]
        self.activePaneID = pane.id
    }

    public func openDocument(_ document: WorkbenchDocument, in pane: EditorPane? = nil, asTemporary: Bool = false) {
        let target = pane ?? activePane
        target.openDocument(document, asTemporary: asTemporary)
    }

    public func allDocuments() -> [WorkbenchDocument] {
        panes.flatMap(\.documents)
    }
}
