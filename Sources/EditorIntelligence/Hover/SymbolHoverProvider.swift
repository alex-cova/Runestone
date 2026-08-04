import Foundation

/// Hover provider that looks up the word at the cursor in the symbol index and returns its
/// documentation or signature as Markdown.
public actor SymbolHoverProvider: HoverProvider {
    public let name = "Symbol"
    private let index: SymbolIndex

    public init(index: SymbolIndex) {
        self.index = index
    }

    public func provide(context: HoverContext) async -> HoverResult? {
        let word = currentWord(at: context.cursor.position, in: context.document.text)
        guard !word.isEmpty else { return nil }
        let symbols = await index.search(exact: word)
        guard let symbol = symbols.first else { return nil }
        let contents = symbol.documentation ?? symbol.signature ?? symbol.name
        return HoverResult(
            contents: contents,
            range: symbol.range,
            source: name
        )
    }
}

private func currentWord(at position: TextPosition, in text: String) -> String {
    let utf16 = text.utf16
    let clampedOffset = max(0, min(position.utf16Offset, utf16.count))
    guard let index = utf16.index(utf16.startIndex, offsetBy: clampedOffset, limitedBy: utf16.endIndex) else {
        return ""
    }
    let stringIndex = index.samePosition(in: text) ?? text.index(text.startIndex, offsetBy: clampedOffset)
    var start = stringIndex
    var end = stringIndex
    while start > text.startIndex, text[text.index(before: start)].isWordCharacter {
        start = text.index(before: start)
    }
    while end < text.endIndex, text[end].isWordCharacter {
        end = text.index(after: end)
    }
    return String(text[start..<end])
}

private extension Character {
    var isWordCharacter: Bool {
        isLetter || isNumber || self == "_"
    }
}
