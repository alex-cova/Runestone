import CoreText
import Darwin
import Foundation

/// CPU bitmap produced by `GlyphRasterizer`. Pixel rows are top-down (Metal-ready).
struct GlyphBitmap: Sendable {
    var key: GlyphKey
    var width: Int
    var height: Int
    var bytesPerRow: Int
    var data: Data
    /// Pixel offset from the glyph origin to the left of the padded tile.
    var originX: Float
    /// Pixel offset from the glyph origin to the bottom of the padded tile (y-up).
    var originY: Float
    var isColor: Bool
}

enum GlyphRasterResult: Sendable {
    case bitmap(GlyphBitmap)
    case oversize
    case empty
    case failed
}

enum GlyphRasterizer {
    static let padPixels = 2
    static let maxGlyphExtentPixels = 256

    static func isColorFont(_ font: CTFont) -> Bool {
        // Core Text: kCTFontColorGlyphsAttribute == "NSCTFontColorGlyphsAttribute"
        if let flag = CTFontCopyAttribute(font, "NSCTFontColorGlyphsAttribute" as CFString) as? Bool, flag {
            return true
        }
        return CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs)
    }

    static func glyph(for string: String, font: CTFont) -> CGGlyph? {
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes) else {
            return nil
        }
        let line = CTLineCreateWithAttributedString(attributed)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], let run = runs.first else {
            return nil
        }
        guard CTRunGetGlyphCount(run) > 0 else {
            return nil
        }
        var glyph: CGGlyph = 0
        CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
        return glyph == 0 ? nil : glyph
    }

    static func rasterize(
        font: CTFont,
        glyph: CGGlyph,
        scale: CGFloat,
        runMatrix: CGAffineTransform = .identity,
        isColor: Bool,
        maxExtent: Int = maxGlyphExtentPixels
    ) -> GlyphRasterResult {
        let key = GlyphKey.make(font: font, glyph: glyph, scale: scale, runMatrix: runMatrix, isColor: isColor)
        var glyphRef = glyph
        var fontBounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphRef, &fontBounds, 1)
        let aabb = fontBounds.applying(runMatrix)
        let scale = max(scale, 0.001)
        let pixelMinX = floor(aabb.minX * scale)
        let pixelMinY = floor(aabb.minY * scale)
        let pixelMaxX = ceil(aabb.maxX * scale)
        let pixelMaxY = ceil(aabb.maxY * scale)
        let contentWidth = pixelMaxX - pixelMinX
        let contentHeight = pixelMaxY - pixelMinY
        if contentWidth <= 0 || contentHeight <= 0 {
            return .empty
        }
        let width = Int(contentWidth) + 2 * padPixels
        let height = Int(contentHeight) + 2 * padPixels
        if width > maxExtent || height > maxExtent {
            return .oversize
        }
        let bytesPerPixel = isColor ? 4 : 1
        let bytesPerRow = alignedBytesPerRow(width: width, bytesPerPixel: bytesPerPixel)
        var data = Data(count: bytesPerRow * height)
        let drawn = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else {
                return false
            }
            return drawGlyph(
                font: font,
                glyph: glyph,
                scale: scale,
                runMatrix: runMatrix,
                isColor: isColor,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow,
                pixels: base,
                pixelMinX: pixelMinX,
                pixelMinY: pixelMinY
            )
        }
        guard drawn else {
            return .failed
        }
        flipVertically(data: &data, height: height, bytesPerRow: bytesPerRow)
        return .bitmap(GlyphBitmap(
            key: key,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            data: data,
            originX: Float(pixelMinX - CGFloat(padPixels)),
            originY: Float(pixelMinY - CGFloat(padPixels)),
            isColor: isColor
        ))
    }

    static func prewarmBitmaps(
        font: CTFont,
        scale: CGFloat,
        runMatrix: CGAffineTransform = .identity,
        maxExtent: Int = maxGlyphExtentPixels
    ) -> [GlyphBitmap] {
        let isColor = isColorFont(font)
        var bitmaps: [GlyphBitmap] = []
        bitmaps.reserveCapacity(prewarmScalars.count)
        var seen = Set<CGGlyph>()
        for scalar in prewarmScalars {
            guard let glyph = glyph(for: String(scalar), font: font), seen.insert(glyph).inserted else {
                continue
            }
            if case .bitmap(let bitmap) = rasterize(
                font: font,
                glyph: glyph,
                scale: scale,
                runMatrix: runMatrix,
                isColor: isColor,
                maxExtent: maxExtent
            ) {
                bitmaps.append(bitmap)
            }
        }
        return bitmaps
    }
}

extension GlyphRasterizer {
    /// Printable Latin-1.
    static let prewarmScalars: [UnicodeScalar] = {
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(96 + 96)
        for value in 0x20...0x7E {
            if let scalar = UnicodeScalar(value) {
                scalars.append(scalar)
            }
        }
        for value in 0xA0...0xFF {
            if let scalar = UnicodeScalar(value) {
                scalars.append(scalar)
            }
        }
        return scalars
    }()
}

private func alignedBytesPerRow(width: Int, bytesPerPixel: Int) -> Int {
    let raw = max(width, 1) * bytesPerPixel
    return (raw + 15) & ~15
}

private func drawGlyph(
    font: CTFont,
    glyph: CGGlyph,
    scale: CGFloat,
    runMatrix: CGAffineTransform,
    isColor: Bool,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    pixels: UnsafeMutableRawPointer,
    pixelMinX: CGFloat,
    pixelMinY: CGFloat
) -> Bool {
    let context: CGContext?
    if isColor {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return false
        }
        // BGRA, premultiplied: little-endian + alpha in the high byte.
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        context = CGContext(
            data: pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    } else {
        // Swift's CGContext initializer requires a color space; DeviceGray 8-bit is R8 coverage.
        context = CGContext(
            data: pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    }
    guard let context else {
        return false
    }
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    if !isColor {
        context.setFillColor(gray: 1, alpha: 1)
    }
    // Positions are in scaled user space; the font matrix comes only from CTFontDrawGlyphs.
    context.scaleBy(x: scale, y: scale)
    context.concatenate(runMatrix)
    context.textMatrix = .identity
    let pad = CGFloat(GlyphRasterizer.padPixels)
    var glyphRef = glyph
    var position = CGPoint(
        x: (pad - pixelMinX) / scale,
        y: (pad - pixelMinY) / scale
    )
    CTFontDrawGlyphs(font, &glyphRef, &position, 1, context)
    return true
}

private func flipVertically(data: inout Data, height: Int, bytesPerRow: Int) {
    guard height > 1, bytesPerRow > 0 else {
        return
    }
    data.withUnsafeMutableBytes { raw in
        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
            return
        }
        var scratch = [UInt8](repeating: 0, count: bytesPerRow)
        for y in 0..<(height / 2) {
            let top = base + y * bytesPerRow
            let bottom = base + (height - 1 - y) * bytesPerRow
            scratch.withUnsafeMutableBytes { scratchRaw in
                guard let scratchBase = scratchRaw.baseAddress else {
                    return
                }
                memcpy(scratchBase, top, bytesPerRow)
                memcpy(top, bottom, bytesPerRow)
                memcpy(bottom, scratchBase, bytesPerRow)
            }
        }
    }
}
