import Foundation
import Runestone
import RunestoneMarkdownLanguage

/// Headless benchmarks against the public `Runestone` API, driving `TextView`/`TextViewState` directly
/// with no `NSWindow`/run loop. See PERFORMANCE_AUDIT.md Phase 5 for what these numbers mean and what
/// still needs a real Instruments pass (actual on-screen frame compositing isn't observable headlessly).
enum Commands {
    struct Options {
        var highlighted = false
    }

    // MARK: - Shared setup

    /// Reads `path` into a `String` and reports how long that alone takes — this is the "decode the
    /// whole file before Runestone can even start" cost described in PERFORMANCE_AUDIT.md Phase 1 §2.
    private static func readFile(_ path: String) throws -> (text: String, readSeconds: Double, sizeBytes: UInt64) {
        let url = URL(fileURLWithPath: path)
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        let result = try Measurement.time("read file into String") {
            try String(contentsOf: url, encoding: .utf8)
        }
        return (result.value, result.seconds, sizeBytes)
    }

    private static func makeState(text: String, options: Options) -> TextViewState {
        if options.highlighted {
            return TextViewState(text: text, language: .markdown)
        } else {
            return TextViewState(text: text)
        }
    }

    private static func makeTextView(state: TextViewState) -> TextView {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        textView.setState(state)
        return textView
    }

    // MARK: - open

    static func open(path: String, options: Options) throws {
        FileHandle.standardError.write("=== open \(path) (highlighted: \(options.highlighted)) ===\n".data(using: .utf8)!)
        let before = Measurement.residentMemoryBytes()
        let (text, readSeconds, sizeBytes) = try readFile(path)
        ResultLog.row("read", file: path, sizeBytes: sizeBytes, seconds: readSeconds)

        let stateResult = Measurement.time("TextViewState.init (line index + parse)") {
            makeState(text: text, options: options)
        }
        ResultLog.row("state_init", file: path, sizeBytes: sizeBytes, seconds: stateResult.seconds, extra: options.highlighted ? "highlighted" : "plain")

        let viewResult = Measurement.time("TextView.setState") {
            makeTextView(state: stateResult.value)
        }
        ResultLog.row("set_state", file: path, sizeBytes: sizeBytes, seconds: viewResult.seconds)

        // Proxy for "time to first painted frame": force one layout pass over the initial viewport.
        let firstLayout = Measurement.time("first layoutSubviews() (first-frame proxy)") {
            viewResult.value.layoutSubviews()
        }
        ResultLog.row("first_frame_proxy", file: path, sizeBytes: sizeBytes, seconds: firstLayout.seconds)

        let after = Measurement.residentMemoryBytes()
        ResultLog.row("rss_delta", file: path, sizeBytes: sizeBytes, seconds: 0, extra: Measurement.formatBytes(after - before))
        FileHandle.standardError.write("  RSS: \(Measurement.formatBytes(before)) -> \(Measurement.formatBytes(after))\n".data(using: .utf8)!)
    }

    // MARK: - scroll

    static func scroll(path: String, frames: Int, options: Options) throws {
        FileHandle.standardError.write("=== scroll \(path) (\(frames) frames) ===\n".data(using: .utf8)!)
        let (text, _, sizeBytes) = try readFile(path)
        let state = makeState(text: text, options: options)
        let textView = makeTextView(state: state)
        textView.layoutSubviews()
        Measurement.pumpRunLoop() // let the deferred contentSize update (TextView.swift:1676) settle

        let totalHeight = max(textView.contentSize.height - textView.frame.height, 1)
        var maxFrameSeconds = 0.0
        var totalSeconds = 0.0
        for frameIndex in 0..<frames {
            let fraction = Double(frameIndex) / Double(max(frames - 1, 1))
            textView.contentOffset = CGPoint(x: 0, y: totalHeight * fraction)
            let frameResult = Measurement.time {
                textView.layoutSubviews()
            }
            totalSeconds += frameResult.seconds
            maxFrameSeconds = max(maxFrameSeconds, frameResult.seconds)
        }
        let avgSeconds = totalSeconds / Double(frames)
        ResultLog.row("scroll_avg_frame", file: path, sizeBytes: sizeBytes, seconds: avgSeconds)
        ResultLog.row("scroll_worst_frame", file: path, sizeBytes: sizeBytes, seconds: maxFrameSeconds)
        FileHandle.standardError.write("  avg frame: \(String(format: "%.5f", avgSeconds))s, worst: \(String(format: "%.5f", maxFrameSeconds))s\n".data(using: .utf8)!)
    }

