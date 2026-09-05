import XCTest
import EditorIntelligence
@testable import Runestone

final class WorkbenchTests: XCTestCase {
    func testEditorPaneOpensAndSelects() {
        let pane = EditorPane()
        let doc = WorkbenchDocument(displayName: "a.swift", text: "let a = 1")
        pane.openDocument(doc)
        XCTAssertEqual(pane.selectedDocument?.id, doc.id)
        XCTAssertEqual(pane.documents.count, 1)
    }

    func testTemporaryTabReusesCleanSlot() {
        let pane = EditorPane()
        let first = WorkbenchDocument(displayName: "a.txt", text: "a")
        let second = WorkbenchDocument(displayName: "b.txt", text: "b")
        pane.openDocument(first, asTemporary: true)
        pane.openDocument(second, asTemporary: true)
        XCTAssertEqual(pane.documents.count, 1)
        XCTAssertEqual(pane.selectedDocument?.displayName, "b.txt")
        XCTAssertTrue(pane.isTemporary(pane.documents[0]))
    }

    func testTemporaryTabDoesNotReuseADirtySlot() {
        let pane = EditorPane()
        let first = WorkbenchDocument(displayName: "a.txt", text: "a")
        first.isDirty = true
        let second = WorkbenchDocument(displayName: "b.txt", text: "b")
        pane.openDocument(first, asTemporary: true)
        pane.openDocument(second, asTemporary: true)
        XCTAssertEqual(pane.documents.count, 2)
        XCTAssertEqual(pane.documents[0].displayName, "a.txt")
        XCTAssertEqual(pane.selectedDocument?.displayName, "b.txt")
    }

    func testTemporaryTabReuseCopiesFileBackedState() async throws {
        let firstURL = FileManager.default.temporaryDirectory.appendingPathComponent("first-\(UUID().uuidString).txt")
        let secondURL = FileManager.default.temporaryDirectory.appendingPathComponent("second-\(UUID().uuidString).txt")
        try "first body\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second body\n".write(to: secondURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let first = try await WorkbenchDocument.load(contentsOf: firstURL)
        let second = try await WorkbenchDocument.load(contentsOf: secondURL)
        let pane = EditorPane()
        pane.openDocument(first, asTemporary: true)
        let reused = pane.openDocument(second, asTemporary: true)
        XCTAssertEqual(pane.documents.count, 1)
        XCTAssertEqual(reused.displayName, secondURL.lastPathComponent)
        XCTAssertTrue(reused.isFileBacked)
        XCTAssertNotNil(reused.pendingState)
        XCTAssertNotNil(reused.rangeReader)
    }

    func testTabListEngineSelectionAfterClose() {
        XCTAssertEqual(TabListEngine.selectionIndexAfterClose(closing: 1, selected: 1, count: 3), 1)
    }

    func testDisambiguatedTitlesAppendsParentDirectoryOnCollision() {
        let urls = [
            URL(fileURLWithPath: "/project/utils/index.ts"),
            URL(fileURLWithPath: "/project/models/index.ts")
        ]
        let titles = TabListEngine.disambiguatedTitles(fileNames: ["index.ts", "index.ts"], urls: urls)
        XCTAssertEqual(titles, ["index.ts — utils", "index.ts — models"])
    }

    func testDisambiguatedTitlesLeavesUniqueNamesUnchanged() {
        let urls = [URL(fileURLWithPath: "/project/a.swift"), URL(fileURLWithPath: "/project/b.swift")]
        let titles = TabListEngine.disambiguatedTitles(fileNames: ["a.swift", "b.swift"], urls: urls)
        XCTAssertEqual(titles, ["a.swift", "b.swift"])
    }

    func testDisambiguatedTitlesLeavesUntitledBuffersUnchangedEvenOnCollision() {
        let titles = TabListEngine.disambiguatedTitles(fileNames: ["untitled", "untitled"], urls: [nil, nil])
        XCTAssertEqual(titles, ["untitled", "untitled"])
    }

    func testWorkbenchAggregatesDocuments() {
        let bench = EditorWorkbench()
        let doc = WorkbenchDocument(displayName: "one", text: "1")
        bench.openDocument(doc)
        XCTAssertEqual(bench.allDocuments().count, 1)
    }

    func testWorkbenchDocumentLoadReusesPendingState() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "line one\nline two\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try await WorkbenchDocument.load(contentsOf: url)
        XCTAssertEqual(document.displayName, url.lastPathComponent)
        XCTAssertTrue(document.isFileBacked)
        XCTAssertEqual(document.text, "")
        XCTAssertEqual(document.pendingState?.stringView.string as String?, "line one\nline two\n")
        XCTAssertEqual(document.url, url)
        XCTAssertNotNil(document.pendingState)
        XCTAssertEqual(document.pendingState?.parsePolicy, .viewport)
        XCTAssertGreaterThan(document.pendingState?.lineManager.lineCount ?? 0, 1)
    }

