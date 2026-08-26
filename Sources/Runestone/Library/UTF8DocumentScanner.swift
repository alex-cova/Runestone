import Foundation

/// UTF-8 walkers that never allocate a `String` / UTF-16 buffer.
enum UTF8DocumentScanner {
    /// UTF-16 code units in `bytes`. Invalid / unexpected continuation bytes count as 1.
    static func utf16Length(ofUTF8 bytes: UnsafeRawBufferPointer) -> Int {
        var utf16 = 0
        var index = 0
        while index < bytes.count {
            let lead = bytes[index]
            if lead < 0x80 {
                utf16 += 1
                index += 1
            } else if lead < 0xC0 {
                utf16 += 1
                index += 1
            } else if lead < 0xE0 {
                utf16 += 1
                index += min(2, bytes.count - index)
            } else if lead < 0xF0 {
                utf16 += 1
                index += min(3, bytes.count - index)
            } else if lead < 0xF8 {
                utf16 += 2
                index += min(4, bytes.count - index)
            } else {
                utf16 += 1
                index += 1
            }
        }
        return utf16
    }

    /// Byte offset of the UTF-16 unit `utf16Offset` within `bytes`. `bytes.count` if past the end.
    static func utf8Offset(forUTF16Offset utf16Offset: Int, in bytes: UnsafeRawBufferPointer) -> Int {
        if utf16Offset <= 0 {
            return 0
        }
        var utf16 = 0
        var index = 0
        while index < bytes.count {
            if utf16 >= utf16Offset {
                return index
            }
            let lead = bytes[index]
            let units: Int
            let advance: Int
            if lead < 0x80 {
                units = 1
                advance = 1
            } else if lead < 0xC0 {
                units = 1
                advance = 1
            } else if lead < 0xE0 {
                units = 1
                advance = min(2, bytes.count - index)
            } else if lead < 0xF0 {
                units = 1
                advance = min(3, bytes.count - index)
            } else if lead < 0xF8 {
                units = 2
                advance = min(4, bytes.count - index)
            } else {
                units = 1
                advance = 1
            }
            if utf16 + units > utf16Offset {
                return index
            }
            utf16 += units
            index += advance
        }
        return bytes.count
    }

