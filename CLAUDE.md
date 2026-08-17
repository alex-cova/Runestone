# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Runestone is a Swift Package Manager library: a high-performance plain text/code editor engine for **macOS** (AppKit), forked from simonbs/Runestone (originally iOS/UIKit) and ported natively to macOS. It combines two layers:

- **`Runestone`** — the text rendering/editing engine itself (line layout, gutter, tree-sitter syntax highlighting, selection, undo, search & replace).
- **`EditorIntelligence`** — a separate, editor-agnostic IDE-intelligence platform (completion, indexing, hover, navigation, diagnostics, refactoring, LSP/AI adapters) that has **no dependency on `Runestone`**. The two are connected only through `Sources/Runestone/EditorIntelligenceAdapter/RunestoneEditorAdapter.swift`.

Requires macOS 12+, Swift 5.5+/Xcode 13+. Tree-sitter (v0.20.9+) is pulled in as an SPM dependency.

## Common commands

```bash
swift build                                   # build all targets
swift test                                    # run the full RunestoneTests suite
swift test --filter ClassName                 # run one test class
swift test --filter ClassName/testMethodName  # run one test method
```

There is no separate lint/format script wired into SPM; SwiftLint config lives at `.swiftlint.yml` (run `swiftlint` directly if installed). `swiftgen.yml` regenerates `Sources/Runestone/Library/L10n.swift` from `Localizable.strings` — don't hand-edit that generated file.

The `Example/MacExample` app is a standalone Xcode/SPM workspace demonstrating usage; it is not part of the root package's build graph.

## Architecture

### Two independent targets, one adapter

`EditorIntelligence` is intentionally decoupled from any specific text-editing UI. It defines its own `Document`, `Cursor`, `Selection`, `TextEdit`/`TextRange` types and talks to an editor only through the `EditorAdapter` protocol (`Sources/EditorIntelligence/Core/EditorAdapter.swift`): a stable `id`, a `context`, a `currentDocument`/`openDocuments` snapshot, an `AsyncStream<EditorEvent>` of edits/selection changes, and async `applyEdit`/`focusRange` methods.

`RunestoneEditorAdapter` (`Sources/Runestone/EditorIntelligenceAdapter/RunestoneEditorAdapter.swift`) is the concrete bridge: it becomes a `TextView`'s `editorDelegate`, caches a `Document` snapshot behind a lock so EIP services can read it off the main actor, and marshals edits/focus changes onto `MainActor` since they touch UI. When adding a new EIP feature, implement it against `EditorAdapter`/`Document`/etc. generically — don't reach into `Runestone` types from `EditorIntelligence` code.

### Runestone engine internals

- **`TextView/Core`** — `TextView.swift` (public AppKit view, ~1.5k lines) and `TextInputView.swift` (~1.8k lines, implements `NSTextInputClient`/keyboard-mouse handling) are the two central classes; most other `TextView/*` subfolders (Gutter, Highlight, Indent, InvisibleCharacters, Navigation, PageGuide, SearchAndReplace, TextSelection, CharacterPairs, LineController, Appearance) are focused collaborators they own.
- **`LineManager`** — maintains document lines as a red-black tree (`RedBlackTree/`) keyed by line position, so line lookups/edits are O(log n) rather than O(n) array operations. `DocumentLineChildrenUpdater` and `LineChangeSet` propagate edits through the tree.
- **`LanguageParser` + `TreeSitter`** — `TreeSitterLanguageParser`/`TreeSitterSyntaxTree` wrap the C tree-sitter library (`TreeSitter*.swift` files) to provide incremental AST parsing; `TreeSitterInternalLanguageMode` and `TreeSitterSyntaxHighlighter` consume the tree to drive syntax highlighting, while `PlainTextInternalLanguageMode`/`PlainTextSyntaxHighlighter` are the no-highlighting fallback. `TextViewState` lets a document + tree-sitter parse be prepared off the main thread before being handed to a `TextView`.
- **`Library`** — cross-cutting helpers (byte/range conversions between UTF-16 and tree-sitter's UTF-8 byte offsets, string helpers, `UIKitCompatibility/` shims used to keep API shape close to the original iOS/UIKit-based upstream project).
- **`RunestoneGraphQLLanguage`** — an example of the pattern for adding a tree-sitter language as its own SPM target: a `TreeSitterGraphQL` C target (grammar) + a Swift target providing `highlights.scm` and indentation scopes, depending on both `Runestone` and the C grammar target. Follow this structure when adding another language.

### EditorIntelligence internals

- **`Core`** — `DependencyContainer` (service locator/wiring), `EventBus` (typed pub/sub used by adapters and engines), `EditorContext`/`EditorEvent`/`EditorTypes`/`Request` — the shared vocabulary every other module builds on.
- **`Indexing`** — `SymbolIndex` backed by a `Trie` for prefix lookups, updated incrementally by `IndexingService` as documents change.
- **`Completion`** — `CompletionEngine` runs a list of `CompletionProvider`s (symbol/word/snippet/LSP/AI) concurrently and ranks results (`Ranking/`); `CompletionContextFactory` builds the request context from adapter/document state.
- **`Snippets`** — tab-stop/placeholder snippet expansion engine, driven through `UIBridge`'s `GhostTextModel`/`CompletionPanelModel`.
- **`Hover`**, **`Navigation`**, **`Diagnostics`**, **`Refactoring`** — each follows the same provider-engine pattern: an `*Engine` orchestrates one or more `*Provider`s (e.g. `DuplicateSymbolDiagnosticProvider`, `GoToDefinitionProvider`, `RenameOperation`) and returns typed results.
- **`AI`** and **`LSP`** — pluggable backends implementing the same provider protocols as native providers (`AICompletionProvider`, `LSPCompletionProvider`, etc.), so completion/hover/diagnostics can mix local, LSP, and AI sources transparently.
- **`UIBridge`** — AppKit-facing presentation models (`CompletionPanelModel`, `HoverWindowModel`, `ParameterHintsModel`, `GhostTextModel`) that translate engine output into view state; actual AppKit views live back in `Runestone/TextView`.

### Tests

`Tests/RunestoneTests` is a single XCTest target covering both `Runestone` and `EditorIntelligence` (243+ tests), plus `TestTreeSitterLanguages` (bundled grammars: html/javascript/json/python/yaml) and `RunestoneGraphQLLanguage` used as fixtures. Test files are one-class-per-file and named `<SubjectUnderTest>Tests.swift`; mocks live in `Tests/RunestoneTests/Mock` and `MockTextInput.swift`.
