import Foundation

/// Model that generates text from a prompt. Concrete implementations can wrap local or remote AI.
public protocol AITextModel: Sendable {
    /// Generate text for the given prompt.
    func generate(prompt: String) async throws -> String
}
