import Foundation

/// Hover provider that delegates to an `AITextModel`.
public actor AIHoverProvider: HoverProvider {
    public let name = "AI"
    private let model: AITextModel
    private let promptBuilder: (@Sendable (HoverContext) -> String)?

    public init(
        model: AITextModel,
        promptBuilder: (@Sendable (HoverContext) -> String)? = nil
    ) {
        self.model = model
        self.promptBuilder = promptBuilder
    }

    public func provide(context: HoverContext) async -> HoverResult? {
        let prompt = promptBuilder?(context) ?? defaultPrompt(for: context)
        do {
            let text = try await model.generate(prompt: prompt)
            guard !text.isEmpty else { return nil }
            return HoverResult(
                contents: text,
                range: context.selection.range,
                source: name
            )
        } catch {
            return nil
        }
    }

    private func defaultPrompt(for context: HoverContext) -> String {
        "Explain the following code at \(context.cursor.position):\n\n\(context.document.textAroundCursor())"
    }
}
