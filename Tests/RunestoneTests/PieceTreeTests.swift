import XCTest
@testable import Runestone

final class PieceTreeTests: XCTestCase {
    func testContiguousAndPieceTreeAgreeOnEdits() throws {
        let samples = ["hello", "a\nb\nc", "café😀", "ab\r\ncd", ""]
        for original in samples {
            let url = try writeTemp(original)
            let loaded = try awaitLoad(url)
            let contiguous = StringView(string: original)
            XCTAssertEqual(loaded.string as String, original)
            let edits: [(NSRange, String)] = [
                (NSRange(location: 0, length: 0), "X"),
                (NSRange(location: 1, length: 1), ""),
                (NSRange(location: min(1, loaded.length), length: 0), "yz")
            ]
            for (range, text) in edits {
                let capped = NSRange(
                    location: min(range.location, loaded.length),
                    length: min(range.length, max(0, loaded.length - min(range.location, loaded.length)))
                )
                loaded.replaceText(in: capped, with: text)
                contiguous.replaceText(in: capped, with: text)
                XCTAssertEqual(loaded.string as String, contiguous.string as String, "after \(text) in \(original)")
            }
        }
    }

    func testMiddleInsertDoesNotRequireFullMaterializeForSubstring() throws {
        let url = try writeTemp("abcdefghij")
        let view = try awaitLoad(url)
        XCTAssertTrue(view.isFileBacked)
        view.replaceText(in: NSRange(location: 5, length: 0), with: "XYZ")
        XCTAssertEqual(view.substring(in: NSRange(location: 3, length: 7)), "deXYZfg")
        XCTAssertEqual(view.length, 13)
    }

    func testSequentialTypingExtendsAddBuffer() throws {
        let url = try writeTemp("hello world")
        let view = try awaitLoad(url)
        view.replaceText(in: NSRange(location: 5, length: 0), with: "!")
        view.replaceText(in: NSRange(location: 6, length: 0), with: "!")
        view.replaceText(in: NSRange(location: 7, length: 0), with: "!")
        XCTAssertEqual(view.string as String, "hello!!! world")
        XCTAssertLessThanOrEqual(view.pieceCount, 3)
    }

    func testCRLFSplitAcrossPiecesStillOneDelimiter() throws {
        let url = try writeTemp("ab\r\ncd")
        let view = try awaitLoad(url)
        view.replaceText(in: NSRange(location: 3, length: 0), with: "X")
        view.replaceText(in: NSRange(location: 3, length: 1), with: "")
        XCTAssertEqual(view.string as String, "ab\r\ncd")
        XCTAssertGreaterThanOrEqual(view.pieceCount, 2)
        XCTAssertEqual(view.rangeOfNextNewLine(startingAt: 0), NSRange(location: 2, length: 2))
        let lineManager = LineManager(stringView: view)
        lineManager.rebuild()
        XCTAssertEqual(lineManager.firstLine.data.delimiterLength, 2)
        XCTAssertEqual(lineManager.lineCount, 2)
    }

    func testUTF8ScalarSplitAcrossPieces() throws {
        let original = "café😀xyz"
        let url = try writeTemp(original)
        let view = try awaitLoad(url)
        let contiguous = StringView(string: original)
        view.replaceText(in: NSRange(location: 3, length: 0), with: "|")
        contiguous.replaceText(in: NSRange(location: 3, length: 0), with: "|")
        view.replaceText(in: NSRange(location: 5, length: 0), with: "|")
        contiguous.replaceText(in: NSRange(location: 5, length: 0), with: "|")
        view.replaceText(in: NSRange(location: 8, length: 0), with: "|")
        contiguous.replaceText(in: NSRange(location: 8, length: 0), with: "|")
        XCTAssertEqual(view.string as String, contiguous.string as String)
        XCTAssertEqual(view.substring(in: NSRange(location: 0, length: view.length)), contiguous.string as String)
    }

    func testPropertyStyleRandomEditsMatchContiguous() throws {
        var rng = SplitMix64(seed: 0xC0FFEE)
        let alphabet = Array("abcé\r\n\t ")
        for round in 0..<8 {
            var text = randomString(length: 24 + round, alphabet: alphabet, rng: &rng)
            let url = try writeTemp(text)
            let view = try awaitLoad(url)
            let contiguous = StringView(string: text)
            for _ in 0..<100 {
                let location = rng.next(upperBound: UInt64(max(view.length, 1)))
                let maxLen = max(0, view.length - Int(location))
                let length = maxLen == 0 ? 0 : Int(rng.next(upperBound: UInt64(min(maxLen, 4) + 1)))
                let insertion = randomString(length: Int(rng.next(upperBound: 4)), alphabet: alphabet, rng: &rng)
                let range = NSRange(location: Int(location), length: length)
                view.replaceText(in: range, with: insertion)
                contiguous.replaceText(in: range, with: insertion)
                XCTAssertEqual(view.length, contiguous.length)
                if view.length <= 80 {
                    XCTAssertEqual(view.string as String, contiguous.string as String)
                } else {
                    let sampleLoc = Int(rng.next(upperBound: UInt64(max(view.length, 1))))
                    let sampleLen = min(16, view.length - sampleLoc)
                    let sample = NSRange(location: sampleLoc, length: sampleLen)
                    XCTAssertEqual(view.substring(in: sample), contiguous.substring(in: sample))
                }
            }
            XCTAssertEqual(view.string as String, contiguous.string as String)
        }
    }

    func testPrefetchDoesNotWillNeedWholeOriginalPiece() throws {
        let text = String(repeating: "abcdefghij\n", count: 40_000)
        let url = try writeTemp(text)
        let view = try awaitLoad(url)
        XCTAssertGreaterThan(view.length, PieceTree.prefetchByteCap)
        view.prefetch(utf16Range: NSRange(location: 0, length: view.length))
        XCTAssertGreaterThan(view.lastPrefetchByteCount, 0)
        XCTAssertLessThanOrEqual(view.lastPrefetchByteCount, PieceTree.prefetchByteCap)
    }

    func testScatteredInsertsStayEquivalent() throws {
        let url = try writeTemp(String(repeating: "0123456789", count: 20))
        let view = try awaitLoad(url)
        let contiguous = StringView(string: view.string as String)
        for offset in stride(from: 0, to: 200, by: 10).reversed() {
            view.replaceText(in: NSRange(location: offset, length: 0), with: "X")
            contiguous.replaceText(in: NSRange(location: offset, length: 0), with: "X")
        }
        XCTAssertGreaterThan(view.pieceCount, 3)
        XCTAssertEqual(view.string as String, contiguous.string as String)
    }

    private func writeTemp(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try text.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func awaitLoad(_ url: URL) throws -> StringView {
        let box = BlockingBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let state = try await TextViewState.load(contentsOf: url)
                box.view = state.stringView
            } catch {
                box.error = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = box.error {
            throw error
        }
        return box.view!
    }
}

private func randomString(length: Int, alphabet: [Character], rng: inout SplitMix64) -> String {
    guard length > 0, !alphabet.isEmpty else {
        return ""
    }
    var result = ""
    result.reserveCapacity(length)
    for _ in 0..<length {
        let index = Int(rng.next(upperBound: UInt64(alphabet.count)))
        result.append(alphabet[index])
    }
    return result
}

private struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        guard upperBound > 0 else {
            return 0
        }
        return next() % upperBound
    }
}

private final class BlockingBox: @unchecked Sendable {
    var view: StringView?
    var error: Error?
}
