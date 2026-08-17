import Foundation

/// Stores semantic token data and supports delta updates from language servers.
public final class SemanticTokenStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var resultId: String?
    private var compressedData: [UInt32] = []
    private var tokens: [LSPSemanticToken] = []

    public init() {}

    public var lastResultId: String? {
        lock.withLock { resultId }
    }

    public var hasReceivedData: Bool {
        lock.withLock { !tokens.isEmpty }
    }

    public func setData(_ semanticTokens: LSPSemanticTokens) {
        lock.withLock {
            resultId = semanticTokens.resultId
            compressedData = semanticTokens.data
            tokens = LSPSemanticTokenDecoder.decode(semanticTokens.data)
        }
    }

    public func applyDelta(_ delta: LSPSemanticTokensDelta) -> [LSPSemanticToken] {
        lock.withLock {
            resultId = delta.resultId
            if !delta.data.isEmpty {
                compressedData.append(contentsOf: delta.data)
                tokens = LSPSemanticTokenDecoder.decode(compressedData)
            }
            return tokens
        }
    }

    public func tokens(in range: LSPRange) -> [LSPSemanticToken] {
        lock.withLock {
            tokens.filter { token in
                let start = LSPPosition(line: token.line, character: token.character)
                let end = LSPPosition(line: token.line, character: token.character + token.length)
                return start.line < range.end.line
                    || (start.line == range.end.line && start.character < range.end.character)
            }.filter { token in
                let start = LSPPosition(line: token.line, character: token.character)
                return start.line > range.start.line
                    || (start.line == range.start.line && start.character >= range.start.character)
            }
        }
    }

    public func allTokens() -> [LSPSemanticToken] {
        lock.withLock { tokens }
    }
}
