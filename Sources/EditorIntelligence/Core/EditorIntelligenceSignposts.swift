import os

/// Instruments intervals named in PERFORMANCE_AUDIT.md Phase 5 §4 for EIP services.
enum EditorIntelligenceSignposts {
    static let performance = OSSignposter(subsystem: "EditorIntelligence", category: "Performance")

    @inline(__always)
    static func interval<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = performance.beginInterval(name)
        defer { performance.endInterval(name, state) }
        return try await work()
    }
}
