@preconcurrency import AppKit
import CoreText
import Foundation
import simd

struct GlyphExtractRequest {
    var line: CTLine
    var fragmentFrame: CGRect
    var descent: CGFloat
    var baseSize: CGSize
    var scaledSize: CGSize
    var unfocusedAlpha: CGFloat
    var focusedRanges: [NSRange]
    var scale: CGFloat
    var emitRect: CGRect
    var atlasWarmRect: CGRect
    var fallbackFont: CTFont
    var fallbackColor: NSColor
    var appearance: NSAppearance?
}

enum GlyphRunSkipReason: Equatable {
    case shadow
    case oversize
    case rasterCap
    case lookupFailed
}

struct GlyphRunSkip: Equatable {
    var runIndex: Int
    var reason: GlyphRunSkipReason
}

struct ExtractedGlyph {
    var instance: GlyphInstance
    /// Unpadded glyph origin in content space (layout X, baseline Y).
    var contentOrigin: CGPoint
    var stringIndex: Int
    var isColor: Bool
    var matrixHash: UInt64
    var glyph: CGGlyph
}

struct GlyphExtractResult {
    var glyphs: [ExtractedGlyph]
    var baselineY: CGFloat
    var emitRect: CGRect
    var skips: [GlyphRunSkip]
    var warmedGlyphCount: Int

    var instances: [GlyphInstance] {
        glyphs.map(\.instance)
    }
}

struct GlyphRasterBudget {
    static let perFrameLimit = 8

    var remaining: Int

    init(limit: Int = perFrameLimit) {
        remaining = limit
    }

    var hasRemaining: Bool {
        remaining > 0
    }

    mutating func consume() -> Bool {
        guard remaining > 0 else {
            return false
        }
        remaining -= 1
        return true
    }
}

/// Instance rebuild key. A pan that moves `canvas.frame` must re-extract even when `CTLine` is unchanged.
struct GlyphExtractCacheKey: Equatable {
    var ctLineID: ObjectIdentifier
    var emitRect: CGRect

    init(line: CTLine, emitRect: CGRect) {
        self.ctLineID = ObjectIdentifier(line)
        self.emitRect = emitRect
    }

    static func shouldRebuild(previous: GlyphExtractCacheKey?, line: CTLine, emitRect: CGRect) -> Bool {
        previous != GlyphExtractCacheKey(line: line, emitRect: emitRect)
    }
}

enum GlyphRunExtractor {
    static let padPixels = GlyphRasterizer.padPixels
    static let maxGlyphExtentPixels = GlyphRasterizer.maxGlyphExtentPixels
    static let verticalLayoutPadding: CGFloat = 350
    static let perFrameRasterLimit = GlyphRasterBudget.perFrameLimit

    /// Fragment-local baseline from the top, matching `LineController.caretRect` vertical centering.
    static func baselineY(baseSize: CGSize, scaledSize: CGSize, descent: CGFloat) -> CGFloat {
        (scaledSize.height + baseSize.height) / 2 - descent
    }

    @MainActor
    static func extract(_ request: GlyphExtractRequest, atlas: GlyphAtlas) -> GlyphExtractResult {
        var budget = GlyphRasterBudget()
        return extract(request, atlas: atlas, budget: &budget)
    }

