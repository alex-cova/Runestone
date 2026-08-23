import XCTest
@testable import Runestone

final class FindSearchEngineTests: XCTestCase {
    func testLiteralSearchCountsAllMatchesCaseInsensitiveByDefault() {
        let options = FindSearchOptions(query: "foo")
        let outcome = FindSearchEngine.search(options: options, in: "foo Foo FOO bar", anchorLocation: 0)
        XCTAssertEqual(outcome.matchCount, 3)
        XCTAssertEqual(outcome.currentIndex, 0)
        XCTAssertEqual(outcome.currentRange, NSRange(location: 0, length: 3))
    }

    func testMatchCaseTrueMakesSearchCaseSensitive() {
        let options = FindSearchOptions(query: "foo", matchCase: true)
        let outcome = FindSearchEngine.search(options: options, in: "foo Foo FOO", anchorLocation: 0)
        XCTAssertEqual(outcome.matchCount, 1)
    }

    func testAnchorPicksTheFirstMatchAtOrAfterTheAnchorLocation() {
        // Matches "aa" at locations 0, 3, and 6. Anchored at 4, the match at 3 is before the
        // anchor and should be skipped in favor of the next one at 6.
        let text = "aa aa aa"
        let options = FindSearchOptions(query: "aa")
        let outcome = FindSearchEngine.search(options: options, in: text, anchorLocation: 4)
        XCTAssertEqual(outcome.currentIndex, 2)
        XCTAssertEqual(outcome.currentRange, NSRange(location: 6, length: 2))
    }

    func testAnchorPastAllMatchesWrapsToTheFirstMatch() {
        let text = "aa bb"
        let options = FindSearchOptions(query: "aa")
        let outcome = FindSearchEngine.search(options: options, in: text, anchorLocation: 100)
        XCTAssertEqual(outcome.currentIndex, 0)
        XCTAssertEqual(outcome.currentRange, NSRange(location: 0, length: 2))
    }

    func testEmptyQueryReturnsEmptyOutcome() {
        let outcome = FindSearchEngine.search(options: FindSearchOptions(query: ""), in: "anything", anchorLocation: 0)
        XCTAssertEqual(outcome, .empty)
    }

    func testNoMatchesReturnsEmptyOutcome() {
        let outcome = FindSearchEngine.search(options: FindSearchOptions(query: "zzz"), in: "abc", anchorLocation: 0)
        XCTAssertEqual(outcome, .empty)
    }

    func testWholeWordDoesNotMatchInsideALongerWord() {
        let options = FindSearchOptions(query: "cat", wholeWord: true)
        let outcome = FindSearchEngine.search(options: options, in: "cat category cat", anchorLocation: 0)
        XCTAssertEqual(outcome.matchCount, 2)
    }

    func testRegexSearchMatchesPattern() {
        let options = FindSearchOptions(query: "[0-9]+", useRegex: true)
        let outcome = FindSearchEngine.search(options: options, in: "abc 123 def 456", anchorLocation: 0)
        XCTAssertEqual(outcome.matchCount, 2)
        XCTAssertEqual(outcome.currentRange, NSRange(location: 4, length: 3))
    }

    func testRegexSearchSkipsZeroLengthMatches() {
        let options = FindSearchOptions(query: "x*", useRegex: true)
        let outcome = FindSearchEngine.search(options: options, in: "xx  xx", anchorLocation: 0)
        // Only the two non-empty "xx" runs should count, not the zero-length matches elsewhere.
        XCTAssertEqual(outcome.matchCount, 2)
    }

    func testInvalidRegexSurfacesAnErrorMessageInsteadOfCrashingOrSilentlyEmpty() {
        let options = FindSearchOptions(query: "(unclosed", useRegex: true)
        let outcome = FindSearchEngine.search(options: options, in: "text", anchorLocation: 0)
        XCTAssertNotNil(outcome.errorMessage)
        XCTAssertEqual(outcome.matchCount, 0)
    }

    func testFindNextAdvancesPastCurrentMatch() {
        let options = FindSearchOptions(query: "a")
        let next = FindSearchEngine.findNext(options: options, in: "a b a", after: 1)
        XCTAssertEqual(next, NSRange(location: 4, length: 1))
    }

    func testFindNextReturnsNilWhenNothingAfterLocation() {
        let options = FindSearchOptions(query: "a")
        XCTAssertNil(FindSearchEngine.findNext(options: options, in: "a b", after: 3))
    }

    func testFindPreviousReturnsLastMatchBeforeLocation() {
        let options = FindSearchOptions(query: "a")
        let previous = FindSearchEngine.findPrevious(options: options, in: "a b a b a", before: 8)
        XCTAssertEqual(previous, NSRange(location: 4, length: 1))
    }

    func testHighlightRangesAreWindowedAroundTheCurrentMatch() {
        let text = String(repeating: "a", count: 300)
        let options = FindSearchOptions(query: "a")
        let outcome = FindSearchEngine.search(options: options, in: text, anchorLocation: 150, maxHighlights: 10)
        XCTAssertEqual(outcome.matchCount, 300)
        XCTAssertEqual(outcome.highlightRanges.count, 10)
    }

    func testReplaceAllLiteral() throws {
        let result = try FindSearchEngine.replaceAll(options: FindSearchOptions(query: "foo"), in: "foo bar foo", replacement: "baz")
        XCTAssertEqual(result, "baz bar baz")
    }

    func testReplaceAllRegexSupportsCaptureGroupTemplates() throws {
        let options = FindSearchOptions(query: "(\\w+)@(\\w+)", useRegex: true)
        let result = try FindSearchEngine.replaceAll(options: options, in: "user@host", replacement: "$2:$1")
        XCTAssertEqual(result, "host:user")
    }

    func testReplaceAllThrowsOnInvalidRegex() {
        let options = FindSearchOptions(query: "(unclosed", useRegex: true)
        XCTAssertThrowsError(try FindSearchEngine.replaceAll(options: options, in: "text", replacement: "x"))
    }

    // MARK: - SearchQuery bridging

    func testFindSearchOptionsFromSearchQueryMapsFullWordAndRegularExpression() {
        let fullWord = SearchQuery(text: "foo", matchMethod: .fullWord, isCaseSensitive: true)
        let options = FindSearchOptions(fullWord)
        XCTAssertEqual(options.query, "foo")
        XCTAssertTrue(options.matchCase)
        XCTAssertTrue(options.wholeWord)
        XCTAssertFalse(options.useRegex)

        let regex = SearchQuery(text: "f.o", matchMethod: .regularExpression)
        XCTAssertTrue(FindSearchOptions(regex).useRegex)
    }

    func testFindSearchOptionsFromSearchQueryCollapsesStartsAndEndsWithToContains() {
        let startsWith = SearchQuery(text: "foo", matchMethod: .startsWith)
        let options = FindSearchOptions(startsWith)
        XCTAssertFalse(options.wholeWord)
        XCTAssertFalse(options.useRegex)
    }

    func testFindSearchOptionsToSearchQueryRoundTrips() {
        let options = FindSearchOptions(query: "foo", matchCase: true, wholeWord: true, useRegex: false)
        let query = options.searchQuery
        XCTAssertEqual(query.text, "foo")
        XCTAssertEqual(query.matchMethod, .fullWord)
        XCTAssertTrue(query.isCaseSensitive)
    }
}
