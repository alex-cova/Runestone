import EditorIntelligence
import Foundation

/// Pushes ``WorkbenchDocument`` snapshots into an EIP ``Workspace`` actor.
public final class RunestoneWorkbenchWorkspaceBridge: @unchecked Sendable {
    public let workspace: Workspace
    private var versions: [DocumentID: Int] = [:]

    public init(workspace: Workspace = Workspace()) {
        self.workspace = workspace
    }

    public func syncPane(_ pane: EditorPane) async {
        let openIDs = Set(pane.documents.map(\.documentID))
        for existing in await workspace.allOpenDocuments() {
            if !openIDs.contains(existing.id) {
                await workspace.closeDocument(existing.id)
                versions.removeValue(forKey: existing.id)
            }
        }
        for document in pane.documents {
            let version = (versions[document.documentID] ?? 0) + 1
            versions[document.documentID] = version
            let snapshot = document.makeEIPDocument(version: version)
            if await workspace.document(withID: document.documentID) != nil {
                await workspace.updateDocument(snapshot)
            } else {
                await workspace.openDocument(snapshot)
            }
        }
        if let selected = pane.selectedDocument {
            await workspace.activateDocument(selected.documentID)
        }
    }

    public func syncWorkbench(_ workbench: EditorWorkbench) async {
        for pane in workbench.panes {
            await syncPane(pane)
        }
    }
}
