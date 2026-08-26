import Foundation

/// Events emitted by an editor adapter.
///
/// The EIP subscribes to these events to keep the workspace, index, and providers in sync.
public enum EditorEvent: Hashable, Sendable {
    case documentOpened(Document)
    case documentClosed(DocumentID)
    case documentChanged(DocumentID, TextSnapshot)
    /// Ranged edits plus a new content snapshot. Adapters emit this for typing; ``documentChanged``
    /// remains the full-replace fallback (reload, replace-all, `text =`).
    case documentEdited(DocumentID, [TextEdit], newSnapshot: TextSnapshot)
    case selectionChanged(DocumentID, Selection)
    case cursorMoved(DocumentID, Cursor)
    case viewportChanged(DocumentID, Viewport)
    case documentActivated(DocumentID)
}
