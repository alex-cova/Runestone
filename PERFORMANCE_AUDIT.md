# Runestone Performance Audit: Scaling to 500 MB–2 GB Files

Scope: `Sources/Runestone` (text engine) and `Sources/EditorIntelligence` (+ `EditorIntelligenceLSP`).
Toolchain used for verification: Xcode 26.6 / Swift 6.3.3 / SDK macosx26.5. Package manifest currently
declares `platforms: [.macOS(.v12)]`. All claims below are either (a) a direct code citation, (b) a
directly-run measurement (build logs, compiler probes), or (c) explicitly labeled **HYPOTHESIS** with a
suggested way to confirm it with the benchmark harness in `Tools/PerfHarness`.

The audit itself involved no production code changes. Since then, a first round of fixes from the
Phase 2/migration-plan findings *has* been applied to `Sources/Runestone` — each is marked **fixed** (or
**partially fixed**, with the remaining gap stated) inline in the relevant finding below, and summarized
in the Phase 5 §3 migration-plan status. Everything still marked open has not been touched.

---

## Phase 1 — Architecture as it exists today

### 1. Text storage
Single source of truth is `StringView` (`Sources/Runestone/TextView/Core/StringView.swift:14-27`), a thin
wrapper over one `NSMutableString` (`internalString`). Not a rope, not a piece table, not a gap buffer —
one contiguous mutable buffer for the entire document. `replaceText(in:with:)` (`StringView.swift:49-51`)
calls `internalString.replaceCharacters(in:with:)` directly.

### 2. Loading path
**There is no loading path in this library at all.** A repo-wide search for `Data(contentsOf:`,
`String(contentsOf:`, `FileHandle`, and `mmap` found exactly one hit
(`TreeSitterLanguage.swift:82`, loading a small `.scm` query resource) and nothing in `Example/MacExample`
either. Every entry point — `TextViewState.init(text: String, ...)` (`TextViewState.swift:33,51`) and
`StringSyntaxHighlighter.syntaxHighlight(_ text: String)` — requires the caller to already hold the
*entire* file as a Swift `String`. There is no mmap, streaming, or chunked ingestion anywhere between
disk and `TextViewState`. This is the most consequential Phase-1 finding: none of the "open a 2 GB file"
problem is solved by the library today; it is 100% unowned.

### 3. Line indexing
`LineManager` (`Sources/Runestone/LineManager/LineManager.swift`) sits on an order-statistics (augmented)
red-black tree (`RedBlackTree.swift`). Each `RedBlackTreeNode` carries `nodeTotalCount`
(`RedBlackTreeNode.swift:14`, subtree line count) and `DocumentLineChildrenUpdater` additionally
aggregates UTF-16 length, byte length, and line-height sums up the tree
(`DocumentLineChildrenUpdater.swift:5-24`). This gives O(log n) line-by-row, line-by-offset,
line-by-byte-offset, and line-by-y-position lookups. `LineManager.lineCount`
(`LineManager.swift:22-24`) is a direct read of `nodeTotalCount` — O(1). Per-line node data
(`DocumentLineNodeData.swift:4-33`) stores only scalars (lengths, byte count, height) plus a weak
back-reference — **no line text is cached in the tree**; text always comes from `StringView`. Estimated
overhead: ~160–220 bytes/line (tree node + node-data object), independent of line content length — so
for a file dominated by many short lines, *line count*, not byte size, drives line-manager memory (e.g.
~33M lines of 60 bytes ≈ 2 GB of text but 5–7 GB of pure line-manager metadata).

`rebuild()` (`LineManager.swift:51-98`) does one forward pass with `NewLineFinder`
(`NewLineFinder.swift:4-14`, a single call to `NSString.getLineStart(_:end:contentsEnd:for:)` per line —
a bulk Foundation primitive, not manual character stepping) and then builds a balanced tree bottom-up in
O(n) (`RedBlackTree.rebuild`/`buildTree`, `RedBlackTree.swift:29-34,488-504`). However, `rebuild()` also
calls `stringView.string.substring(with: substringRange)` per line (`LineManager.swift:67,88`) purely to
compute `byteCount`, even though `byteCount == length * 2` is derivable from the already-known
`totalLength` without materializing a substring (as is already done elsewhere, e.g.
`LineManager.swift:293-297,336-338`). This doubles allocation/copy work during the one-time initial load
of a multi-GB file.

Single-line insert/delete (`LineManager.swift:100-201`) locate the touched line via
`node(containingLocation:)` (`RedBlackTree.swift:36-76`, O(log n)) and only touch the affected node(s);
propagation to the root is O(log n) (`RedBlackTree.swift:217-238`). "Go to line N"
(`line(atRow:)`→`node(atIndex:)`, `RedBlackTree.swift:155-174`) is an O(log n) rank descent.

### 4. Encoding
Not handled by the library at all, by construction: a Swift `String` is always valid Unicode, so once a
document reaches `TextViewState`, there is no invalid-byte, mixed-encoding, or mojibake path to audit
inside Runestone. `LineEndingDetector` (`Sources/Runestone/Library/LineEndingDetector.swift:12-46`)
samples up to 20 lines of the already-decoded string to guess LF/CRLF/CR; it never touches raw bytes or a
BOM. **Any encoding sniffing, BOM stripping, or invalid-byte repair for a 2 GB file must happen in the
host app before it ever calls into Runestone** — this is a hard architectural boundary, not a
missing feature to patch internally.

### 5. Rendering
Fully custom Core Text layout — no `NSLayoutManager`/`NSTextLayoutManager` anywhere.
`LineTypesetter` drives `CTTypesetterCreateWithAttributedString`/`CTTypesetterCreateLine`
(`LineTypesetter.swift:82,225`) and `LineFragmentRenderer` draws with `CTLineDraw`
(`LineFragmentRenderer.swift:292`) directly into a `CGContext`. Layout is genuinely viewport-scoped:
`LayoutManager.layoutLinesInViewport()` (`LayoutManager.swift:516-610`) walks from
`paddedInsetViewport.minY` and stops once `maxY >= layoutBounds.maxY`, where `paddedInsetViewport` is the
visible rect expanded by a fixed 350pt `verticalLayoutPadding` (`LayoutManager.swift:165-169`) — never
more. Each `LineController` only does CoreText work when queried (`LineController.swift:93-97,125-131`);
lines that scroll off-screen are recycled via `ViewReuseQueue` and have their syntax highlighting
cancelled (`LayoutManager.swift:596-604`). **Verified and removed**: a non-viewport-scoped
`layoutLines(toLocation:)` (formerly `LayoutManager.swift:457-475`, explicitly commented "O(number of
lines up to `location`)") existed alongside the O(log n) `prepareLineForDisplay(atLocation:)` — checked
every call site (`grep -rn "layoutLines(toLocation"` across `Sources`/`Tests`/`Tools`) and found it had
*zero* callers anywhere, including its own `TextInputView` wrapper; all real jump-to-location paths
(`goToLine`, `scrollRangeToVisible`, etc., `TextView.swift:1297,1570,1572,1826`) already correctly used
`prepareLineForDisplay(atLocation:)`. So the O(n) path wasn't a live risk — but dead code left lying next
to the O(log n) replacement is exactly the kind of thing a future edit could accidentally call instead of
the fast path, so both it and its unused wrapper were deleted rather than left as a landmine.

