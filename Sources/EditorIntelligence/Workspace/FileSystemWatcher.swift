import Foundation

/// Event emitted by a file-system watcher.
public enum FileSystemEvent: Hashable, Sendable {
    case fileAdded(URL)
    case fileRemoved(URL)
    case fileChanged(URL)
}

/// Watches a directory on the file system and emits change events.
///
/// Implementations are platform-specific. The bundled `PollingFileSystemWatcher` is a simple
/// polling-based implementation suitable for the foundation; it should be replaced with a native
/// FSEvents/DispatchSource watcher as the platform matures.
public protocol FileSystemWatcher: AnyObject, Sendable {
    var events: AsyncStream<FileSystemEvent> { get }
    func start() async
    func stop() async
}
