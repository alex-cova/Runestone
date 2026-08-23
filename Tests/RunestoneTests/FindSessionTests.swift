import XCTest
@testable import Runestone

@MainActor
final class FindSessionTests: XCTestCase {
    private func searched(_ session: FindSession, query: String, in text: String, anchor: Int = 0) {
        session.query = query
        let outcome = FindSearchEngine.search(options: session.searchOptions(), in: text, anchorLocation: anchor)
        session.applySearchOutcome(outcome)
    }

    func testMatchCountLabelReflectsState() {
        let session = FindSession()
        XCTAssertEqual(session.matchCountLabel, "")

        searched(session, query: "zzz", in: "abc")
        XCTAssertEqual(session.matchCountLabel, "No matches")

        searched(session, query: "a", in: "a b a")
        XCTAssertEqual(session.matchCountLabel, "1 of 2")
    }

    func testMatchCountLabelSurfacesTheErrorMessage() {
        let session = FindSession()
        session.useRegex = true
        searched(session, query: "(unclosed", in: "text")
        XCTAssertNotNil(session.errorMessage)
        XCTAssertEqual(session.matchCountLabel, session.errorMessage)
    }

    func testShowFindAndShowReplaceSetReplaceMode() {
        let session = FindSession()
        session.showFind()
        XCTAssertTrue(session.isPresented)
        XCTAssertFalse(session.isReplaceMode)

        session.showReplace()
        XCTAssertTrue(session.isReplaceMode)
    }

    func testHideClearsHighlightsAndPresentation() {
        let session = FindSession()
        searched(session, query: "a", in: "a b a")
        session.hide()
        XCTAssertFalse(session.isPresented)
        XCTAssertEqual(session.matchCount, 0)
        XCTAssertNil(session.currentRange)
    }

    func testSelectNextWrapsAroundToTheFirstMatch() {
        let session = FindSession()
        let text = "a b a"
        searched(session, query: "a", in: text)
        XCTAssertEqual(session.currentIndex, 0)

        session.selectNext(in: text)
        XCTAssertEqual(session.currentIndex, 1)

        session.selectNext(in: text)
        XCTAssertEqual(session.currentIndex, 0, "Should wrap back to the first match")
    }

    func testSelectPreviousWrapsAroundToTheLastMatch() {
        let session = FindSession()
        let text = "a b a"
        searched(session, query: "a", in: text)
        XCTAssertEqual(session.currentIndex, 0)

        session.selectPrevious(in: text)
        XCTAssertEqual(session.currentIndex, 1, "Should wrap back to the last match")
    }

    func testReplaceCurrentReplacesAndReturnsNewSelection() {
        let session = FindSession()
        let text = "foo bar foo"
        searched(session, query: "foo", in: text)
        session.replacement = "BAZ"

        let result = session.replaceCurrent(in: text)
        XCTAssertEqual(result?.text, "BAZ bar foo")
        XCTAssertEqual(result?.selection, NSRange(location: 0, length: 3))
    }

    func testReplaceCurrentReturnsNilWithoutACurrentMatch() {
        let session = FindSession()
        XCTAssertNil(session.replaceCurrent(in: "anything"))
    }

    func testReplaceAllReplacesEveryMatch() {
        let session = FindSession()
        let text = "foo bar foo"
        searched(session, query: "foo", in: text)
        session.replacement = "BAZ"

        let result = session.replaceAll(in: text)
        XCTAssertEqual(result, "BAZ bar BAZ")
    }

    func testMatchesSnapshotComparesQueryAndOptions() {
        let session = FindSession()
        session.query = "foo"
        session.matchCase = true
        let snapshot = FindSession.SearchSnapshot(query: "foo", matchCase: true, wholeWord: false, useRegex: false)
        XCTAssertTrue(session.matchesSnapshot(snapshot))

        session.query = "bar"
        XCTAssertFalse(session.matchesSnapshot(snapshot))
    }

    func testCappedHighlightRangesCentersWindowAroundCurrentIndex() {
        let matches = (0 ..< 20).map { NSRange(location: $0, length: 1) }
        let capped = FindSession.cappedHighlightRanges(matches: matches, currentIndex: 10, maxCount: 4)
        XCTAssertEqual(capped.count, 4)
        XCTAssertTrue(capped.contains(NSRange(location: 10, length: 1)))
    }

    func testFindRangesEnumeratesEveryMatch() throws {
        let ranges = try FindSession.findRanges(query: "a", in: "a b a b a", matchCase: false, wholeWord: false, useRegex: false)
        XCTAssertEqual(ranges.count, 3)
    }

    func testFindRangesThrowsOnInvalidRegex() {
        XCTAssertThrowsError(try FindSession.findRanges(query: "(unclosed", in: "text", matchCase: false, wholeWord: false, useRegex: true))
    }
}
