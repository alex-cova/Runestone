import Foundation

/// Hover provider that translates LSP hover results into EIP hover results.
public actor LSPHoverProvider: HoverProvider {
    public let name = "LSP"
    private let client: LSPClient

    public init(client: LSPClient) {
        self.client = client
    }

    public func provide(context: HoverContext) async -> HoverResult? {
        do {
            let hover = try await client.requestHover(
                for: context.document,
                at: context.cursor.position
            )
            guard let hover = hover else { return nil }
            return HoverResult(
                contents: hover.contents,
                range: hover.range.map(textRange),
                source: name
            )
        } catch {
            return nil
        }
    }
}
