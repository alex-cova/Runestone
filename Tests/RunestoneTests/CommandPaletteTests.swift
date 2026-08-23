import XCTest
@testable import Runestone

@MainActor
final class CommandRegistryTests: XCTestCase {
    func testRegistersAndFilters() {
        let registry = CommandRegistry()
        registry.register(EditorCommand(id: "file.save", title: "Save", group: "File") {})
        registry.register(EditorCommand(id: "file.saveAs", title: "Save As…", group: "File") {})
        registry.register(EditorCommand(id: "goto.line", title: "Go to Line…", group: "Goto") {})

        let filtered = registry.filtered(query: "save")
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.title.localizedCaseInsensitiveContains("save") })
        XCTAssertEqual(registry.command(id: "goto.line")?.title, "Go to Line…")
    }

    func testRegisteringSameIDReplacesTheExistingCommand() {
        let registry = CommandRegistry()
        registry.register(EditorCommand(id: "x", title: "Old Title", group: "G") {})
        registry.register(EditorCommand(id: "x", title: "New Title", group: "G") {})
        XCTAssertEqual(registry.commands.count, 1)
        XCTAssertEqual(registry.command(id: "x")?.title, "New Title")
    }

    func testCommandGroupsPreserveFirstSeenOrder() {
        let registry = CommandRegistry()
        registry.register(EditorCommand(id: "1", title: "One", group: "Goto") {})
        registry.register(EditorCommand(id: "2", title: "Two", group: "File") {})
        registry.register(EditorCommand(id: "3", title: "Three", group: "Goto") {})

        let groups = registry.commandGroups
        XCTAssertEqual(groups.map(\.name), ["Goto", "File"])
        XCTAssertEqual(groups[0].commands.map(\.id), ["1", "3"])
        XCTAssertEqual(groups[1].commands.map(\.id), ["2"])
    }
}

@MainActor
final class PaletteQueryScopeTests: XCTestCase {
    func testGreaterThanPrefixAlwaysResolvesToCommands() {
        XCTAssertEqual(PaletteQueryScope.resolve(query: ">save", mode: .textActions), .commands("save"))
        XCTAssertEqual(PaletteQueryScope.resolve(query: ">save", mode: .quickOpen), .commands("save"))
    }

    func testSlashAndHashPrefixesAlwaysResolveToFiles() {
        XCTAssertEqual(PaletteQueryScope.resolve(query: "/main.swift", mode: .textActions), .files("main.swift"))
        XCTAssertEqual(PaletteQueryScope.resolve(query: "#main.swift", mode: .commands), .files("main.swift"))
    }

    func testBareQueryHonorsTheModesDefault() {
        XCTAssertEqual(PaletteQueryScope.resolve(query: "json", mode: .textActions), .textActions("json"))
        XCTAssertEqual(PaletteQueryScope.resolve(query: "json", mode: .commands), .commands("json"))
        XCTAssertEqual(PaletteQueryScope.resolve(query: "json", mode: .quickOpen), .files("json"))
        XCTAssertEqual(PaletteQueryScope.resolve(query: "json", mode: .symbols), .symbols("json"))
    }

    func testLoneCommandsPrefixYieldsAnEmptyRemainder() {
        XCTAssertEqual(PaletteQueryScope.resolve(query: ">", mode: .textActions), .commands(""))
    }

    func testPrefixRemainderIsTrimmedOfLeadingWhitespace() {
        XCTAssertEqual(PaletteQueryScope.resolve(query: "> save", mode: .textActions), .commands("save"))
    }

    func testQueryAccessorReturnsTheAssociatedString() {
        XCTAssertEqual(PaletteQueryScope.commands("save").query, "save")
        XCTAssertEqual(PaletteQueryScope.files("main.swift").query, "main.swift")
    }
}

@MainActor
final class EditorPaletteModelTests: XCTestCase {
    func testShowCommandsResetsQueryAndSelectionAndPresents() {
        let model = EditorPaletteModel()
        model.query = "stale"
        model.selectedIndex = 3
        model.showCommands()
        XCTAssertEqual(model.mode, .commands)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertTrue(model.isPresented)
    }

    func testHideClearsPresentation() {
        let model = EditorPaletteModel()
        model.showQuickOpen()
        model.hide()
        XCTAssertFalse(model.isPresented)
    }

    func testMoveSelectionClampsToValidRange() {
        let model = EditorPaletteModel()
        model.selectedIndex = 0
        model.moveSelection(by: -1, count: 5)
        XCTAssertEqual(model.selectedIndex, 0)
        model.moveSelection(by: 10, count: 5)
        XCTAssertEqual(model.selectedIndex, 4)
    }

    func testMoveSelectionIsNoOpWhenCountIsZero() {
        let model = EditorPaletteModel()
        model.selectedIndex = 2
        model.moveSelection(by: 1, count: 0)
        XCTAssertEqual(model.selectedIndex, 2)
    }

    func testClampSelectionPullsSelectionBackWhenCountShrinks() {
        let model = EditorPaletteModel()
        model.selectedIndex = 9
        model.clampSelection(count: 3)
        XCTAssertEqual(model.selectedIndex, 2)
    }
}

final class QuickOpenFileRankerTests: XCTestCase {
    func testRanksByFuzzyMatchAgainstPathRelativeToRoot() {
        let root = URL(fileURLWithPath: "/project")
        let files = [
            URL(fileURLWithPath: "/project/utils/index.ts"),
            URL(fileURLWithPath: "/project/models/user.swift")
        ]
        let ranked = QuickOpenFileRanker.rank(query: "index", files: files, root: root, limit: 10)
        XCTAssertEqual(ranked.first?.lastPathComponent, "index.ts")
    }

    func testFallsBackToLastPathComponentWhenURLIsNotUnderRoot() {
        let root = URL(fileURLWithPath: "/project")
        let files = [URL(fileURLWithPath: "/elsewhere/readme.md")]
        let ranked = QuickOpenFileRanker.rank(query: "readme", files: files, root: root, limit: 10)
        XCTAssertEqual(ranked.count, 1)
    }
}
