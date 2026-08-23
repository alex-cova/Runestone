import Foundation

/// Debounces and offloads ``FindSearchEngine`` scans driven by a ``FindSession``, so query typing
/// and document edits don't block the main thread.
///
/// Staleness is guarded two ways: the debounce/search `Task`s are cancelled outright when a newer
/// request comes in, and the in-flight result is additionally checked against `isCurrent()` and
/// the session's `SearchSnapshot` before being applied — so a slow search for a query the user has
/// since changed (or a document the user has since navigated away from) never clobbers a newer
/// result.
@MainActor
public final class FindSearchScheduler {
    /// 200ms — matches the debounce interval most find-bar implementations settle on.
    public static let debounceNanoseconds: UInt64 = 200_000_000

    private var debounceTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    public init() {}

    public func cancel() {
        debounceTask?.cancel()
        searchTask?.cancel()
    }

    /// Schedules a search for `session`'s current query/options against `text`.
    /// - Parameters:
    ///   - immediate: Skips the debounce delay — use for e.g. showing the find bar with an
    ///     already-known query, where waiting would read as unresponsive.
    ///   - isCurrent: Checked before applying a result, in case the caller's context (active
    ///     document, visible panel, etc.) changed while the search was in flight. Defaults to
    ///     always current.
    ///   - apply: Called on the main actor after `session.applySearchOutcome(_:)` has already run.
    public func scheduleRefresh(
        session: FindSession,
        text: String,
        anchorLocation: Int,
        immediate: Bool = false,
        isCurrent: @escaping @MainActor () -> Bool = { true },
        apply: @escaping @MainActor () -> Void
    ) {
        debounceTask?.cancel()
        if immediate {
            runSearch(session: session, text: text, anchorLocation: anchorLocation, isCurrent: isCurrent, apply: apply)
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            runSearch(session: session, text: text, anchorLocation: anchorLocation, isCurrent: isCurrent, apply: apply)
        }
    }

    private func runSearch(
        session: FindSession,
        text: String,
        anchorLocation: Int,
        isCurrent: @escaping @MainActor () -> Bool,
        apply: @escaping @MainActor () -> Void
    ) {
        searchTask?.cancel()
        let snapshot = FindSession.SearchSnapshot(
            query: session.query,
            matchCase: session.matchCase,
            wholeWord: session.wholeWord,
            useRegex: session.useRegex
        )
        let searchText = text
        let anchor = anchorLocation

        if snapshot.query.isEmpty {
            guard isCurrent() else { return }
            session.applySearchOutcome(.empty)
            apply()
            return
        }

        searchTask = Task { @MainActor in
            let options = FindSearchOptions(
                query: snapshot.query,
                matchCase: snapshot.matchCase,
                wholeWord: snapshot.wholeWord,
                useRegex: snapshot.useRegex
            )
            let outcome = await Task.detached(priority: .userInitiated) {
                FindSearchEngine.search(options: options, in: searchText, anchorLocation: anchor)
            }.value

            guard !Task.isCancelled else { return }
            guard isCurrent(), session.matchesSnapshot(snapshot) else { return }

            session.applySearchOutcome(outcome)
            apply()
        }
    }
}
