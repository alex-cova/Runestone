import Foundation

/// Maps LSP semantic token type and modifier indices to highlight capture names.
public struct SemanticTokenMap: Sendable {
    private let tokenTypes: [String]
    private let tokenModifiers: [String]

    public init(tokenTypes: [String], tokenModifiers: [String]) {
        self.tokenTypes = tokenTypes
        self.tokenModifiers = tokenModifiers
    }

    public func highlightName(for token: LSPSemanticToken) -> String {
        let base = tokenTypes.indices.contains(token.typeIndex) ? tokenTypes[token.typeIndex] : "variable"
        return base
    }

    public func modifiers(for token: LSPSemanticToken) -> [String] {
        var result: [String] = []
        var raw = token.modifiers
        while raw > 0 {
            let index = raw.trailingZeroBitCount
            raw &= ~(1 << index)
            if tokenModifiers.indices.contains(index) {
                result.append(tokenModifiers[index])
            }
        }
        return result
    }
}
