import AppKit
import CoreText
import Metal
import XCTest
@testable import Runestone

@MainActor
final class GlyphRunExtractorTests: XCTestCase {
    func testASCIIGlyphCountAndPositionsMatchCTLineOffsets() throws {
        let atlas = try makeAtlas()
        let font = makeMenlo(pointSize: 16)
        let string = "Hello"
        let line = makeLine(string, font: font)
        let metrics = lineMetrics(line)
        let gutter: CGFloat = 24
        let frame = CGRect(x: gutter, y: 10, width: metrics.base.width, height: metrics.scaled.height)
        let result = extract(
            line: line,
            font: font,
            atlas: atlas,
            fragmentFrame: frame,
            metrics: metrics
        )
        XCTAssertEqual(result.glyphs.count, string.utf16.count)
        let firstIndex = try XCTUnwrap(result.glyphs.first?.stringIndex)
        let lastIndex = try XCTUnwrap(result.glyphs.last?.stringIndex)
        let firstOffset = CTLineGetOffsetForStringIndex(line, 0, nil)
        let lastOffset = CTLineGetOffsetForStringIndex(line, string.utf16.count - 1, nil)
        XCTAssertEqual(firstIndex, 0)
        XCTAssertEqual(lastIndex, string.utf16.count - 1)
        XCTAssertEqual(result.glyphs[0].contentOrigin.x, gutter + firstOffset, accuracy: 0.05)
        XCTAssertEqual(result.glyphs[result.glyphs.count - 1].contentOrigin.x, gutter + lastOffset, accuracy: 0.05)
    }

    func testBaselineYMatchesCaretVerticalCentering() throws {
        let atlas = try makeAtlas()
        let font = makeMenlo(pointSize: 16)
        let line = makeLine("Ag", font: font)
        var metrics = lineMetrics(line)
        metrics.scaled = CGSize(width: metrics.base.width, height: metrics.base.height * 1.5)
        let expected = (metrics.scaled.height + metrics.base.height) / 2 - metrics.descent
        let paddingTop = (metrics.scaled.height - metrics.base.height) / 2
        XCTAssertEqual(expected, paddingTop + metrics.base.height - metrics.descent, accuracy: 0.0001)
        let result = extract(line: line, font: font, atlas: atlas, metrics: metrics)
        XCTAssertEqual(result.baselineY, expected, accuracy: 0.0001)
        XCTAssertEqual(
            GlyphRunExtractor.baselineY(baseSize: metrics.base, scaledSize: metrics.scaled, descent: metrics.descent),
            paddingTop + metrics.base.height - metrics.descent,
            accuracy: 0.0001
        )
    }

    func testHoeflerLigatureCollapsesFi() throws {
        guard let nsFont = NSFont(name: "HoeflerText-Regular", size: 24) else {
            throw XCTSkip("Hoefler Text is not available")
        }
        let atlas = try makeAtlas()
        let font = nsFont as CTFont
        let ligatured = makeLine("fi", font: font, extra: [kCTLigatureAttributeName as NSAttributedString.Key: 2])
        let disabled = makeLine("fi", font: font, extra: [kCTLigatureAttributeName as NSAttributedString.Key: 0])
        let ligaturedResult = extract(line: ligatured, font: font, atlas: atlas, metrics: lineMetrics(ligatured))
        let disabledResult = extract(line: disabled, font: font, atlas: atlas, metrics: lineMetrics(disabled))
        XCTAssertEqual(ctGlyphCount(ligatured), 1)
        XCTAssertEqual(ligaturedResult.glyphs.count, 1)
        XCTAssertEqual(disabledResult.glyphs.count, 2)
    }

    func testCombiningMarkProducesMultipleGlyphs() throws {
        let atlas = try makeAtlas()
        let font = makeMenlo(pointSize: 16)
        let preferred = "e\u{0301}"
        let preferredLine = makeLine(preferred, font: font)
        let preferredResult = extract(
            line: preferredLine,
            font: font,
            atlas: atlas,
            metrics: lineMetrics(preferredLine)
        )
        XCTAssertEqual(preferredResult.glyphs.count, ctGlyphCount(preferredLine))
        if preferredResult.glyphs.count >= 2 {
            return
        }
        // Core Text composes U+0065 U+0301 for Menlo; stacked marks still produce multiple glyphs.
        let stacked = "e\u{0327}\u{0301}"
        let stackedLine = makeLine(stacked, font: font)
        guard ctGlyphCount(stackedLine) >= 2 else {
            throw XCTSkip("No combining-mark sequence produced multiple glyphs")
        }
        let stackedResult = extract(
            line: stackedLine,
            font: font,
            atlas: atlas,
            metrics: lineMetrics(stackedLine)
        )
        XCTAssertGreaterThanOrEqual(stackedResult.glyphs.count, 2)
    }

