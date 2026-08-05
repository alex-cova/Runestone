import Foundation

/// A provider that returns hover/documentation information for a given editor context.
public protocol HoverProvider: Sendable {
    /// Human-readable provider name, used for tracing.
    var name: String { get }

    /// Produce a hover result for the given context, or `nil` if the provider has no information.
    func provide(context: HoverContext) async -> HoverResult?
}
