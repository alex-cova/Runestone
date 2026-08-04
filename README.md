# Runestone

A performant, feature-rich plain text and code editor framework for **macOS** with integrated IDE intelligence services.

Based on [simonbs/Runestone](https://github.com/simonbs/Runestone), this repository is specifically ported and extended to run natively on **macOS**. It combines a high-performance text rendering engine with the **Editor Intelligence Platform (EIP)** for code completion, tree-sitter AST parsing, indexing, navigation, hover documentation, diagnostics, and AI/LSP integrations.

---

## Key Features

### 🎨 High-Performance Text Editor (`Runestone`)
* **macOS-Native Design**: Built on AppKit shims and custom layout systems for smooth macOS text editing, mouse interaction, and keybindings.
* **Syntax Highlighting**: Powered by Tree-sitter for fast, accurate incremental syntax highlighting.
* **Gutter & Line Numbers**: Customizable line numbers, gutter width, and line selection highlights.
* **Background Preparation**: Use `TextViewState` to parse text and setup state off the main thread for instant loading of large files.
* **Text Formatting & Customization**: Support for line wrapping, tab widths, custom themes, invisible character rendering, and font trait overrides.
* **Search & Replace**: Built-in regular expression search and replace capabilities.

### 🧠 Editor Intelligence Platform (`EditorIntelligence`)
* **Incremental Tree-sitter Parsing**: Asynchronous AST parsing (`TreeSitterLanguageParser`) with document state tracking.
* **Symbol Indexing**: Trie-backed incremental `SymbolIndex` and `IndexingService` for fast identifier lookups.
* **Async Code Completion Engine**: Multi-provider completion framework supporting ranking, snippets, local symbols, in-buffer words, LSP servers, and AI models.
* **Snippet Engine**: Interactive code snippets with tab stops, default placeholders, and variable transformations.
* **Hover & Documentation**: Cached hover engine providing rich markdown tooltips and symbol documentation (`HoverEngine`, `SymbolHoverProvider`).
* **Code Navigation**: Support for Go to Definition, Find References, Symbol Search, and Breadcrumbs.
* **Diagnostics Engine**: Problem reporting and severity tracking with built-in analyzers (e.g. duplicate symbol detection).
* **Refactoring Framework**: AST-guided symbol refactoring including rename operations.
* **AI & LSP Integration**: Modular adapters for Language Server Protocol (`LSPClient`) and AI model integration (`AITextModel`, `AICompletionProvider`, `AIHoverProvider`).
* **UI Presentation Layer**: AppKit presentation models and views (`CompletionPanelView`, `HoverWindowView`, `GhostTextModel`).

---

## Requirements

* **macOS**: 12.0 (Monterey) or later
* **Swift**: 5.5+ / Xcode 13+
* **Dependencies**: [Tree-sitter](https://github.com/tree-sitter/tree-sitter) (v0.20.9+)

---

## Project Architecture

```
Runestone/
├── Sources/
│   ├── Runestone/                  # Core text editor engine & macOS AppKit shims
│   │   ├── TextView/               # Text view layout, gutter, themes, and selection
│   │   ├── TreeSitter/             # Tree-sitter integration & syntax highlighters
│   │   ├── EditorIntelligenceAdapter/# Adapter connecting TextView to EditorIntelligence
│   │   └── Library/                # AppKit/UIKit compatibility layer
│   │
│   ├── EditorIntelligence/         # Editor Intelligence Platform (EIP)
│   │   ├── Core/                   # Documents, cursors, selections, event bus
│   │   ├── Parsing/ & Indexing/    # Tree-sitter parsing & trie symbol index
│   │   ├── Completion/ & Snippets/ # Completion engine, ranking & snippet expansion
│   │   ├── Hover/ & Navigation/    # Documentation tooltips & code navigation
│   │   ├── Diagnostics/ & Refactoring/# Issue tracking & AST symbol rename
│   │   ├── AI/ & LSP/              # AI providers & LSP server adapters
│   │   └── UIBridge/               # AppKit views & presentation models
│   │
│   ├── SmokeTest/                  # Minimal runtime executable target
│   └── TestTreeSitterLanguages/    # Tree-sitter language test targets
│
├── Example/
│   └── MacExample/                 # Example AppKit macOS application
└── Tests/
    └── RunestoneTests/             # Unit and integration test suite (243 tests)
```

---

## Installation

Add Runestone as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/simonbs/Runestone.git", branch: "main")
]
```

Then add `Runestone` (and optionally `EditorIntelligence`) to your target dependencies:

```swift
.target(
    name: "YourAppTarget",
    dependencies: [
        .product(name: "Runestone", package: "Runestone"),
        .product(name: "EditorIntelligence", package: "Runestone")
    ]
)
```

---

## Quick Start

### Basic `TextView` Setup

```swift
import AppKit
import Runestone

class ViewController: NSViewController {
    override func loadView() {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        textView.theme = DefaultTheme()
        textView.text = """
        // Welcome to Runestone on macOS!
        func greet(name: String) {
            print("Hello, \(name)!")
        }
        """
        textView.showLineNumbers = true
        textView.isLineWrappingEnabled = true
        self.view = textView
    }
}
```

### Loading State Asynchronously

For large files, initialize the editor state on a background queue:

```swift
DispatchQueue.global(qos: .userInitiated).async {
    let state = TextViewState(text: largeCodeString, theme: DefaultTheme())
    DispatchQueue.main.async {
        textView.setState(state)
    }
}
```

### Using Editor Intelligence Platform (EIP)

```swift
import Runestone
import EditorIntelligence

// Adapt TextView to EditorIntelligence
let adapter = RunestoneEditorAdapter(textView: textView)

// Configure completion engine with providers
let completionEngine = CompletionEngine(providers: [
    SymbolCompletionProvider(index: symbolIndex),
    WordCompletionProvider(),
    SnippetCompletionProvider(snippets: mySnippets)
])

// Request completions asynchronously
let context = adapter.makeCompletionContext()
Task {
    let response = await completionEngine.completions(for: context)
    print("Completions: \(response.value)")
}
```

---

## Testing

The project includes a comprehensive suite of unit and integration tests covering text editing, tokenization, selection handling, tree-sitter parsing, symbol indexing, completion ranking, hover tooltips, and diagnostic reporting.

Run the test suite using SPM:

```bash
swift test
```

---

## License

Runestone is available under the MIT license. See the [LICENSE](LICENSE) file for more information.