    // MARK: - keystroke

    enum Position: String { case start, middle, end }

    static func keystroke(path: String, position: Position, options: Options) throws {
        FileHandle.standardError.write("=== keystroke \(path) at \(position.rawValue) ===\n".data(using: .utf8)!)
        let (text, _, sizeBytes) = try readFile(path)
        let state = makeState(text: text, options: options)
        let textView = makeTextView(state: state)
        textView.layoutSubviews()

        let length = (text as NSString).length
        let location: Int
        switch position {
        case .start: location = min(10, length)
        case .middle: location = length / 2
        case .end: location = max(length - 10, 0)
        }
        // Scroll the edit location into view first, matching how a real edit is always at/near the
        // visible viewport rather than an arbitrary offscreen location.
        if let textLocation = textView.textLocation(at: location) {
            _ = textView.goToLine(textLocation.lineNumber, select: .beginning)
        }

        let editResult = Measurement.time("single-character insert") {
            textView.replace(NSRange(location: location, length: 0), withText: "x")
        }
        ResultLog.row("keystroke_\(position.rawValue)", file: path, sizeBytes: sizeBytes, seconds: editResult.seconds)
    }

    // MARK: - goto

    static func goto(path: String, percent: Int, options: Options) throws {
        FileHandle.standardError.write("=== goto \(path) at \(percent)% ===\n".data(using: .utf8)!)
        let (text, _, sizeBytes) = try readFile(path)
        let lineCount = max(text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }, 1)
        let state = makeState(text: text, options: options)
        let textView = makeTextView(state: state)
        textView.layoutSubviews()

        let targetLine = min(max(Int(Double(lineCount) * Double(percent) / 100.0), 0), lineCount - 1)
        let gotoResult = Measurement.time("goToLine") {
            _ = textView.goToLine(targetLine, select: .beginning)
        }
        ResultLog.row("goto_\(percent)pct", file: path, sizeBytes: sizeBytes, seconds: gotoResult.seconds, extra: "line \(targetLine) of \(lineCount)")
    }

    // MARK: - search

    static func search(path: String, pattern: String, regex: Bool, options: Options) throws {
        FileHandle.standardError.write("=== search \(path) pattern=\(pattern) regex=\(regex) ===\n".data(using: .utf8)!)
        let (text, _, sizeBytes) = try readFile(path)
        let state = makeState(text: text, options: options)
        let textView = makeTextView(state: state)
        textView.layoutSubviews()

        let query = SearchQuery(text: pattern, matchMethod: regex ? .regularExpression : .contains)
        let searchResult = Measurement.time("TextView.search(for:) — the SearchController path used by the shipping find panel") {
            textView.search(for: query)
        }
        ResultLog.row(regex ? "search_regex" : "search_literal", file: path, sizeBytes: sizeBytes, seconds: searchResult.seconds, extra: "\(searchResult.value.count) matches")
    }

    // MARK: - save

    static func save(path: String, options: Options) throws {
        FileHandle.standardError.write("=== save \(path) after one edit ===\n".data(using: .utf8)!)
        let (text, _, sizeBytes) = try readFile(path)
        let state = makeState(text: text, options: options)
        let textView = makeTextView(state: state)
        textView.layoutSubviews()
        textView.replace(NSRange(location: 0, length: 0), withText: "x")

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("perfharness-save-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let saveResult = Measurement.time("naive full rewrite after 1-character edit") {
            try? textView.text.write(to: tempURL, atomically: true, encoding: .utf8)
        }
        ResultLog.row("save_full_rewrite", file: path, sizeBytes: sizeBytes, seconds: saveResult.seconds,
                       extra: "baseline only \u{2014} see PERFORMANCE_AUDIT.md Phase 4 Saving for the patch-based alternative")
    }
}