Gutter width (`GutterWidthService.swift`) reads `lineManager.lineCount` (O(1)) and caches the computed
width, so gutter sizing does not scan the document.

**Rendering itself is not a 2 GB bottleneck** — it already scales with visible lines, not file size.

### 6. Editing
`TextInputView.replaceText(in:with:)` (`TextInputView.swift:1979`) → `TextEditHelper.replaceText` →
`StringView.replaceText` → `NSMutableString.replaceCharacters(in:with:)` (`StringView.swift:50`). This is
one contiguous buffer; CFMutableString's internal reallocation/`memmove` behavior means a worst-case
O(document length) cost per edit for edits away from the last edit point (sequential typing at one
location benefits from an internal gap heuristic; jumping around a huge document does not).
`LineManager` updates are O(log n) as above, and tree-sitter's `TreeSitterInternalLanguageMode.textDidChange`
(`TreeSitterInternalLanguageMode.swift:64-81`) applies an incremental `TreeSitterInputEdit` — genuinely
incremental re-parsing, not a full re-parse per edit.

One unconditional whole-document cost on every edit when code folding is enabled:
`TextInputView.swift:2033` calls `foldingController.setNeedsRecompute()` on every edit, consumed lazily
by `LayoutManager.swift:363`'s `recomputeIfNeeded()` on the next layout pass, which runs
`FoldingController.recompute()` (`FoldingController.swift:294-329`) — a `while row < lineCount` walk over
**every line in the document**, once per layout pass following an edit. Folding defaults to disabled
(`FoldingController.swift:38`, `TextView.isLineFoldingEnabled`), so this only bites when a consumer turns
folding on for a huge file — but the code's own comments (`FoldingController.swift:14-30`) already flag
this exact tradeoff as a deliberate, documented scope cut, not an oversight.

### 7. Undo/redo
`TimedUndoManager` (`TimedUndoManager.swift`) only adds 1-second coalescing on top of `UndoManager`. Real
undo registration, `addUndoOperation` (`TextInputView.swift:2042-2066`), captures the replaced substring
and re-registers the inverse edit — a delta sized to the edit, not the document. The one exception:
`setStringWithUndoAction` (`TextInputView.swift:1931-1953`) does `stringView.string.copy()` — a full
document clone — for whole-document/batch-replace undo steps (`TextInputView.swift:1935`). Each
find/replace-all on a 2 GB document would push a full 2 GB clone onto the undo stack, unbounded.

### 8. Syntax highlighting / search
Two-tier and asymmetric. Per-line highlighting is lazy, cancellable, and queued off the caller's thread
(`TreeSitterSyntaxHighlighter.swift:42-76`, `LineController.swift:268-301`) — good. But the underlying AST
parse is eager and synchronous over the **entire** document before any line is ever displayed:
`TextViewState.prepare(with:)` (`TextViewState.swift:61-70`) calls `languageMode.parse(nsString)`
(line 65) unconditionally, which flows through `TreeSitterParser.parse(_:oldTree:)`
(`TreeSitterParser.swift:31-40`) into one `ts_parser_parse_string_encoding` call over the whole string —
no chunking at the parse-tree level. `StringSyntaxHighlighter.syntaxHighlight(_:)`
(`StringSyntaxHighlighter.swift:47-57`) does the identical full-document parse. The doc comment on
`TextViewState` (line 5) only *recommends* callers construct it on a background queue; nothing enforces
it, and `TextViewState.init` itself is fully synchronous.

Search has two independent, differently-safe implementations: `FindSearchEngine`
(`FindSearchEngine.swift`) is async, debounced 200 ms (`FindSearchScheduler.swift:14`), run in
`Task.detached(priority: .userInitiated)` (`FindSearchScheduler.swift:85`), and cancellable — but it is
**not** what the shipping find panel uses. `FindPanelController.swift:107,226` calls
`TextView.search(for:)`, which instantiates `SearchController` (`TextView.swift:1323,1347`) and runs
`query.matches(in: stringView.string)` (`SearchController.swift:46`) **synchronously, with no debounce
and no cancellation**, on whatever thread calls it (the find panel, i.e. main thread). `FindSearchEngine`
appears to be newer infrastructure not yet wired into the built-in find UI.

### 9. Saving
No save path exists anywhere in Runestone or `Example/MacExample` (`grep` for `write(to:`,
`FileManager` write APIs, `atomically`, and `NSDocument` all came back empty). Saving is entirely the host
application's responsibility; there is nothing to audit here beyond "the host app must not do a naive full
rewrite if the goal is fast-save on a multi-GB file" (see Phase 4).

### 10. Concurrency topology
The `EditorIntelligence` platform is thoroughly actor-based: 34 custom actors across
Completion/Navigation/Hover/Diagnostics/Refactoring/LSP/Indexing/Workspace/Cache (full list gathered via
`grep -rn "^public actor "`), e.g. `IndexingService`, `Workspace`, `CompletionEngine`,
`LSPWorkspaceSyncBridge`. Exactly one actor exists in `Runestone` proper: `TreeSitterLanguageParser`
(`LanguageParser/TreeSitterLanguageParser.swift:9`). Everything else in the text engine —
`LineManager`, `StringView`, `TextInputView`, `LayoutManager`, `FoldingController` — is a plain class
mutated only on the main thread by convention (confirmed explicitly in the `FoldingController.swift:20-24`
doc comment: *"`LineManager` is a plain (non-`Sendable`) class mutated only on the main thread"*), not by
`@MainActor` enforcement. Roughly 23 files carry `@MainActor` annotations, concentrated in `TextView/Core`
and `UIBridge`.

This creates a hard boundary: every time the actor-based EIP layer needs to see the document, something
on the main-thread side must bridge the live `NSMutableString` into an immutable `Sendable` snapshot. Three
independent bridge points do this **unconditionally on every keystroke, with no debounce**:

- `RunestoneEditorAdapter.textViewDidChange` → `refreshDocument()` → `makeDocument(with:)` →
  **`let text = textView.text as String`** (`RunestoneEditorAdapter.swift:107`) — a full
  `NSMutableString`→`String` bridge, documented in the adapter's own comment
  (`RunestoneEditorAdapter.swift:102-104`) as "eager and unavoidable." (Selection-only changes already
  avoid this by reusing the previous snapshot — `RunestoneEditorAdapter.swift:204-209` — so this
  optimization exists for one call path but not the text-changed path.)
- `RunestoneWorkbenchEditorAdapter.refreshLiveDocumentFromTextView` →
  **`selected.text = textView.text`** (`RunestoneWorkbenchEditorAdapter.swift:~103`) — the same full
  bridge, for the multi-pane workbench adapter.
- `LSPWorkspaceSyncBridge.handle(.documentChanged)` → **`syncService.notifyFullChange(document, version:)`**
  (`LSPWorkspaceSyncBridge.swift:63`) — bypasses the incremental, 250ms-batched machinery that already
  exists two structs away in the same file (`LSPDocumentSyncService.enqueueChange`/`scheduleFlush`,
  `LSPDocumentSyncService.swift:46-63`) and instead sends the **entire document** as a full-sync payload
  on every single edit event.

