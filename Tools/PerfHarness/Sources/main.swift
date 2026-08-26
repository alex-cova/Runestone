import Foundation

// PerfHarness: headless benchmark CLI for the large-file performance audit in PERFORMANCE_AUDIT.md.
// Generate synthetic fixtures first with Tools/PerfHarness/generate_fixtures.py, then run e.g.:
//
//   swift run -c release PerfHarness open Fixtures/short_lines_500mb.txt
//   swift run -c release PerfHarness scroll Fixtures/short_lines_500mb.txt --frames 60
//   swift run -c release PerfHarness keystroke Fixtures/short_lines_500mb.txt --at middle
//   swift run -c release PerfHarness goto Fixtures/short_lines_500mb.txt --percent 50
//   swift run -c release PerfHarness search Fixtures/short_lines_500mb.txt --pattern needle --regex
//   swift run -c release PerfHarness save Fixtures/short_lines_500mb.txt
//
// Always run with `-c release` — debug builds of tree-sitter/CoreText-heavy code are not representative.
// Add `--highlighted` to route through TreeSitterLanguage.markdown instead of plain text.
// Add `--deferred` to skip eager parse in TextViewState (first paint without a syntax tree).
// Add `--viewport` to parse only the visible window (SyntaxParsePolicy.viewport).
// Add `--chunked` on `open` to load via TextViewState.load with FileHandle reads.
// Add `--mmap` on `open` to load via TextViewState.load with MAP_PRIVATE ingest.
// Output is CSV on stdout (one row per metric); progress/timing narration goes to stderr.

func printUsageAndExit() -> Never {
    FileHandle.standardError.write("""
    Usage: PerfHarness <command> <path> [options]
    Commands:
      open <path> [--highlighted] [--deferred] [--viewport] [--chunked] [--mmap]
      scroll <path> [--frames N] [--highlighted] [--deferred]
      keystroke <path> --at start|middle|end [--highlighted] [--deferred]
      goto <path> --percent N [--highlighted] [--deferred]
      search <path> --pattern TEXT [--regex] [--highlighted] [--deferred]
      save <path> [--highlighted] [--deferred]

    """.data(using: .utf8)!)
    exit(1)
}

func flagValue(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func hasFlag(_ name: String, in args: [String]) -> Bool {
    args.contains(name)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { printUsageAndExit() }

let command = arguments[0]
let path = arguments[1]
let rest = Array(arguments.dropFirst(2))
let options = Commands.Options(
    highlighted: hasFlag("--highlighted", in: rest),
    deferred: hasFlag("--deferred", in: rest),
    chunked: hasFlag("--chunked", in: rest),
    mmap: hasFlag("--mmap", in: rest),
    viewport: hasFlag("--viewport", in: rest)
)

guard FileManager.default.fileExists(atPath: path) else {
    FileHandle.standardError.write("File not found: \(path)\n".data(using: .utf8)!)
    exit(1)
}

do {
    switch command {
    case "open":
        try Commands.open(path: path, options: options)
    case "scroll":
        let frames = Int(flagValue("--frames", in: rest) ?? "") ?? 30
        try Commands.scroll(path: path, frames: frames, options: options)
    case "keystroke":
        guard let raw = flagValue("--at", in: rest), let position = Commands.Position(rawValue: raw) else {
            FileHandle.standardError.write("keystroke requires --at start|middle|end\n".data(using: .utf8)!)
            exit(1)
        }
        try Commands.keystroke(path: path, position: position, options: options)
    case "goto":
        guard let raw = flagValue("--percent", in: rest), let percent = Int(raw) else {
            FileHandle.standardError.write("goto requires --percent N\n".data(using: .utf8)!)
            exit(1)
        }
        try Commands.goto(path: path, percent: percent, options: options)
    case "search":
        guard let pattern = flagValue("--pattern", in: rest) else {
            FileHandle.standardError.write("search requires --pattern TEXT\n".data(using: .utf8)!)
            exit(1)
        }
        try Commands.search(path: path, pattern: pattern, regex: hasFlag("--regex", in: rest), options: options)
    case "save":
        try Commands.save(path: path, options: options)
    default:
        printUsageAndExit()
    }
} catch {
    FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
