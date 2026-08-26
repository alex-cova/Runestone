import XCTest
@testable import Runestone

final class TextEditHelperTests: XCTestCase {
    private func makeHelper(text: String) -> (TextEditHelper, StringView) {
        let stringView = StringView(string: text)
        let lineManager = LineManager(stringView: stringView)
        lineManager.rebuild()
        let helper = TextEditHelper(stringView: stringView, lineManager: lineManager, lineEndings: .lf)
        return (helper, stringView)
    }

    func testApplyProducesTheSameStringAsStringByApplying() {
        let (helper, _) = makeHelper(text: "aaa bbb ccc")
        let batch = BatchReplaceSet(replacements: [
            .init(range: NSRange(location: 0, length: 3), text: "X"),
            .init(range: NSRange(location: 8, length: 3), text: "YY")
        ])
        let application = helper.apply(batch)
        XCTAssertEqual(application.newString as String, "X bbb YY")
    }

    /// This is the case that makes computing the inverse non-trivial: two replacements whose
    /// lengths differ from what they replace, so the second replacement's position in the
    /// resulting string has shifted relative to its original range.
    func testInverseReplacementsRestoreTheOriginalStringWhenLengthsDiffer() {
        let original = "aaa bbb ccc"
        let (helper, _) = makeHelper(text: original)
        let batch = BatchReplaceSet(replacements: [
            .init(range: NSRange(location: 0, length: 3), text: "X"),   // shrinks by 2
            .init(range: NSRange(location: 8, length: 3), text: "YY")   // shrinks by 1
        ])
        let application = helper.apply(batch)
        XCTAssertEqual(application.newString as String, "X bbb YY")

        // Applying the inverse to a fresh helper seeded with the *new* string should restore the
        // original — exactly what undo does by feeding `inverseReplacements` back through
        // `replaceText(in:)`.
        let (undoHelper, _) = makeHelper(text: application.newString as String)
        let restored = undoHelper.string(byApplying: BatchReplaceSet(replacements: application.inverseReplacements))
        XCTAssertEqual(restored as String, original)
    }

    func testInverseReplacementsRestoreTheOriginalStringWhenReplacementGrows() {
        let original = "a b c"
        let (helper, _) = makeHelper(text: original)
        let batch = BatchReplaceSet(replacements: [
            .init(range: NSRange(location: 0, length: 1), text: "AAA"), // grows by 2
            .init(range: NSRange(location: 4, length: 1), text: "C")    // same length
        ])
        let application = helper.apply(batch)
        XCTAssertEqual(application.newString as String, "AAA b C")

        let (undoHelper, _) = makeHelper(text: application.newString as String)
        let restored = undoHelper.string(byApplying: BatchReplaceSet(replacements: application.inverseReplacements))
        XCTAssertEqual(restored as String, original)
    }

    func testInverseReplacementsAreDeltaSizedNotDocumentSized() {
        // A long document with only two small edits — the inverse should carry just the two old
        // fragments, not a copy of the whole document (PERFORMANCE_AUDIT.md Phase 2 #7).
        let original = String(repeating: "x", count: 10_000) + "NEEDLE" + String(repeating: "y", count: 10_000)
        let (helper, _) = makeHelper(text: original)
        let batch = BatchReplaceSet(replacements: [
            .init(range: NSRange(location: 10_000, length: 6), text: "FOUND")
        ])
        let application = helper.apply(batch)
        XCTAssertEqual(application.inverseReplacements.count, 1)
        XCTAssertEqual(application.inverseReplacements.first?.text, "NEEDLE")
        XCTAssertLessThan(application.inverseReplacements.first?.text.utf16.count ?? .max, 100)
    }

    func testOverlappingReplacementsKeepOnlyTheFirstAndItsInverseStillRoundTrips() {
        let original = "abcdef"
        let (helper, _) = makeHelper(text: original)
        let batch = BatchReplaceSet(replacements: [
            .init(range: NSRange(location: 0, length: 3), text: "XYZ"),
            .init(range: NSRange(location: 2, length: 3), text: "OVERLAP") // overlaps the first, should be dropped
        ])
        let application = helper.apply(batch)
        XCTAssertEqual(application.newString as String, "XYZdef")

        let (undoHelper, _) = makeHelper(text: application.newString as String)
        let restored = undoHelper.string(byApplying: BatchReplaceSet(replacements: application.inverseReplacements))
        XCTAssertEqual(restored as String, original)
    }
}
