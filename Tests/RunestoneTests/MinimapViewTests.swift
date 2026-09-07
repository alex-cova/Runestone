@preconcurrency import AppKit
@testable import Runestone
import RunestoneMarkdownLanguage
import XCTest

/// End-to-end checks on the real `MinimapView` inside a laid-out `TextView` (the Core Text render
/// path, since tests disable Metal): it paints syntax colors, keeps its cost bounded on a large
/// document instead of walking every row, and survives the degenerate document sizes.
final class MinimapViewTests: XCTestCase {
    @MainActor
    private func makeTextView(text: String, language: TreeSitterLanguage? = nil) -> TextView {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 500, height: 600))
        textView.minimapWidth = 100
        textView.showMinimap = true
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        let state: TextViewState
        if let language {
            state = TextViewState(text: text, theme: DefaultTheme(), language: language, languageProvider: MarkdownLanguageProvider())
        } else {
            state = TextViewState(text: text, theme: DefaultTheme())
        }
        textView.setState(state)
        textView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        textView.layoutIfNeeded()
        return textView
    }

    @MainActor
    private func distinctColors(inColumn column: Int, of view: NSView) -> Set<[Int]> {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return []
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var colors: Set<[Int]> = []
        var y = 2
        while CGFloat(y) < view.bounds.height - 2 {
            if let color = bitmap.colorAt(x: column, y: y)?.usingColorSpace(.deviceRGB) {
                colors.insert([
                    Int((color.redComponent * 255).rounded()),
                    Int((color.greenComponent * 255).rounded()),
                    Int((color.blueComponent * 255).rounded()),
                ])
            }
            y += 3
        }
        return colors
    }

    private var markdownDocument: String {
        var lines: [String] = []
        for i in 0 ..< 160 {
            switch i % 6 {
            case 0: lines.append("# Heading number \(i)")
            case 1: lines.append("Some **bold** and _italic_ prose on line \(i).")
            case 2: lines.append("    let indented = code(\(i))")
            case 3: lines.append("")
            case 4: lines.append("- list item \(i) with `inline code`")
            default: lines.append("> a quoted line \(i)")
            }
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    func testMinimapPaintsMoreColorsWithSyntaxHighlightingThanWithout() {
        let plain = makeTextView(text: markdownDocument)
        let highlighted = makeTextView(text: markdownDocument, language: .markdown)

        let sampleColumn = 20
        let plainColors = distinctColors(inColumn: sampleColumn, of: plain.minimapViewForTesting)
        let highlightedColors = distinctColors(inColumn: sampleColumn, of: highlighted.minimapViewForTesting)

        XCTAssertGreaterThanOrEqual(plainColors.count, 2, "at minimum: background + one bar color")
        XCTAssertGreaterThan(highlightedColors.count, plainColors.count,
                             "syntax highlighting introduces more distinct bar colors than a flat render")
    }

    @MainActor
    func testDrawIsBoundedByViewportNotDocumentLength() {
        let manyLines = (0 ..< 5000).map { "func item\($0)() { return \($0) }" }.joined(separator: "\n")
        let textView = makeTextView(text: manyLines, language: .markdown)
        let minimap = textView.minimapViewForTesting

        guard let bitmap = minimap.bitmapImageRepForCachingDisplay(in: minimap.bounds) else {
            return XCTFail("no bitmap")
        }
        minimap.cacheDisplay(in: minimap.bounds, to: bitmap)

        // A y-space walk touches at most ~one row per `minimapRowHeight` of view height; an
        // O(document) walk would report 5000.
        let ceiling = Int(minimap.bounds.height / 3) + 32
        XCTAssertGreaterThan(minimap.debugLastDrawnRowCount, 0)
        XCTAssertLessThan(minimap.debugLastDrawnRowCount, ceiling,
                          "expected a viewport-bounded walk, got \(minimap.debugLastDrawnRowCount)")
    }

    @MainActor
    func testEmptyAndSingleLineDocumentsDoNotCrash() {
        for text in ["", "just one line"] {
            let textView = makeTextView(text: text, language: .markdown)
            let minimap = textView.minimapViewForTesting
            if let bitmap = minimap.bitmapImageRepForCachingDisplay(in: minimap.bounds) {
                minimap.cacheDisplay(in: minimap.bounds, to: bitmap)
            }
        }
    }
}
