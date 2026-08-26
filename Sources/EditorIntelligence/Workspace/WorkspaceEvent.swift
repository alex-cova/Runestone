import Foundation

/// Workspace-level events emitted by the `Workspace` actor.
public enum WorkspaceEvent: Hashable, Sendable {
    case projectAdded(Project)
    case projectRemoved(UUID)
    case documentOpened(Document)
    case documentClosed(DocumentID)
    case documentChanged(Document)
    /// Ranged edits applied to an open document. LSP should incremental-sync these;
    /// ``documentChanged`` is the full-document fallback.
    case documentEdited(Document, [TextEdit])
    case documentActivated(DocumentID)
    case workspaceChanged
}