Downstream of the first bridge, `IndexingService.indexDocument(_:)` (`IndexingService.swift:32-55`) does a
second full `parser.parse(document:)` plus whole-document word extraction (`tree.words`) on every
`documentOpened`/`documentChanged` event, with **no debounce anywhere in `IndexingService` or
`Workspace`** (`grep` for `debounce`/`throttle` across `Workbench` and `Workspace` found nothing outside
the LSP sync service, which — as above — is bypassed for full-change notifications).

`@unchecked Sendable` / `nonisolated(unsafe)`: exactly 4 sites in the whole codebase, and all four are
genuinely lock-protected, not silenced warnings over real races:
- `FindSearchEngine.swift:381-382` — `nonisolated(unsafe) static var cache` guarded by a co-located
  `NSLock`.
- `RunestoneStateBuilder.swift:9,15,21,27` — four small carrier types (`PreparedState`, `WeakBox`,
  `UncheckedBox`, `GenerationGate`); three are either immutable-after-init or `NSLock`-protected.
  `WeakBox<T>` was the one soft spot: a `weak var` mutated/read across threads with no explicit lock,
  and no comment explaining why it's exempt. **Fixed** — added a doc comment explaining the actual
  invariant (ARC's weak-reference side table is internally locked, so this is safe without our own
  lock, unlike a plain `var T?` would be) rather than wrapping it in a redundant `NSLock`.
- `TreeSitterLanguageCache.swift:15` — `NSLock`-protected dictionary cache.
- `SemanticTokenStorage.swift:4-9` — `NSLock`-protected mutable state.

`Span`, `RawSpan`, `~Copyable`, `borrowing`, `consuming`, and `nonisolated(nonsending)` do not appear
anywhere in the codebase today (`grep -rn` across both targets returned zero hits for all six).

**Verified**: `Span<UInt8>`, `RawSpan`, `~Copyable` struct declarations, and `nonisolated(nonsending)`
all compile cleanly with this toolchain (Swift 6.3.3) even at `-target arm64-apple-macos12` — i.e. none of
these are gated by deployment target; they're available today regardless of whether the package bumps its
minimum OS. This was verified by direct `swiftc -typecheck` probes against `arm64-apple-macos12/15/26`,
not assumed from memory.

**Swift language mode — verified, not assumed**: `Package.swift` declares
`// swift-tools-version:5.5` (line 1) with no per-target `swiftSettings`, no
`.swiftLanguageMode(...)`, and no `enableUpcomingFeature`/`enableExperimentalFeature` anywhere in the
manifest. Tools-version 5.5 predates Swift 6 language modes entirely, so **this package compiles in Swift
5 language mode today**, on a Swift 6.3.3 toolchain, despite the audit brief's framing of it as a
"Swift 6 (strict concurrency enabled)" codebase. To quantify the gap, I ran a clean build of the
`Runestone` target with `-Xswiftc -strict-concurrency=complete` (the closest approximation to Swift 6
mode available without changing tools-version) and it **completed successfully with 0 errors and 8,292
warnings across 50 files** — the large majority explicitly annotated "this is an error in the Swift 6
language mode" (`#SendingRisksDataRace`, `#ConformanceIsolation`, `#MutableGlobalVariable`,
`#SendableClosureCaptures`, etc.; top categories: 2,800 "main actor-isolated property can not be mutated
from a nonisolated context", 1,408 "call to main actor-isolated instance method in a synchronous
nonisolated context", 578 `#SendingRisksDataRace`, 506 `#ConformanceIsolation`). **This means: flipping
this package to actual Swift 6 language mode today, with zero other changes, would not compile.**
(`EditorIntelligence`/`EditorIntelligenceLSP` were not included in this pass; given their actor-first
design they are likely far closer to compliant, but that is a hypothesis, not measured here.)

---

## Phase 2 — Bottlenecks ranked by impact on the 500 MB–2 GB goal

Each entry: what/where, cost class, which stated metric it degrades, confidence.

### 1. Per-keystroke full-document copy + full re-parse + full re-index + full LSP resync (compounding) — CONFIRMED, **partially fixed**
**Where (as originally found)**: `RunestoneEditorAdapter.swift:107`, `RunestoneWorkbenchEditorAdapter.swift:~103`,
`IndexingService.swift:32-55`, `LSPWorkspaceSyncBridge.swift:63`.
**Cost**: O(document size) NSString→String bridge, PLUS a second full tree-sitter parse, PLUS
whole-document word tokenization, PLUS (if an LSP is attached) serializing the entire document into a
`textDocument/didChange` full-sync payload — **all four, unthrottled, on every single character typed**,
whenever `RunestoneEditorAdapter`/`RunestoneWorkbenchEditorAdapter` is attached to the `TextView` (i.e.
whenever any EIP feature — completion, hover, diagnostics, LSP — is wired up, which is the platform's
entire purpose).
**Degrades**: keystroke-to-render latency, directly and severely — this is the single largest threat to
the stated "sub-16ms keystroke latency" goal at scale. On a small file this is invisible (sub-millisecond),
which is exactly the kind of problem the audit brief warns "only manifests at scale."
**Fixed (the frequency, not yet the payload shape)**: see migration step 1 — both adapters now debounce
the full-document bridge to at most once per 200ms quiet period. Since `Workspace.handleEditorEvent`
forwards `.documentChanged` 1:1 with no batching of its own (verified by reading it), everything
downstream — `IndexingService`'s full re-parse/re-index, `LSPWorkspaceSyncBridge`'s full resync — inherits
the lower event rate for free, without needing a separate fix at each layer. **Not fixed**: the LSP
resync still sends the *entire document* per sync (`notifyFullChange`, not incremental `enqueueChange`)
— a payload-size problem, distinct from the frequency problem just fixed, that needs real edit-delta
plumbing through `TextViewDelegate`/`EditorAdapter`/`Workspace` (none of which currently carry deltas)
and was deliberately left for a separate, larger pass.
**Confidence**: CONFIRMED by direct code reading, not a hypothesis; frequency fix verified by tests, not
yet by an Instruments before/after pass.

### 2. Eager, synchronous, unchunked full-document tree-sitter parse at open time — CONFIRMED, measured
**Where**: `TextViewState.swift:65`, `TreeSitterParser.swift:31-40`, `StringSyntaxHighlighter.swift:57`.
**Cost**: one `ts_parser_parse_string_encoding` call over the entire buffer. Measured directly with
`Tools/PerfHarness` (`PerfHarness open <file> --highlighted` vs. without) on a ~12 MB synthetic file
(`short_lines_10mb.txt`, tree-sitter Markdown grammar): `TextViewState.init` went from **0.17s (plain) to
3.96s (highlighted)** — a ~23x slowdown for parsing alone — and resident memory after open went from
**156 MB to 782 MB**, a ~65x blow-up relative to the 12 MB source file. This is a real measurement, not
tree-sitter's generic 1–10 MB/s throughput figure applied speculatively — and it's already this severe at
12 MB, three orders of magnitude below the stated 2 GB target. Extrapolating *linearly* from this single
data point would put a 2 GB open in the tens-of-minutes range with tens of GB of parse-tree memory, but
don't trust that extrapolation blindly: tree throughput/memory depend on grammar and content structure
(this test used Swift-like plaintext tokens fed to the Markdown grammar, which may parse pathologically
compared to real Markdown), and large-file tree-sitter memory usage may not scale purely linearly with
input size either. **Re-run this exact benchmark across 10 MB/100 MB/500 MB/2 GB before finalizing the
Phase 4 remediation** — the shape of the curve (linear vs. super-linear) determines how urgently the
"skip eager parse above a size threshold" degradation mode in Phase 4 is needed.
**Degrades**: "near-instant open" and "memory usage that does not scale linearly with file size" — both,
simultaneously. Nothing enforces that this happens off the main thread — only
`RunestoneStateBuilder.prepareAndApply` (`RunestoneStateBuilder.swift:74-98`) does that for you, and only
if a caller opts into it.
**Confidence**: CONFIRMED, with a real measurement at one data point; the full size curve is the next
thing to measure with the harness, not a hypothesis about the mechanism itself.

