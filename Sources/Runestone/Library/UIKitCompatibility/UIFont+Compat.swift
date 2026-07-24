import AppKit
import Foundation

extension NSFont {
    var lineHeight: CGFloat { totalLineHeight }
    var totalLineHeight: CGFloat { ascender + abs(descender) + leading }

    static func monospacedSystemFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}
