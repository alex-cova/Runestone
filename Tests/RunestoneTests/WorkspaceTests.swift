import XCTest
import EditorIntelligence

final class WorkspaceTests: XCTestCase {
    func testAddAndRemoveProject() async {
        let workspace = Workspace()
        let project = Project(url: URL(fileURLWithPath: "/tmp/test"), name: "test")
        await workspace.addProject(project)
        var projects = await workspace.allProjects()
        XCTAssertEqual(projects.count, 1)
        await workspace.removeProject(project.id)
        projects = await workspace.allProjects()
        XCTAssertTrue(projects.isEmpty)
    }

    func testOpenDocumentBecomesActive() async {
        let workspace = Workspace()
        let document = makeDocument(id: DocumentID(), text: "hello")
        await workspace.openDocument(document)
        let active = await workspace.activeDocument()
        XCTAssertEqual(active?.id, document.id)
        let all = await workspace.allOpenDocuments()
        XCTAssertEqual(all.count, 1)
    }

    func testHandleDocumentChangedEvent() async {
        let workspace = Workspace()
        let document = makeDocument(id: DocumentID(), text: "hello")
        await workspace.openDocument(document)
        let newSnapshot = TextSnapshot(version: 1, text: "hello world")
        await workspace.handleEditorEvent(.documentChanged(document.id, newSnapshot))
        let updated = await workspace.document(withID: document.id)
        XCTAssertEqual(updated?.text, "hello world")
        XCTAssertEqual(updated?.version, 1)
    }
}

private func makeDocument(id: DocumentID, text: String) -> Document {
    let snapshot = TextSnapshot(version: 0, text: text)
    let position = TextPosition(line: 0, column: 0, utf16Offset: 0)
    return Document(
        id: id,
        url: nil,
        displayName: "test",
        contentSnapshot: snapshot,
        selection: Selection(range: TextRange(start: position, end: position)),
        cursor: Cursor(position: position),
        viewport: Viewport(x: 0, y: 0, width: 100, height: 100)
    )
}