### 3. Single contiguous `NSMutableString` buffer for the whole document — CONFIRMED
**Where**: `StringView.swift:50`.
**Cost**: worst-case O(document length) `memmove` per edit for any edit that isn't at the end of the
buffer or immediately following the previous edit (CFMutableString's gap heuristic helps sequential
typing at one location, not edits scattered across a huge file — e.g. jumping between two distant
bookmarks and typing at each).
**Degrades**: keystroke latency, and specifically the audit's "keystroke-to-render latency at the start,
middle and end of the file" benchmark — expect this to show up as a strong position-dependent latency
curve (edits near byte 0 of a 2 GB buffer should be visibly worse than edits near the end, or vice versa,
depending on CFString's internal strategy — this asymmetry itself is worth measuring).
**Confidence**: the mechanism is CONFIRMED (CFMutableString is a single reallocatable buffer); the exact
constant-factor cost is a HYPOTHESIS to measure directly, since CFString's internal gap/rope-like
optimizations for `NSMutableString` are not publicly documented and may already mitigate this better than
naive reasoning suggests.

### 4. `LineManager.rebuild()` redundant per-line substring materialization on load — CONFIRMED, **fixed**
**Where**: `LineManager.swift:67,88`.
**Cost**: one throwaway `String` allocation + character copy per line during initial load, on top of the
newline scan — roughly doubles the allocation/copy work of the one-time load, for a value
(`byteCount = totalLength * 2`) that's already computable without it.
**Degrades**: open time.
**Fixed**: both substring calls replaced with `ByteCount(totalLength * 2)`.
**Confidence**: CONFIRMED and fixed.

### 5. Synchronous, non-cancellable, main-thread search in the shipping find panel — CONFIRMED, **fixed**
**Where (as originally found)**: `TextView/Find/FindPanelController.swift` → `TextView.swift:1323,1347` →
`SearchController.swift:46` (`query.matches(in: stringView.string)`).
**Cost**: O(document length) `NSString`/`NSRegularExpression` scan, synchronously, on the thread that
calls it (main, since it's driven by the find field's text-change callback).
**Degrades**: UI responsiveness while typing in the find field on a large file — every keystroke in the
search box would freeze the window for the duration of a full-document scan. Ironically, the
already-built `FindSearchEngine`/`FindSearchScheduler` (async, debounced, cancellable) solved exactly
this and simply wasn't wired to the shipping find panel.
**Fixed**: `FindPanelController` now drives search-as-you-type, next/previous, and document-change
refresh (while the panel is open) through `FindSession`/`FindSearchScheduler`/`FindSearchEngine` —
debounced 200ms, off the main actor, with the scan loop itself checking `Task.isCancelled` (Phase 3).
Next/Previous use `findNext`/`findPrevious` (O(distance to match)) rather than a full recount. **Not
fixed**: Replace All still goes through the original synchronous `SearchController` path — see migration
step 2 for why (capture-group-template expansion isn't available on the `FindSearchEngine` side without
further work). `UITextSearchingHelper` (the system `UITextSearching`/find-interaction bridge) and
`SearchController` itself were deliberately left untouched — both have real, separate reasons to stay
synchronous (a system API contract expecting synchronous results; capture-group correctness,
respectively) rather than being simple unaddressed debt.
**Confidence**: CONFIRMED and fixed for the panel's primary interaction (typing, navigation); actual
before/after freeze-duration delta is a HYPOTHESIS to measure with Instruments, not done here.

### 6. No mmap/streaming/chunked loading — architecture gap, not a bug — CONFIRMED
**Where**: absence, confirmed repo-wide (see Phase 1 §2).
**Cost**: the entire file must be resident as a `String` (UTF-16-backed `NSString` storage internally,
typically ~2x a UTF-8 file's byte size, plus transient decode buffers) before Runestone does anything.
**Degrades**: the explicit "memory usage that does not scale linearly with file size" goal — memory today
scales linearly with file size by construction, with a 2x+ constant factor before considering line-manager
and tree-sitter tree overhead on top.
**Confidence**: CONFIRMED as a gap; this is Phase 4's central design question.

### 7. Unbounded full-document undo snapshots for batch operations — CONFIRMED, **fixed**
**Where (as originally found)**: `TextInputView.swift:1931-1953`, specifically the `.copy()` that used
to sit where line 1935 was.
**Cost**: one full document clone per batch/replace-all undo step, with no cap on undo-stack depth.
**Degrades**: memory usage (unbounded growth) after repeated find/replace-all on a huge document; not a
per-keystroke problem, but a memory-pressure one under the "several GB" scenario.
**Fixed**: see migration step 5 — `setStringWithUndoAction` now registers a delta-sized inverse
(`TextEditHelper.apply(_:)`'s `inverseReplacements`) instead of cloning the whole document. Finding and
fixing this also surfaced a real, independent, pre-existing crash — see migration step 5 for details.
**Confidence**: CONFIRMED and fixed.

### 8. Pathological single-mega-line traversal / edit cost — CONFIRMED and measured
**Where**: `TextInputStringTokenizer.swift:129-247`, via `StringView.character(at:)`
(`StringView.swift:41-47`), one UTF-16 code unit per Objective-C message send; also
`StringView.replaceCharacters` (Phase 2 #3) on a single giant line.
**Cost**: bounded by *line* length, not document length, for normal text — but the audit brief explicitly
requires a "few multi-megabyte lines" synthetic variant, and a single-line file with no newlines makes
this bound equal to file size. Measured directly: `PerfHarness keystroke <file> --at middle` on two ~10 MB
fixtures of otherwise-comparable size — `short_lines_10mb.txt` (many short lines): **5.2ms**;
`mega_lines_10mb.txt` (few multi-megabyte lines): **40.9ms** — an ~8x latency increase from line-length
alone, at only 10 MB. This is a real measurement, and it directly demonstrates the audit brief's point
about synthetic variants: two files of identical byte size produce an 8x different keystroke latency
purely from line-length distribution, which a single "average file" benchmark would completely hide.
**Degrades**: exactly the kind of thing that "only manifests at scale and won't reproduce on small
files" (or reproduces on small files but only in the mega-line variant, not the short-line variant of the
same size) — keystroke-to-render latency.
**Confidence**: CONFIRMED with a real measurement at 10 MB; re-run at 100 MB/500 MB/2 GB mega-line
fixtures to see whether the gap widens (consistent with an O(line length) mechanism) or plateaus.

### 9. `Task { @MainActor in ... }` created per keystroke and per selection change — CONFIRMED, minor
**Where**: `RunestoneEditorAdapter.swift:83,92,202`.
**Cost**: one unstructured `Task` allocation + scheduler hop per edit/selection event. Small in isolation
(microseconds), but compounds with #1 and adds actor-hop overhead exactly where the goal is <16ms.
**Degrades**: keystroke latency, marginally.
**Status**: partially addressed as a side effect of #1's debounce fix — the *expensive* part (the
full-document bridge) now runs at most once per 200ms quiet period instead of per keystroke. The `Task`
allocation itself still happens on every keystroke (`refreshTask?.cancel(); refreshTask = Task { ... }`
in the debounced `refreshDocument()`), since cancelling and recreating is what makes the debounce work —
collapsing that down further (e.g. a reusable timer instead of cancel+recreate) would trade a
microsecond-scale allocation for real complexity, so it wasn't done. `textViewDidChangeSelection`
(line 202) is unrelated to #1 and still allocates a `Task` per selection change, unchanged.
**Confidence**: CONFIRMED.

### 10. `ContentSizeService.lineWidths` grows unbounded and its longest-line lookup falls back to a
full linear scan — CONFIRMED, **fixed**
**Where**: `ContentSizeService.swift`. `lineWidths: [DocumentLineNodeID: CGFloat]` gains one entry per
line ever measured (i.e. every line that's ever scrolled into view) and, pre-fix, was never evicted —
unbounded for a user paging through a huge non-wrapped file. Separately, `longestLineWidth`'s getter
falls back to a full `for (lineID, lineWidth) in lineWidths` scan whenever its cached value is
invalidated (e.g. any window resize while `isLineWrappingEnabled == false`) — a scan whose cost scales
with the unbounded dictionary above.
**Degrades**: memory usage (unbounded growth) after a long scroll session on a large non-wrapped file,
and main-thread latency on the occasional full rescan.
**Fixed**: added `ContentSizeService.removeLineWidths(exceptLinesWithID:)`, mirroring
`LineControllerStorage.removeAllLineControllers(exceptLinesWithID:)`, wired into
`LayoutManager.clearMemory()` (the existing memory-pressure-notification handler) alongside the
line-controller eviction it already did. The one line it must never evict is whichever one is currently
tracked as longest (`lineIDTrackingWidth`) — `setSize(of:to:)` reads that entry as the "current maximum"
to compare newly-measured lines against, so losing it would make the comparison read 0 and let almost
any subsequently-measured line incorrectly overtake it, silently shrinking the reported content width.
Verified in `Tests/RunestoneTests/ContentSizeServiceTests.swift`.
**Confidence**: CONFIRMED and fixed. Not re-measured with Instruments (VM Tracker/Allocations) at scale
— the fix bounds growth to memory-pressure-notification frequency, not continuously, since `clearMemory()`
only fires on an actual `UIApplication.didReceiveMemoryWarningNotification`-equivalent signal in this
AppKit port; between notifications the dictionary can still grow for the duration of one scroll session.

---

## Phase 3 — Swift 6 concurrency-specific findings

- **Accidental copies at isolation boundaries**: yes, and it's the same finding as Phase 2 #1 viewed
  through a concurrency lens. The `Document`/`TextSnapshot` handed from the main-thread `TextView` world
  into the actor-based EIP world is a `Sendable` value type wrapping a `String` — passing it is cheap
  (COW), but *producing* it (`textView.text as String` off an `NSMutableString`) is not, and that
  production happens on every edit. This isn't a "boundary-crossing copy" in the Swift-ownership sense
  (no `sending`/region-isolation would help here, since the copy is inherent in bridging a *mutable*
  reference type into an immutable value snapshot) — it's a caching/debounce problem, not an ownership
  problem. Recommendation: don't try to make the bridge itself cheaper; make it happen less often (see
  Phase 4).
- **Main actor overload**: this project's `defaultIsolation` is unset (Swift 5 mode; Swift 6.2's
  default-`MainActor` inference doesn't apply without opting into the newer language mode/upcoming
  feature), so nothing is *accidentally* main-actor-isolated by a mode default today. The risk is
  latent: if/when this package bumps to Swift 6 language mode, adopting default main-actor isolation
  without auditing would silently pull background-appropriate code (e.g. anything currently
  `nonisolated` by omission) onto the main actor. Treat `defaultIsolation` as a decision to make
  deliberately during the Swift 6 migration, not to inherit by default.
- **`nonisolated` vs `nonisolated(nonsending)`**: not used anywhere; not yet relevant since the codebase
  isn't in Swift 6 mode. Once actor isolation is tightened, `nonisolated(nonsending)` is a real candidate
  for the per-edit/per-frame adapter callbacks (`textViewDidChange`, etc.) to avoid a forced hop back to
  the caller's executor when the callee doesn't need actor isolation for its own state.
- **Actor contention**: `LineManager`/`StringView`/`TextInputView` are plain main-thread classes, not
  actors, so there is no actor-lock contention between the render path and the edit path *today* — they're
  already serialized by being main-thread-only. The contention that exists is architectural, not an
  actor-lock: the EIP actors (`IndexingService`, `Workspace`, LSP actors) each independently receive a
  full document snapshot and independently do full-document work, so under rapid typing you get N
  actors each queuing up a full-document job per keystroke. A custom executor wouldn't fix this; a
  debounce/coalescing layer in front of `documentChanged` emission would.
- **`@unchecked Sendable`/`nonisolated(unsafe)`**: audited above (Phase 1 §10) — 4 sites, all
  lock-protected or, for `WeakBox`, now documented as relying on ARC's own weak-reference-table locking.
  No sign of a warning being silenced over an actual unaddressed race.
- **Non-copyable / borrowing**: `Span`/`RawSpan`/`~Copyable`/`borrowing`/`consuming` are unused but
  verified available today at this toolchain regardless of deployment target (Phase 1 §10). They are
  strong candidates for a *future* byte-buffer/chunk-decode layer (Phase 4) precisely because that layer
  doesn't exist yet — there's no legacy code fighting the migration, only a decision to build the new
  ingestion layer with them from the start.
- **Async overhead**: per-keystroke `Task` creation confirmed (Phase 2 #9); no `async` calls found inside
  any tight per-character loop (the paragraph/word navigation loops in `TextInputStringTokenizer` are
  synchronous).
- **Cancellation**: `FindSearchEngine`/`FindSearchScheduler` staleness-checking at the `Task` level
  was already correct (`FindSearchScheduler.swift:21-24`), but the scan loops themselves — the actual
  hot path — didn't check `Task.isCancelled` internally, so a stale search over a huge document ran to
  completion (wasting CPU/time off the main thread) before its result was discarded. **Fixed**:
  `literalSearch`/`collectLiteralHighlights` (manual `while` loops) and `regexSearch`/
  `collectRegexHighlights` (`NSRegularExpression.enumerateMatches` — checked via the closure's `stop`
  pointer) now check `Task.isCancelled` per iteration/match and bail to `.empty` immediately. Verified
  with `FindSearchEngineTests.testLiteralSearchStopsScanningOnceCancelled`/
  `testRegexSearchStopsScanningOnceCancelled` (a pre-cancelled search over a 700K-character document
  returns in ~1-2ms instead of scanning the whole thing). The tree-sitter full-document parse at open
  (Phase 2 #2) and the shipping find panel's `SearchController` scan (Phase 2 #5) are **still not**
  cancellable — once started, both run to completion even if the user closes the file or clears the
  search field; neither has been touched yet.
- **Does it build in Swift 6 language mode today?** No — measured, not assumed (Phase 1 §10: 0 errors
  under Swift 5 mode + `-strict-concurrency=complete`, but 8,292 of those diagnostics are explicitly
  marked as becoming hard errors under actual Swift 6 language mode). **This means "make it Swift 6
  compliant" and "make it fast at 2 GB" are two separate, largely orthogonal bodies of work.** The
  concurrency cleanup (isolating `LineManager`/`StringView`/etc. properly, resolving 8k+ diagnostics)
  should not be scheduled as if it were part of the performance work, and performance work should not be
  blocked on it — the worst bottlenecks found here (full-document copy per keystroke, eager full parse,
  single-buffer memmove) are equally severe in Swift 5 mode today.

---

## Phase 4 — Recommended architecture

Smallest set of changes that unlocks 500 MB–2 GB editing, ranked so each phase ships independently.

### Buffer: keep `NSMutableString` for now; the real fix is upstream of it
A rope (B-tree of UTF-8 chunks) or piece table would fix Phase 2 #3's memmove cost, but **Phase 2 #1 and
#2 dominate by orders of magnitude** — no buffer data structure change helps if every keystroke still
triggers a full re-parse and a full re-index. Recommendation: fix #1/#2/#5 first (pure debounce/laziness
changes, no data-structure risk), *then* measure whether `NSMutableString`'s memmove cost is still
significant with the harness before investing in a rope. A rope interacts awkwardly with Swift value
semantics/COW/Sendable checking (a rope's persistent-tree nodes want structural sharing, which is exactly
what COW gives you for free with a `String`/array-backed structure, but a hand-rolled rope needs its own
COW discipline) — not free, so don't pay for it speculatively.
If/when it is needed: prefer a rope over a piece table for this codebase specifically, because
`LineManager`'s red-black tree is already an order-statistics tree over line boundaries — a byte-oriented
rope is the same data structure one layer down, and the two would compose naturally (rope leaves aligned
to line boundaries).

### File access: chunked reads for v1, `mmap` as a v2 optimization
Start with chunked reads (`FileHandle.read(upToCount:)` in a loop) decoding into whatever the new
byte-buffer type is (see Decoding below) rather than jumping straight to `mmap`. `mmap` avoids the initial
read-syscall cost but introduces real hazards this project would need to own: page faults during scroll
(effectively moving the I/O cost from "open" to "first scroll to that region," which could look like
scroll jank instead of open latency — arguably worse for the "smooth scrolling" goal), behavior under
external truncation/modification of the mapped file (SIGBUS on access past a truncated file), and
interaction with memory pressure (mapped pages can be evicted and refaulted, which is good for RSS but bad
for worst-case scroll latency under memory pressure). Chunked reads give predictable, boundable latency
and are much easier to make cancellable and to report progress for. Revisit `mmap` only after chunked
reads are measured and shown insufficient for "near-instant open."

### Indexing: incremental line index is already the right shape — extend, don't replace
`LineManager`'s augmented red-black tree already gives O(log n) line/offset/byte lookups (Phase 1 §3).
Nothing here needs replacing for "go to line N" or scrollbar metrics. The two real gaps are (a) building
it without the redundant substring materialization (Phase 2 #4, a small fix), and (b) it currently
requires the whole `NSMutableString` to exist before `rebuild()` can run — once loading is chunked, the
line index needs to be extended incrementally *as* chunks arrive, rather than in one `rebuild()` call at
the end.

### Decoding: keep bytes as the source of truth for the *loading* path only
Don't attempt to replace `StringView`'s `NSMutableString` as the *edited* document's source of truth —
that's a much larger, riskier change for a benefit that Phase 2 #1/#2 already dwarf. Do introduce a
byte-oriented ingestion layer for the *load* path: read fixed-size chunks, decode only what's needed to
discover line boundaries and feed the line index incrementally, handle multi-byte UTF-8 sequences split
across chunk boundaries by holding back the trailing incomplete sequence to prepend to the next chunk.
This is exactly the kind of new, from-scratch code where `~Copyable`/`Span`/`RawSpan` (verified available,
Phase 1 §10) are worth adopting immediately — no legacy call sites to migrate, and it eliminates ARC
overhead on a hot loading path that will process gigabytes of chunks.

### Rendering: no change needed to the layout strategy
Phase 1 §5 already confirms viewport-scoped custom Core Text layout. The `layoutLines(toLocation:)` O(n)
path had zero remaining call sites (verified and removed — see Phase 1 §5). **TextKit 2
would not be an improvement here**: this codebase already has what TextKit 2 is trying to provide
(viewport-scoped incremental layout) via a simpler, more auditable custom path, without inheriting
TextKit 2's own IME/accessibility/RTL edge cases on macOS. Do not migrate to it.

### Search: fix the wiring, not the engine
`FindSearchEngine` already does the right thing (Phase 2 #5) — async, debounced, cancellable. The fix is
wiring `FindPanelController` to it instead of the synchronous `SearchController`, not building new search
infrastructure. Add streaming/partial-result reporting (matches found so far, updated as the scan
progresses) so a full-document regex search on 2 GB shows progress instead of appearing frozen for
however long the scan takes.

### Highlighting: fix the eager full parse, keep the lazy per-line highlighting
Per-line highlighting (Phase 1 §8) is already correctly viewport-scoped and lazy — no change needed there.
The fix is making the *initial parse* non-blocking and, ideally, incremental/degradable: for files above
some size threshold, either (a) always route through `RunestoneStateBuilder.prepareAndApply`'s background
queue (currently opt-in) so it's never on the caller's thread, and/or (b) add an explicit large-file
degradation mode that skips the eager whole-document parse entirely and only parses+highlights the
currently-visible region on demand, parsing the rest incrementally in the background while idle. (b) is
the Sublime-Text-like answer — Sublime does not syntax-highlight distant regions of a huge file
until they're viewed. This is worth the complexity here specifically because Phase 2 #2's cost is
plausibly the single largest "time to open" number in the whole audit.

### Undo: bound it
Cap undo-stack depth/total bytes, and stop cloning the full string for batch operations
(`TextInputView.swift:1935`) — batch/replace-all undo should record the same delta-list shape normal
edits already use (a list of (range, replacement) pairs), not a full-document snapshot.

### Saving: patch small edits, keep atomic replace for anything larger
For the common case (one or a few small edits since last save), write only the changed byte ranges using
`FileHandle` seek+write rather than rewriting the whole file — safe as long as the edit doesn't change the
file's total length in a way that shifts trailing bytes (which text edits almost always do, so in
practice this mostly helps in-place fixed-width scenarios). For the general case (arbitrary inserts/
deletes, which shift everything after the edit), atomic replacement (write to a temp file, `rename()`) is
still the correct default for data safety — it is the only strategy that can't corrupt the file on a crash
mid-write. Given saving is entirely outside this library (Phase 1 §9), this is guidance for the host app,
not a Runestone change.

### What's not worth doing
- A custom executor for the render path: no actor contention exists on the render path today (Phase 3).
- Migrating to TextKit 2: strictly worse for this codebase's needs than what already exists.
- A rope/piece-table rewrite before fixing Phases 2 #1/#2: high risk, and the dominant costs live
  elsewhere.
- `mmap` before chunked reads are tried and measured: real correctness hazards (truncation, SIGBUS) for a
  benefit that's unproven relative to plain chunked I/O until measured.

---

## Phase 5 — Deliverables

### 1. This document
`PERFORMANCE_AUDIT.md`, findings ranked above by impact.

### 2. Benchmark harness
See `Tools/PerfHarness/` (executable SPM target `PerfHarness`) and
`Tools/PerfHarness/generate_fixtures.py` (synthetic file generator: 10 MB/100 MB/500 MB/2 GB ×
{many-short-lines, few-mega-lines, mixed-unicode-emoji, CRLF, invalid-UTF-8}). The harness measures, per
the brief: open + first-frame-proxy time, peak RSS/memory growth, simulated scroll frame time, keystroke
latency at start/middle/end, go-to-line at 50%/100%, literal+regex search, save-after-one-edit. It
exercises `TextViewState`/`TextView`/`SearchController` directly (headless, no `NSWindow`), since those
are where Phase 1/2's findings live; real on-screen frame time additionally needs an Instruments-driven
pass (Phase 5 §4) since a headless CLI can't drive actual `CALayer` compositing.

**Preliminary results already gathered against ~10-12 MB fixtures** (three orders of magnitude below the
500 MB–2 GB target, run during this audit to sanity-check the harness itself) directly substantiate two
of the Phase 2 findings with real numbers rather than pure hypothesis — see Phase 2 #2 (eager tree-sitter
parse: 0.17s→3.96s and 156 MB→782 MB RSS just from enabling highlighting on a 12 MB file) and Phase 2 #8
(mega-line variant: 5.2ms→40.9ms keystroke latency vs. a short-line file of the same byte size). Running
the same commands against the 100 MB/500 MB/2 GB tiers is the immediate next step and was not done in this
audit session — generating and parsing multi-GB fixtures takes minutes per run and is best done as a
deliberate, separate pass (e.g. overnight/CI) rather than interactively:

```
python3 Tools/PerfHarness/generate_fixtures.py --out Fixtures --sizes 100mb,500mb,2gb --variants all
swift run -c release PerfHarness open Fixtures/short_lines_500mb.txt
swift run -c release PerfHarness open Fixtures/short_lines_500mb.txt --highlighted
# ...repeat per command/variant/size; redirect stdout to a .csv to accumulate results.
```

### 3. Phased migration plan
1. **Debounce the EIP bridge (Phase 2 #1)** — highest win, lowest risk. **Partially done.** Added a
   200ms coalescing window (matching `LSPDocumentSyncService`'s default) in front of
   `RunestoneEditorAdapter.refreshDocument()` and `RunestoneWorkbenchEditorAdapter`'s content refresh
   (split out of the old `refreshLiveDocumentFromTextView`, which turned out to also run the full
   O(document) bridge on every *selection* change, not just every edit — now only the debounced
   content path does that; selection/scroll updates stay synchronous and cheap). Both are `EventBus`
   sources, and `Workspace`/`LSPWorkspaceSyncBridge`/anything else subscribed downstream inherits the
   lower event rate for free — confirmed by reading `Workspace.handleEditorEvent` (forwards 1:1, no
   batching of its own), so no separate fix was needed at that layer for the *frequency* problem.
   **Not done**: routing `LSPWorkspaceSyncBridge`'s `.documentChanged` handling through
   `enqueueChange`/incremental sync instead of `notifyFullChange` — that's a separate *payload size*
   problem (sends the whole document over the LSP wire per sync, not just a diff), and fixing it needs
   real edit-delta plumbing (range + replacement text) threaded through `TextViewDelegate` →
   `EditorAdapter` → `Workspace`, none of which currently carries deltas past `TextInputView` — a
   materially larger, riskier change than the debounce, deliberately left for a separate pass.
   Verify with the harness's keystroke-latency benchmark before/after.
2. **Wire `FindPanelController` to `FindSearchEngine`** instead of `SearchController` (Phase 2 #5).
   **Done.** Search-as-you-type and document-change refresh while the panel is open are now debounced
   200ms and run off the main actor; Next/Previous use `findNext`/`findPrevious` (O(distance), not a
   full recount). **Not done**: Replace All still goes through the old synchronous `SearchController`
   path (`FindSearchEngine.replaceAll` returns a whole new `String`, not per-match ranges, so it can't
   feed `BatchReplaceSet`'s delta-based undo without further work), and `FindSearchEngine`'s scan loop
   still has no internal `Task.isCancelled` check, so a stale off-main search on a huge file still runs
   to completion before its result is discarded (wastes CPU, doesn't block the UI). Verify: find-panel
   typing no longer blocks the main thread on a large synthetic file (measure with Instruments' Time
   Profiler on main thread during a search).
3. **Fix `LineManager.rebuild()`'s redundant substring calls** (Phase 2 #4) — **done.** Replaced both
   `stringView.string.substring(with:)` calls in `rebuild()` with `ByteCount(totalLength * 2)`, matching
   the pattern `setLength(of:to:newLine:)`/`insertLine(ofLength:after:)` already used. Verify: open-time
   allocation count drops roughly in half on the harness's Allocations-instrument pass (not yet measured
   with Instruments — the full test suite and a `SmokeTest` run confirm correctness, not the allocation
   delta).
4. **Make the eager full-document parse non-blocking and cancellable by default** (Phase 2 #2) — route
   `TextViewState` construction through `RunestoneStateBuilder.prepareAndApply` universally (or make an
   equivalent the default rather than opt-in), and make the underlying `ts_parser_parse` cancellable
   mid-flight for the "user closed the file/opened a different one before parse finished" case. This is
   the first phase that touches the open-file "happy path," so it needs a feature-flag rollout and A/B
   time-to-open measurement against the previous synchronous behavior before removing the flag.
5. **Bound the undo stack; delta-ify batch-replace undo** (Phase 2 #7) — **delta-ification done;
   hard depth cap not done (see below).** `TextEditHelper.apply(_:)` now computes an inverse
   `[BatchReplaceSet.Replacement]` (range + old text) alongside the new string, in the same pass
   that builds it — sized to the edited ranges, not the document. `setStringWithUndoAction` registers
   that inverse instead of cloning `stringView.string`; undo replays it through `replaceText(in:)`,
   which computes its own inverse in turn, so undo/redo/undo/... never holds more than the edited
   ranges' worth of text per step regardless of document size — the "N replace-alls ≈ N × document
   size" blow-up this item was written to fix is gone. Verified with
   `Tests/RunestoneTests/TextEditHelperTests.swift` (inverse correctness, including cases where
   replacement length differs from the original range, which shifts later ranges) and
   `Tests/RunestoneTests/BatchReplaceUndoTests.swift` (round-trips through the real `TextView` +
   `UndoManager`, including a many-replacement stress case).
   **Found and fixed a separate, pre-existing correctness bug while adding that test coverage** —
   this is a Swift-6-adjacent-looking but actually orthogonal bug, called out per the audit's own
   "distinguish correctness problem from performance problem" rule: **`TextView.replaceText(in:
   BatchReplaceSet)` followed by `undoManager.undo()` crashed unconditionally**
   (`NSInternalInconsistencyException`, "endUndoGrouping called with no matching begin"). Root
   cause: `setStringWithUndoAction` unconditionally called `timedUndoManager.endUndoGrouping()` /
   `beginUndoGrouping()` around itself; when this method runs *as* an undo/redo invocation (i.e. as
   the body of the closure `registerUndo` scheduled), `UndoManager` already has its own implicit
   group open around that invocation, and closing it early leaves the manager's bookkeeping
   inconsistent once the invocation returns. This bug existed before any change in this session —
   confirmed by reproducing it against the unmodified code via `git stash` — and had no prior test
   coverage of `TextView.replaceText(in:)` + real undo, which is why it shipped unnoticed. Fixed by
   only managing grouping explicitly for a top-level (non-nested) call, via
   `timedUndoManager.isUndoing || timedUndoManager.isRedoing`; a nested call now relies on
   `UndoManager`'s own grouping, which is what it expects. **Not done**: a hard `levelsOfUndo` /
   byte-budget cap on the undo stack. Deliberately left alone — bounding *this* item's specific
   memory-blowup source (delta-ification, above) already removes the case that motivated the cap,
   and imposing a hard undo-depth limit is a product decision (how far back should any edit remain
   undoable) that affects every edit, not just batch replace, so it shouldn't be decided unilaterally
   here.
6. **Build the chunked-loading + incremental-line-index ingestion path** (Phase 4's biggest structural
   change) — this is the only phase that actually removes the "must hold the whole file as a `String`"
   constraint, so it's what actually unlocks "memory usage that does not scale linearly with file size."
   Ship it as an *additional* entry point alongside the existing `TextViewState(text: String, ...)`
   initializer (don't remove the String-based path — small files and programmatic use of the library
   still want it), gated so existing callers are unaffected. Verify: peak-RSS-vs-file-size benchmark
   should go from linear to roughly flat (bounded by visible-window size + line-index overhead) for files
   that use the new path.
7. **(Separately, not blocking any of the above) Swift 6 language-mode migration** — 8,292 diagnostics
   across 50 files is a multi-week correctness project on its own; track it independently, and don't let
   it gate any of steps 1–6, since none of those fixes depend on the package being in Swift 6 mode.

Between phases, the library stays shippable at every step: 1–5 are behavior-preserving perf fixes with no
API changes; 6 is additive; 7 is fully decoupled.

### 4. Instrumentation

os_signpost points to add (name, category, location, what to look for):

| Signpost name | Location | Look for |
|---|---|---|
| `TextViewState.prepare` | `TextViewState.swift:61` (wrap `prepare(with:)`) | Time Profiler: is this on the main thread? Duration vs. file size — confirms/refutes Phase 2 #2's cost model. |
| `TreeSitterParser.parse` | `TreeSitterParser.swift:31` | Time Profiler: fraction of open time spent in `ts_parser_parse_string_encoding` specifically, vs. `LineManager.rebuild`. |
| `LineManager.rebuild` | `LineManager.swift:51` | Allocations: object-count spike from the per-line `substring(with:)` calls (Phase 2 #4) — should roughly halve after the fix. |
| `StringView.replaceText` | `StringView.swift:49` | Time Profiler + Allocations: per-edit duration vs. edit position (start/middle/end of buffer) — tests Phase 2 #3's position-dependence hypothesis. |
| `RunestoneEditorAdapter.refreshDocument` | `RunestoneEditorAdapter.swift:91` | Time Profiler: duration and *frequency* — frequency should drop to ~1 per debounce window after migration step 1, not 1 per keystroke. |
| `IndexingService.indexDocument` | `IndexingService.swift:32` | Swift Concurrency template: how many of these actor jobs are in flight/queued during rapid typing — should collapse to one after debouncing. |
| `LSPWorkspaceSyncBridge.handle` | `LSPWorkspaceSyncBridge.swift:52` | System Trace: bytes serialized per event before/after switching from `notifyFullChange` to `enqueueChange`. |
| `FoldingController.recompute` | `FoldingController.swift:294` | Time Profiler: only fires when folding is enabled — confirms this cost is conditional, and measures its magnitude at high line counts. |
| `SearchController.search` | `SearchController.swift:16` | Time Profiler: main-thread duration during find-panel typing — should disappear from the main thread after migration step 2. |
| `LayoutManager.layoutLinesInViewport` | `LayoutManager.swift:516` | System Trace / Core Animation: per-scroll-frame duration — this is the actual "smooth scrolling" metric. |

Instruments templates and what each is for:
- **Time Profiler** — wall-clock hot spots for open, parse, and per-keystroke work; use with the signposts
  above to separate "waiting on tree-sitter" from "waiting on the EIP bridge" from "waiting on
  `NSMutableString` mutation."
- **Allocations** — object/byte churn during load (confirms/refutes the rebuild-substring doubling, Phase
  2 #4) and during typing (confirms whether the full-document `String` bridge, Phase 2 #1, is actually
  allocating a new multi-GB buffer per keystroke or whether COW/sharing mitigates it more than expected).
- **VM Tracker** — resident vs. compressed vs. swapped memory as file size grows; this is the direct
  measurement for "memory usage that does not scale linearly with file size," and the only way to see
  whether a future `mmap`-based loader's pages are actually staying resident or getting evicted under
  pressure.
- **System Trace** — thread scheduling and main-thread blockage; use this to catch the synchronous
  `SearchController` scan (Phase 2 #5) and the synchronous parse (Phase 2 #2) actually blocking the main
  thread/run loop, which Time Profiler alone can undercount if sampling misses a short-but-blocking call.
- **Swift Concurrency** — actor contention and Task backlog in the EIP layer; specifically to watch
  `IndexingService`/`Workspace`/LSP actors queue up redundant full-document jobs during rapid typing
  before the debounce fix (migration step 1), and confirm the queue collapses to single in-flight jobs
  after it.

---

## Ground-rule compliance notes

- The audit and the harness described in §2 involved no production code changes (the harness is new,
  additive tooling under `Tools/`). A subsequent round of fixes, explicitly requested afterward, *did*
  change `Sources/Runestone` — each such change is called out inline (search this document for
  "**fixed**") and summarized in §3's migration-plan status; nothing was changed silently or outside
  what's documented here.
- Claims are labeled CONFIRMED (directly read in code or directly measured) or HYPOTHESIS (plausible cost
  model stated, with the specific harness benchmark that would confirm it) throughout Phases 2–3.
- Phase 3's Swift-6-language-mode finding is deliberately kept separate from the performance
  recommendations in Phase 4/migration plan — per the brief, "correctness problem under Swift 6" and
  "performance problem" are not the same project here, and conflating them would misprioritize both.
- Every fix applied is covered by new or existing tests, and the full suite (500 tests as of the last
  fix) passes consistently across repeated runs. One pre-existing, unrelated flaky test class
  (`EditorHostCacheTests`, timing-sensitive under parallel test load) was independently confirmed to
  fail intermittently even with zero changes applied — not a regression from anything in this document.