    func testWorkbenchAdapterReportsOpenDocuments() {
        let bench = EditorWorkbench()
        let doc = WorkbenchDocument(displayName: "one", text: "hello")
        bench.openDocument(doc)
        let adapter = RunestoneWorkbenchEditorAdapter(workbench: bench)
        XCTAssertEqual(adapter.openDocuments.count, 1)
        XCTAssertEqual(adapter.currentDocument?.displayName, "one")
    }

    func testSplitActivePaneAddsSecondPane() {
        let bench = EditorWorkbench()
        let originalPaneID = bench.activePaneID
        let newPane = bench.splitActivePane(edge: .trailing)
        XCTAssertEqual(bench.panes.count, 2)
        XCTAssertEqual(bench.activePaneID, newPane.id)
        XCTAssertNotEqual(bench.activePaneID, originalPaneID)
    }

    func testClosePaneFallsBackToRemainingPane() {
        let bench = EditorWorkbench()
        let firstPaneID = bench.activePaneID
        let secondPane = bench.splitActivePane(edge: .trailing)
        bench.closePane(secondPane.id)
        XCTAssertEqual(bench.panes.count, 1)
        XCTAssertEqual(bench.activePaneID, firstPaneID)
    }

    func testRestorationRoundTripPreservesTabsAndSelection() throws {
        let bench = EditorWorkbench()
        let docA = WorkbenchDocument(displayName: "a.txt", text: "alpha")
        let docB = WorkbenchDocument(displayName: "b.txt", text: "beta")
        bench.openDocument(docA)
        bench.openDocument(docB)
        bench.activePane.selectDocument(docA.id)

        let encoded = try JSONEncoder().encode(bench.makeRestorationState())
        let decoded = try JSONDecoder().decode(EditorRestorationState.self, from: encoded)

        let restored = EditorWorkbench()
        restored.restore(from: decoded)
        XCTAssertEqual(restored.panes.count, 1)
        XCTAssertEqual(restored.activePane.documents.count, 2)
        XCTAssertEqual(restored.activePane.selectedDocument?.displayName, "a.txt")
        XCTAssertEqual(restored.activePane.documents.map(\.displayName), ["a.txt", "b.txt"])
    }

    func testRestorationPreservesSplitLayout() throws {
        let bench = EditorWorkbench()
        bench.openDocument(WorkbenchDocument(displayName: "left", text: "L"))
        let rightPane = bench.splitActivePane(edge: .trailing)
        bench.openDocument(WorkbenchDocument(displayName: "right", text: "R"), in: rightPane)

        let encoded = try JSONEncoder().encode(bench.makeRestorationState())
        let decoded = try JSONDecoder().decode(EditorRestorationState.self, from: encoded)

        let restored = EditorWorkbench()
        restored.restore(from: decoded)
        XCTAssertEqual(restored.panes.count, 2)
        XCTAssertEqual(restored.activePane.selectedDocument?.displayName, "right")
        let leftPane = restored.panes.first { $0.id != restored.activePaneID }
        XCTAssertEqual(leftPane?.selectedDocument?.displayName, "left")
    }
}