    @MainActor
    static func extract(
        _ request: GlyphExtractRequest,
        atlas: GlyphAtlas,
        budget: inout GlyphRasterBudget
    ) -> GlyphExtractResult {
        let baselineY = baselineY(
            baseSize: request.baseSize,
            scaledSize: request.scaledSize,
            descent: request.descent
        )
        var result = GlyphExtractResult(
            glyphs: [],
            baselineY: baselineY,
            emitRect: request.emitRect,
            skips: [],
            warmedGlyphCount: 0
        )
        guard let runs = CTLineGetGlyphRuns(request.line) as? [CTRun] else {
            return result
        }
        var prepared: [PreparedRun] = []
        prepared.reserveCapacity(runs.count)
        for (runIndex, run) in runs.enumerated() {
            switch prepare(run, runIndex: runIndex, request: request, baselineY: baselineY) {
            case .skip(let skip):
                result.skips.append(skip)
            case .run(let preparedRun):
                prepared.append(preparedRun)
            }
        }
        for preparedRun in prepared {
            var stopRun = false
            for pending in preparedRun.glyphs where pending.band == .emit {
                switch resolve(pending, preparedRun: preparedRun, request: request, atlas: atlas, budget: &budget) {
                case .instance(let extracted):
                    result.glyphs.append(extracted)
                case .warmed, .skipped:
                    break
                case .needsRasterCap:
                    result.skips.append(GlyphRunSkip(runIndex: preparedRun.runIndex, reason: .rasterCap))
                    stopRun = true
                case .failed:
                    result.skips.append(GlyphRunSkip(runIndex: preparedRun.runIndex, reason: .lookupFailed))
                    stopRun = true
                }
                if stopRun {
                    break
                }
            }
        }
        let cappedRuns = Set(result.skips.compactMap { skip -> Int? in
            skip.reason == .rasterCap ? skip.runIndex : nil
        })
        for preparedRun in prepared where !cappedRuns.contains(preparedRun.runIndex) {
            for pending in preparedRun.glyphs where pending.band == .warm {
                if case .warmed = resolve(
                    pending,
                    preparedRun: preparedRun,
                    request: request,
                    atlas: atlas,
                    budget: &budget
                ) {
                    result.warmedGlyphCount += 1
                }
            }
        }
        return result
    }
}

private extension GlyphRunExtractor {
    enum Band {
        case emit
        case warm
        case none
    }

    struct PendingGlyph {
        var glyph: CGGlyph
        var position: CGPoint
        var stringIndex: Int
        var color: SIMD4<Float>
        var band: Band
    }

    struct PreparedRun {
        var runIndex: Int
        var font: CTFont
        var runMatrix: CGAffineTransform
        var isColor: Bool
        var matrixHash: UInt64
        var glyphs: [PendingGlyph]
    }

    enum PrepareResult {
        case skip(GlyphRunSkip)
        case run(PreparedRun)
    }

    enum ResolveResult {
        case instance(ExtractedGlyph)
        case warmed
        case skipped
        case needsRasterCap
        case failed
    }

