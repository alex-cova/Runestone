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

    func testTabListEngineSelectionAfterClose() {
        XCTAssertEqual(TabListEngine.selectionIndexAfterClose(closing: 1, selected: 1, count: 3), 1)
    }

    func testWorkbenchAggregatesDocuments() {
        let bench = EditorWorkbench()
        let doc = WorkbenchDocument(displayName: "one", text: "1")
        bench.openDocument(doc)
        XCTAssertEqual(bench.allDocuments().count, 1)
    }

    func testWorkbenchAdapterReportsOpenDocuments() {
        let bench = EditorWorkbench()
        let doc = WorkbenchDocument(displayName: "one", text: "hello")
        bench.openDocument(doc)
        let adapter = RunestoneWorkbenchEditorAdapter(workbench: bench)
        XCTAssertEqual(adapter.openDocuments.count, 1)
        XCTAssertEqual(adapter.currentDocument?.displayName, "one")
    }
}
