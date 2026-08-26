import Foundation

/// Completion provider that delegates to an `AITextModel`.
public actor AICompletionProvider: CompletionProvider {
    public let name = "AI"
    private let model: AITextModel
    private let promptBuilder: (@Sendable (CompletionContext) -> String)?

    public init(
        model: AITextModel,
        promptBuilder: (@Sendable (CompletionContext) -> String)? = nil
    ) {
        self.model = model
        self.promptBuilder = promptBuilder
    }

    public func provide(context: CompletionContext) async -> [CompletionItem] {
        let prompt = promptBuilder?(context) ?? defaultPrompt(for: context)
        do {
            let text = try await model.generate(prompt: prompt)
            guard !text.isEmpty else { return [] }
            return [CompletionItem(
                label: "AI Suggestion",
                insertText: text,
                kind: .text,
                range: context.range,
                source: name,
                documentation: nil
            )]
        } catch {
            return []
        }
    }

    private func defaultPrompt(for context: CompletionContext) -> String {
        "Complete the following code at cursor position \(context.cursor.position):\n\n\(context.document.textAroundCursor())"
    }
}
