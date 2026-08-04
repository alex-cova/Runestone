import Foundation
import AppKit
#if DEBUG
private var previousUnrecognizedHighlightNames: [String] = []
#endif

enum HighlightName: String {
    case boolean
    case comment
    case constantBuiltin = "constant.builtin"
    case constantCharacter = "constant.character"
    case constructor
    case float
    case function
    case keyword
    case number
    case `operator`
    case parameter
    case property
    case punctuation
    case punctuationBracket = "punctuation.bracket"
    case punctuationDelimiter = "punctuation.delimiter"
    case punctuationSpecial = "punctuation.special"
    case string
    case type
    case typeBuiltin = "type.builtin"
    case variable
    case variableBuiltin = "variable.builtin"

    init?(_ rawHighlightName: String) {
        var comps = rawHighlightName.split(separator: ".")
        while !comps.isEmpty {
            let candidateRawHighlightName = comps.joined(separator: ".")
            if let highlightName = Self(rawValue: candidateRawHighlightName) {
                self = highlightName
                return
            }
            comps.removeLast()
        }
#if DEBUG
        if !previousUnrecognizedHighlightNames.contains(rawHighlightName) {
            previousUnrecognizedHighlightNames.append(rawHighlightName)
            print("Unrecognized highlight name: '\(rawHighlightName)'."
                  + " Add the highlight name to HighlightName.swift if you want to add support for syntax highlighting it."
                  + " This message will only be shown once per highlight name.")
        }
#endif
        return nil
    }
}