    func testEmojiZWJUsesAppleColorEmoji() throws {
        let font = try makeAppleColorEmojiFont(pointSize: 32)
        let atlas = try makeAtlas()
        let string = "👨‍👩‍👧‍👦"
        let line = makeLine(string, font: font)
        XCTAssertGreaterThan(ctGlyphCount(line), 0, "Apple Color Emoji must shape the ZWJ sequence")
        let result = extract(line: line, font: font, atlas: atlas, metrics: lineMetrics(line), scale: 1)
        XCTAssertFalse(result.glyphs.isEmpty)
        XCTAssertTrue(result.glyphs.allSatisfy(\.isColor))
        XCTAssertTrue(result.skips.isEmpty)
    }

    func testItalicSymbolicTraitsQuadWidthIsShearNotShearSquared() throws {
        let atlas = try makeAtlas()
        let regular = makeMenlo(pointSize: 16)
        let italicDescriptor = (regular as NSFont).fontDescriptor.withSymbolicTraits(.italic)
        let italicFont = NSFont(descriptor: italicDescriptor, size: 16) ?? (regular as NSFont)
        var shear = CGAffineTransform(a: 1, b: 0, c: 0.25, d: 1, tx: 0, ty: 0)
        let sheared = CTFontCreateCopyWithAttributes(regular, 0, &shear, nil)

        let regularLine = makeLine("A", font: regular)
        let italicLine = makeLine("A", font: italicFont)
        let shearedLine = makeLine("A", font: sheared)
        let regularResult = extract(line: regularLine, font: regular, atlas: atlas, metrics: lineMetrics(regularLine))
        let italicResult = extract(line: italicLine, font: italicFont, atlas: atlas, metrics: lineMetrics(italicLine))
        let shearedResult = extract(line: shearedLine, font: sheared, atlas: atlas, metrics: lineMetrics(shearedLine))

        let regularGlyph = try XCTUnwrap(regularResult.glyphs.first)
        let italicGlyph = try XCTUnwrap(italicResult.glyphs.first)
        let shearedGlyph = try XCTUnwrap(shearedResult.glyphs.first)
        XCTAssertNotEqual(regularGlyph.instance.size, .zero)
        XCTAssertNotEqual(italicGlyph.instance.size, .zero)

        let regularKey = GlyphKey.make(font: regular, glyph: regularGlyph.glyph, scale: 2, isColor: false)
        let italicKey = GlyphKey.make(font: italicFont, glyph: italicGlyph.glyph, scale: 2, isColor: false)
        let shearedKey = GlyphKey.make(font: sheared, glyph: shearedGlyph.glyph, scale: 2, isColor: false)
        XCTAssertNotEqual(regularKey, italicKey)
        XCTAssertNotEqual(regularKey.matrixHash, shearedKey.matrixHash)

        var glyph = shearedGlyph.glyph
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(sheared, .default, &glyph, &bounds, 1)
        let fontMatrix = CTFontGetMatrix(sheared)
        let doubleSheared = bounds.applying(fontMatrix)
        let scale: CGFloat = 2
        let pad = CGFloat(GlyphRasterizer.padPixels) / scale
        let singleWidth = bounds.width + 2 * pad
        let doubleWidth = doubleSheared.width + 2 * pad
        XCTAssertGreaterThan(doubleWidth - singleWidth, 1, "Shear² extra width must be distinguishable")
        XCTAssertEqual(CGFloat(shearedGlyph.instance.size.x), singleWidth, accuracy: 1.0)
        XCTAssertLessThan(
            abs(CGFloat(shearedGlyph.instance.size.x) - singleWidth),
            abs(CGFloat(shearedGlyph.instance.size.x) - doubleWidth)
        )
    }

