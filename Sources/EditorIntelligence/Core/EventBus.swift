import Foundation

/// A typed event bus built on `AsyncSequence`.
///
/// Producers call `send(_:)` to broadcast events. Consumers iterate over the `events` stream.
/// The bus supports multiple concurrent subscribers and delivers events in FIFO order.
///
/// Continuations are guarded by `lock`. `@unchecked Sendable` lets actor-isolated owners expose
/// the bus as `nonisolated let` without hopping for subscribe/send.
public final class EventBus<Event: Sendable>: @unchecked Sendable {
    private var continuations: [AsyncStream<Event>.Continuation] = []
    private let lock = NSLock()

    public init() {}

    deinit {
        lock.withLock {
            for continuation in continuations {
                continuation.finish()
            }
        }
    }

    /// Create a new async sequence of events.
    ///
    /// Each call returns a separate stream so multiple subscribers can receive every event.
    public var events: AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        lock.withLock { continuations.append(continuation) }
        return stream
    }

    /// Broadcast an event to all subscribers.
    public func send(_ event: Event) {
        lock.withLock {
            for continuation in continuations {
                continuation.yield(event)
            }
        }
    }

    /// Finish all streams and stop accepting new events.
    public func finish() {
        lock.withLock {
            for continuation in continuations {
                continuation.finish()
            }
            continuations.removeAll()
        }
    }
}