    static func prepare(
        _ run: CTRun,
        runIndex: Int,
        request: GlyphExtractRequest,
        baselineY: CGFloat
    ) -> PrepareResult {
        let attributes = (CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]) ?? [:]
        if attributes[.shadow] != nil {
            return .skip(GlyphRunSkip(runIndex: runIndex, reason: .shadow))
        }
        let font = (attributes[.font] as? NSFont) ?? (request.fallbackFont as NSFont)
        let fontMatrix = CTFontGetMatrix(font)
        // Run text matrix copies CTFontGetMatrix for synthetic italic; extra is run * font⁻¹ so bounds are not sheared twice.
        let runMatrix = extraRunMatrix(CTRunGetTextMatrix(run), fontMatrix: fontMatrix)
        let applyRunMatrix = !runMatrix.isIdentity
        let isColor = GlyphRasterizer.isColorFont(font)
        let runColor = resolveColor(attributes: attributes, request: request)
        let glyphCount = CTRunGetGlyphCount(run)
        let matrixHash = GlyphKey.matrixHash(fontMatrix: fontMatrix, runMatrix: runMatrix)
        guard glyphCount > 0 else {
            return .run(PreparedRun(
                runIndex: runIndex,
                font: font,
                runMatrix: runMatrix,
                isColor: isColor,
                matrixHash: matrixHash,
                glyphs: []
            ))
        }
        var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
        var positions = [CGPoint](repeating: .zero, count: glyphCount)
        var stringIndices = [CFIndex](repeating: 0, count: glyphCount)
        let range = CFRange(location: 0, length: glyphCount)
        CTRunGetGlyphs(run, range, &glyphs)
        CTRunGetPositions(run, range, &positions)
        CTRunGetStringIndices(run, range, &stringIndices)
        var pending: [PendingGlyph] = []
        pending.reserveCapacity(glyphCount)
        let scale = max(request.scale, 0.001)
        for index in 0..<glyphCount {
            var position = positions[index]
            var glyph = glyphs[index]
            var bounds = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, &bounds, 1)
            if applyRunMatrix {
                position = position.applying(runMatrix)
                bounds = bounds.applying(runMatrix)
            }
            let pixelSize = paddedPixelSize(bounds: bounds, scale: scale)
            if pixelSize.width > maxGlyphExtentPixels || pixelSize.height > maxGlyphExtentPixels {
                return .skip(GlyphRunSkip(runIndex: runIndex, reason: .oversize))
            }
            if pixelSize.width == 0 || pixelSize.height == 0 {
                continue
            }
            let padPoints = CGFloat(padPixels) / scale
            let padded = bounds.insetBy(dx: -padPoints, dy: -padPoints)
            let quad = CGRect(
                x: request.fragmentFrame.minX + position.x + padded.origin.x,
                y: request.fragmentFrame.minY + baselineY - (padded.origin.y + padded.height),
                width: padded.width,
                height: padded.height
            )
            let band: Band
            if quad.intersects(request.emitRect) {
                band = .emit
            } else if quad.intersects(request.atlasWarmRect) {
                band = .warm
            } else {
                continue
            }
            var color = runColor
            let stringIndex = Int(stringIndices[index])
            if request.unfocusedAlpha < 1, !isFocused(stringIndex, ranges: request.focusedRanges) {
                color *= Float(request.unfocusedAlpha)
            }
            pending.append(PendingGlyph(
                glyph: glyph,
                position: position,
                stringIndex: stringIndex,
                color: color,
                band: band
            ))
        }
        return .run(PreparedRun(
            runIndex: runIndex,
            font: font,
            runMatrix: runMatrix,
            isColor: isColor,
            matrixHash: matrixHash,
            glyphs: pending
        ))
    }

    @MainActor
    static func resolve(
        _ pending: PendingGlyph,
        preparedRun: PreparedRun,
        request: GlyphExtractRequest,
        atlas: GlyphAtlas,
        budget: inout GlyphRasterBudget
    ) -> ResolveResult {
        let key = GlyphKey.make(
            font: preparedRun.font,
            glyph: pending.glyph,
            scale: request.scale,
            runMatrix: preparedRun.runMatrix,
            isColor: preparedRun.isColor
        )
        if !atlas.hasEntry(key) {
            guard budget.consume() else {
                return pending.band == .emit ? .needsRasterCap : .skipped
            }
        }
        let slot: GlyphAtlasSlot
        switch atlas.lookup(
            font: preparedRun.font,
            glyph: pending.glyph,
            scale: request.scale,
            runMatrix: preparedRun.runMatrix,
            isColor: preparedRun.isColor
        ) {
        case .hit(let lookedUp):
            slot = lookedUp
        case .oversize:
            return pending.band == .emit ? .failed : .skipped
        case .failed:
            return pending.band == .emit ? .failed : .skipped
        }
        if pending.band == .warm {
            return slot.isEmpty ? .skipped : .warmed
        }
        guard !slot.isEmpty else {
            return .skipped
        }
        return .instance(makeExtractedGlyph(
            pending: pending,
            preparedRun: preparedRun,
            request: request,
            slot: slot
        ))
    }

    static func makeExtractedGlyph(
        pending: PendingGlyph,
        preparedRun: PreparedRun,
        request: GlyphExtractRequest,
        slot: GlyphAtlasSlot
    ) -> ExtractedGlyph {
        let scale = max(request.scale, 0.001)
        let width = CGFloat(slot.width) / scale
        let height = CGFloat(slot.height) / scale
        let originX = request.fragmentFrame.minX + pending.position.x + CGFloat(slot.originX) / scale
        let originY = request.fragmentFrame.minY + requestBaselineY(request) - (CGFloat(slot.originY) / scale + height)
        var color = pending.color
        if preparedRun.isColor {
            let alpha = color.w
            color = SIMD4(alpha, alpha, alpha, alpha)
        }
        let uv = uvRect(for: slot)
        let instance = GlyphInstance(
            origin: SIMD2(Float(originX), Float(originY)),
            size: SIMD2(Float(width), Float(height)),
            uvOrigin: uv.origin,
            uvSize: uv.size,
            color: color,
            atlasPage: slot.pageID
        )
        return ExtractedGlyph(
            instance: instance,
            contentOrigin: CGPoint(
                x: request.fragmentFrame.minX + pending.position.x,
                y: request.fragmentFrame.minY + requestBaselineY(request)
            ),
            stringIndex: pending.stringIndex,
            isColor: preparedRun.isColor,
            matrixHash: preparedRun.matrixHash,
            glyph: pending.glyph
        )
    }

    static func requestBaselineY(_ request: GlyphExtractRequest) -> CGFloat {
        baselineY(baseSize: request.baseSize, scaledSize: request.scaledSize, descent: request.descent)
    }

    static func uvRect(for slot: GlyphAtlasSlot) -> (origin: SIMD2<Float>, size: SIMD2<Float>) {
        guard let texture = slot.texture, texture.width > 0, texture.height > 0 else {
            return (.zero, .zero)
        }
        let width = Float(texture.width)
        let height = Float(texture.height)
        return (
            SIMD2(Float(slot.x) / width, Float(slot.y) / height),
            SIMD2(Float(slot.width) / width, Float(slot.height) / height)
        )
    }

    static func extraRunMatrix(_ runMatrix: CGAffineTransform, fontMatrix: CGAffineTransform) -> CGAffineTransform {
        if runMatrix.isIdentity || affineComponentsEqual(runMatrix, fontMatrix) {
            return .identity
        }
        return runMatrix.concatenating(fontMatrix.inverted())
    }

    static func affineComponentsEqual(_ lhs: CGAffineTransform, _ rhs: CGAffineTransform) -> Bool {
        lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c && lhs.d == rhs.d && lhs.tx == rhs.tx && lhs.ty == rhs.ty
    }

    static func paddedPixelSize(bounds: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        let pixelMinX = floor(bounds.minX * scale)
        let pixelMinY = floor(bounds.minY * scale)
        let pixelMaxX = ceil(bounds.maxX * scale)
        let pixelMaxY = ceil(bounds.maxY * scale)
        let contentWidth = pixelMaxX - pixelMinX
        let contentHeight = pixelMaxY - pixelMinY
        if contentWidth <= 0 || contentHeight <= 0 {
            return (0, 0)
        }
        return (Int(contentWidth) + 2 * padPixels, Int(contentHeight) + 2 * padPixels)
    }

    static func isFocused(_ stringIndex: Int, ranges: [NSRange]) -> Bool {
        ranges.contains { NSLocationInRange(stringIndex, $0) }
    }

    static func resolveColor(attributes: [NSAttributedString.Key: Any], request: GlyphExtractRequest) -> SIMD4<Float> {
        let color: NSColor
        if let nsColor = attributes[.foregroundColor] as? NSColor {
            color = nsColor
        } else {
            color = request.fallbackColor
        }
        return premultipliedSRGB(color, appearance: request.appearance)
    }

    static func premultipliedSRGB(_ color: NSColor, appearance: NSAppearance?) -> SIMD4<Float> {
        func convert(_ color: NSColor) -> SIMD4<Float> {
            guard let rgb = color.usingColorSpace(.sRGB) else {
                return SIMD4(0, 0, 0, 1)
            }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return SIMD4(Float(red * alpha), Float(green * alpha), Float(blue * alpha), Float(alpha))
        }
        if let appearance {
            var result = SIMD4<Float>(0, 0, 0, 1)
            appearance.performAsCurrentDrawingAppearance {
                result = convert(color)
            }
            return result
        }
        return convert(color)
    }
}