    func testWrappingOffLongLineRebuildsInstancesWhenEmitRectMoves() throws {
        let atlas = try makeAtlas()
        let font = makeMenlo(pointSize: 16)
        let string = String(repeating: "A", count: 200)
        let line = makeLine(string, font: font)
        let metrics = lineMetrics(line)
        let frame = CGRect(x: 24, y: 0, width: metrics.base.width, height: metrics.scaled.height)
        let canvasA = CGRect(x: 0, y: 0, width: 180, height: 40)
        let canvasB = CGRect(x: 400, y: 0, width: 180, height: 40)
        let first = extract(
            line: line,
            font: font,
            atlas: atlas,
            fragmentFrame: frame,
            metrics: metrics,
            emitRect: MetalProjection.emitRect(canvasFrame: canvasA),
            atlasWarmRect: .null
        )
        let second = extract(
            line: line,
            font: font,
            atlas: atlas,
            fragmentFrame: frame,
            metrics: metrics,
            emitRect: MetalProjection.emitRect(canvasFrame: canvasB),
            atlasWarmRect: .null
        )
        XCTAssertFalse(first.glyphs.isEmpty)
        XCTAssertFalse(second.glyphs.isEmpty)
        let keyA = GlyphExtractCacheKey(line: line, emitRect: MetalProjection.emitRect(canvasFrame: canvasA))
        let keyB = GlyphExtractCacheKey(line: line, emitRect: MetalProjection.emitRect(canvasFrame: canvasB))
        XCTAssertEqual(keyA.ctLineID, keyB.ctLineID)
        XCTAssertNotEqual(keyA, keyB)
        XCTAssertTrue(GlyphExtractCacheKey.shouldRebuild(previous: keyA, line: line, emitRect: keyB.emitRect))
        let firstOrigins = first.instances.map(\.origin.x)
        let secondOrigins = second.instances.map(\.origin.x)
        XCTAssertNotEqual(firstOrigins, secondOrigins)
    }

    func testShadowRunIsSkipped() throws {
        let atlas = try makeAtlas()
        let font = makeMenlo(pointSize: 16)
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 2
        let line = makeLine("Hi", font: font, extra: [.shadow: shadow])
        let result = extract(line: line, font: font, atlas: atlas, metrics: lineMetrics(line))
        XCTAssertTrue(result.glyphs.isEmpty)
        XCTAssertEqual(result.skips.map(\.reason), [.shadow])
    }

    func testFocusAlphaDimsUnfocusedGlyphs() throws {
        let atlas = try makeAtlas()
        let font = makeMenlo(pointSize: 16)
        let line = makeLine("AB", font: font, extra: [.foregroundColor: NSColor.white])
        let metrics = lineMetrics(line)
        let result = extract(
            line: line,
            font: font,
            atlas: atlas,
            metrics: metrics,
            unfocusedAlpha: 0.5,
            focusedRanges: [NSRange(location: 0, length: 1)]
        )
        XCTAssertEqual(result.glyphs.count, 2)
        let focused = result.glyphs[0].instance.color
        let dimmed = result.glyphs[1].instance.color
        XCTAssertEqual(focused.w, 1, accuracy: 0.01)
        XCTAssertEqual(dimmed.w, 0.5, accuracy: 0.01)
        XCTAssertEqual(dimmed.x, focused.x * 0.5, accuracy: 0.01)
    }

