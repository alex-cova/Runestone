import Foundation

/// Workspace-level events emitted by the `Workspace` actor.
public enum WorkspaceEvent: Hashable, Sendable {
    case projectAdded(Project)
    case projectRemoved(UUID)
    case documentOpened(Document)
    case documentClosed(DocumentID)
    case documentChanged(Document)
    case documentActivated(DocumentID)
    case workspaceChanged
}
