import Foundation

/// Decodes LSP semantic token `data` arrays into ``LSPSemanticToken`` values.
public enum LSPSemanticTokenDecoder {
    public static func decode(_ data: [UInt32]) -> [LSPSemanticToken] {
        guard data.count >= 5 else {
            return []
        }
        var tokens: [LSPSemanticToken] = []
        var line = 0
        var character = 0
        var index = 0
        while index + 5 <= data.count {
            let deltaLine = Int(data[index])
            let deltaChar = Int(data[index + 1])
            let length = Int(data[index + 2])
            let typeIndex = Int(data[index + 3])
            let modifiers = data[index + 4]
            if deltaLine == 0 {
                character += deltaChar
            } else {
                line += deltaLine
                character = deltaChar
            }
            tokens.append(LSPSemanticToken(
                line: line,
                character: character,
                length: length,
                typeIndex: typeIndex,
                modifiers: modifiers
            ))
            index += 5
        }
        return tokens
    }
}
