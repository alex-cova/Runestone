import Foundation

/// A lightweight polling-based file-system watcher.
///
/// Replaced with a native FSEvents implementation in a later phase. This watcher is safe to use from
/// any actor because it runs its polling loop on a dedicated background task and exposes events via
/// `AsyncStream`.
public final class PollingFileSystemWatcher: FileSystemWatcher {
    public let url: URL
    public let interval: TimeInterval
    public var events: AsyncStream<FileSystemEvent> { eventBus.events }

    private let eventBus = EventBus<FileSystemEvent>()
    private var task: Task<Void, Never>?
    private var snapshot: [URL: Date] = [:]

    public init(url: URL, interval: TimeInterval = 2.0) {
        self.url = url
        self.interval = interval
    }

    deinit {
        task?.cancel()
    }

    public func start() async {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                self.scan()
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
    }

    private func scan() {
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var newSnapshot: [URL: Date] = [:]
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate else {
                continue
            }
            newSnapshot[fileURL] = date
            if let oldDate = snapshot[fileURL] {
                if oldDate != date {
                    eventBus.send(.fileChanged(fileURL))
                }
            } else {
                eventBus.send(.fileAdded(fileURL))
            }
        }
        for (oldURL, _) in snapshot where newSnapshot[oldURL] == nil {
            eventBus.send(.fileRemoved(oldURL))
        }
        snapshot = newSnapshot
    }
}
