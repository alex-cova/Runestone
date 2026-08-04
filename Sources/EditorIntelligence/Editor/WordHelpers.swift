import Foundation

/// Extract the word at the given UTF-16 offset in a string.
///
/// A word character is a letter, digit, or underscore. Returns the empty string if the offset is
/// out of bounds or no word characters surround it.
public func word(at offset: Int, in text: String) -> String {
    let utf16 = text.utf16
    let clampedOffset = max(0, min(offset, utf16.count))
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