    func testInstanceBufferGrowsByDoublingAndCompacts() throws {
        let (device, _) = try requireMetalDevice()
        let buffer = try XCTUnwrap(GlyphInstanceBuffer(device: device), "Shared instance buffer must allocate")
        XCTAssertEqual(buffer.capacity, GlyphInstanceBuffer.minimumCapacity)
        XCTAssertEqual(GlyphInstanceBuffer.minimumCapacity, 16_384)
        XCTAssertEqual(GlyphInstanceBuffer.maximumCapacity, 131_072)

        let dummy = GlyphInstance(
            origin: SIMD2(1, 2),
            size: SIMD2(3, 4),
            uvOrigin: .zero,
            uvSize: SIMD2(1, 1),
            color: SIMD4(1, 1, 1, 1),
            atlasPage: 1
        )
        buffer.write(Array(repeating: dummy, count: 20_000))
        XCTAssertEqual(buffer.capacity, 32_768)
        XCTAssertEqual(buffer.count, 20_000)
        XCTAssertEqual(buffer.instances.count, 20_000)

        buffer.write(Array(repeating: dummy, count: 40_000))
        XCTAssertEqual(buffer.capacity, 65_536)
        XCTAssertEqual(buffer.count, 40_000)

        buffer.write(Array(repeating: dummy, count: 70_000))
        XCTAssertEqual(buffer.capacity, 131_072)

        buffer.write(Array(repeating: dummy, count: GlyphInstanceBuffer.maximumCapacity + 1))
        XCTAssertEqual(buffer.capacity, GlyphInstanceBuffer.maximumCapacity)
        XCTAssertEqual(buffer.instances.count, GlyphInstanceBuffer.maximumCapacity + 1)

        buffer.compact()
        XCTAssertEqual(buffer.capacity, GlyphInstanceBuffer.minimumCapacity)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.instances.isEmpty)
    }
}

private extension GlyphRunExtractorTests {
    struct LineMetrics {
        var descent: CGFloat
        var base: CGSize
        var scaled: CGSize
    }

    func makeMenlo(pointSize: CGFloat) -> CTFont {
        CTFontCreateWithName("Menlo" as CFString, pointSize, nil)
    }

    func makeAppleColorEmojiFont(pointSize: CGFloat) throws -> CTFont {
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, pointSize, nil)
        let postScriptName = CTFontCopyPostScriptName(font) as String
        if postScriptName != "AppleColorEmoji" {
            XCTFail("Apple Color Emoji is missing (got \(postScriptName))")
            struct AppleColorEmojiMissing: Error {}
            throw AppleColorEmojiMissing()
        }
        return font
    }

    func requireMetalDevice() throws -> (MTLDevice, MTLCommandQueue) {
        guard MetalContext.isAvailable else {
            throw XCTSkip("Metal is not available")
        }
        guard let device = MetalContext.shared.device, let queue = MetalContext.shared.commandQueue else {
            XCTFail("MetalContext.isAvailable is true but device or command queue is nil")
            throw XCTSkip("Metal is not available")
        }
        return (device, queue)
    }

    func makeAtlas() throws -> GlyphAtlas {
        let (device, queue) = try requireMetalDevice()
        return GlyphAtlas(
            device: device,
            commandQueue: queue,
            hasUnifiedMemory: device.hasUnifiedMemory
        )
    }

    func makeLine(_ string: String, font: CTFont, extra: [NSAttributedString.Key: Any] = [:]) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        for (key, value) in extra {
            attributes[key] = value
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    func lineMetrics(_ line: CTLine, multiplier: CGFloat = 1) -> LineMetrics {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let height = ascent + descent + leading
        let base = CGSize(width: width, height: height)
        return LineMetrics(descent: descent, base: base, scaled: CGSize(width: width, height: height * multiplier))
    }

    func ctGlyphCount(_ line: CTLine) -> Int {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else {
            return 0
        }
        return runs.reduce(0) { $0 + CTRunGetGlyphCount($1) }
    }

    func extract(
        line: CTLine,
        font: CTFont,
        atlas: GlyphAtlas,
        fragmentFrame: CGRect? = nil,
        metrics: LineMetrics,
        scale: CGFloat = 2,
        emitRect: CGRect? = nil,
        atlasWarmRect: CGRect = .infinite,
        unfocusedAlpha: CGFloat = 1,
        focusedRanges: [NSRange] = []
    ) -> GlyphExtractResult {
        let frame = fragmentFrame ?? CGRect(origin: .zero, size: metrics.scaled)
        let request = GlyphExtractRequest(
            line: line,
            fragmentFrame: frame,
            descent: metrics.descent,
            baseSize: metrics.base,
            scaledSize: metrics.scaled,
            unfocusedAlpha: unfocusedAlpha,
            focusedRanges: focusedRanges,
            scale: scale,
            emitRect: emitRect ?? CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000),
            atlasWarmRect: atlasWarmRect,
            fallbackFont: font,
            fallbackColor: .white,
            appearance: nil
        )
        return GlyphRunExtractor.extract(request, atlas: atlas)
    }
}