    static func stripBOM(from bytes: UnsafeRawBufferPointer) -> UnsafeRawBufferPointer {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return UnsafeRawBufferPointer(rebasing: bytes.dropFirst(3))
        }
        return bytes
    }

    /// `(utf8Offset, utf16Offset, lineCount)` triples on the original mapping, for O(log n)+64KB
    /// UTF-16→UTF-8 conversion and line-feed counts inside a large original piece.
    struct Checkpoint {
        var utf8Offset: Int
        var utf16Offset: Int
        /// Number of line delimiters fully ended before `utf8Offset`.
        var lineCount: Int
    }

    struct Scan {
        var lineMetrics: [LineMetric]
        var checkpoints: [Checkpoint]
        var utf16Length: Int
        var lineFeedCount: Int
        var longestLineUTF16: Int
        var longestLineIndex: Int
        var isValid: Bool
    }

    static let checkpointStride = 64 * 1024

    static func scan(_ bytes: UnsafeRawBufferPointer) -> Scan {
        var lines: [LineMetric] = []
        var scan = scan(bytes, onLine: { lines.append($0) }, onProgress: nil)
        scan.lineMetrics = lines
        return scan
    }

    /// Walk `bytes` once. `onLine` receives each completed line (including the trailing line with
    /// no delimiter). `onProgress` is called with the current byte index at checkpoint boundaries
    /// so a loader can remap already-scanned pages.
    static func scan(
        _ bytes: UnsafeRawBufferPointer,
        onLine: ((LineMetric) -> Void)?,
        onProgress: ((Int) -> Void)?
    ) -> Scan {
        var checkpoints: [Checkpoint] = [Checkpoint(utf8Offset: 0, utf16Offset: 0, lineCount: 0)]
        var currentUTF16 = 0
        var totalUTF16 = 0
        var lineFeedCount = 0
        var longestLineUTF16 = 0
        var longestLineIndex = 0
        var lineIndex = 0
        var index = 0
        var isValid = true
        let count = bytes.count
        func finishLine(_ metric: LineMetric) {
            if metric.totalLength > longestLineUTF16 {
                longestLineUTF16 = metric.totalLength
                longestLineIndex = lineIndex
            }
            onLine?(metric)
            lineIndex += 1
            if metric.delimiterLength > 0 {
                lineFeedCount += 1
            }
        }
        while index < count {
            if index - checkpoints[checkpoints.count - 1].utf8Offset >= checkpointStride {
                checkpoints.append(Checkpoint(
                    utf8Offset: index,
                    utf16Offset: totalUTF16 + currentUTF16,
                    lineCount: lineFeedCount
                ))
                onProgress?(index)
            }
            let byte = bytes[index]
            if byte == 0x0A {
                finishLine(LineMetric(totalLength: currentUTF16 + 1, delimiterLength: 1))
                totalUTF16 += currentUTF16 + 1
                currentUTF16 = 0
                index += 1
            } else if byte == 0x0D {
                if index + 1 < count && bytes[index + 1] == 0x0A {
                    finishLine(LineMetric(totalLength: currentUTF16 + 2, delimiterLength: 2))
                    totalUTF16 += currentUTF16 + 2
                    currentUTF16 = 0
                    index += 2
                } else {
                    finishLine(LineMetric(totalLength: currentUTF16 + 1, delimiterLength: 1))
                    totalUTF16 += currentUTF16 + 1
                    currentUTF16 = 0
                    index += 1
                }
            } else if byte == 0xC2, index + 1 < count, bytes[index + 1] == 0x85 {
                finishLine(LineMetric(totalLength: currentUTF16 + 1, delimiterLength: 1))
                totalUTF16 += currentUTF16 + 1
                currentUTF16 = 0
                index += 2
            } else if byte == 0xE2, index + 2 < count, bytes[index + 1] == 0x80,
                      bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 {
                finishLine(LineMetric(totalLength: currentUTF16 + 1, delimiterLength: 1))
                totalUTF16 += currentUTF16 + 1
                currentUTF16 = 0
                index += 3
            } else {
                let lead = byte
                let needed: Int
                let units: Int
                if lead < 0x80 {
                    needed = 0
                    units = 1
                } else if lead < 0xC0 {
                    isValid = false
                    needed = 0
                    units = 1
                } else if lead < 0xE0 {
                    needed = 1
                    units = 1
                } else if lead < 0xF0 {
                    needed = 2
                    units = 1
                } else if lead < 0xF8 {
                    needed = 3
                    units = 2
                } else {
                    isValid = false
                    needed = 0
                    units = 1
                }
                if needed > 0 {
                    if index + needed >= count {
                        isValid = false
                    } else {
                        for offset in 1...needed where bytes[index + offset] & 0xC0 != 0x80 {
                            isValid = false
                        }
                    }
                }
                currentUTF16 += units
                index += min(1 + needed, count - index)
            }
        }
        finishLine(LineMetric(totalLength: currentUTF16, delimiterLength: 0))
        totalUTF16 += currentUTF16
        onProgress?(count)
        return Scan(
            lineMetrics: [],
            checkpoints: checkpoints,
            utf16Length: totalUTF16,
            lineFeedCount: lineFeedCount,
            longestLineUTF16: longestLineUTF16,
            longestLineIndex: longestLineIndex,
            isValid: isValid
        )
    }

    /// Line metrics matching ``LineBreakAccumulator`` / `NSString.getLineStart` (LF, CR, CRLF, NEL, LS, PS).
    static func lineMetrics(in bytes: UnsafeRawBufferPointer) -> [LineMetric] {
        scan(bytes).lineMetrics
    }

    static func isValidUTF8(_ bytes: UnsafeRawBufferPointer) -> Bool {
        scan(bytes, onLine: nil, onProgress: nil).isValid
    }

    /// Number of line delimiters in `bytes` (CRLF counts as one).
    static func lineFeedCount(in bytes: UnsafeRawBufferPointer) -> Int {
        var count = 0
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x0A {
                count += 1
                index += 1
            } else if byte == 0x0D {
                if index + 1 < bytes.count && bytes[index + 1] == 0x0A {
                    index += 2
                } else {
                    index += 1
                }
                count += 1
            } else if byte == 0xC2, index + 1 < bytes.count, bytes[index + 1] == 0x85 {
                count += 1
                index += 2
            } else if byte == 0xE2, index + 2 < bytes.count, bytes[index + 1] == 0x80,
                      bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 {
                count += 1
                index += 3
            } else if byte < 0x80 {
                index += 1
            } else if byte < 0xC0 {
                index += 1
            } else if byte < 0xE0 {
                index += min(2, bytes.count - index)
            } else if byte < 0xF0 {
                index += min(3, bytes.count - index)
            } else if byte < 0xF8 {
                index += min(4, bytes.count - index)
            } else {
                index += 1
            }
        }
        return count
    }
}
