import Foundation

/// A provider that resolves navigation requests for a given editor context.
public protocol NavigationProvider: Sendable {
    /// Human-readable provider name, used for tracing.
    var name: String { get }

    /// Produce a navigation result for the given context, or `nil` if the provider has no match.
    func provide(context: NavigationContext) async -> NavigationResult?
}
