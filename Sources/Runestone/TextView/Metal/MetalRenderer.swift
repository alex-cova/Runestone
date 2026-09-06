@preconcurrency import AppKit
import CoreText
import Foundation
import Metal
import simd

/// `LinePaintBackend` that paints visible line fragments with a `CAMetalLayer` instead of one
/// layer-backed `LineFragmentView` per fragment.
///
/// `LayoutManager` drives it exactly like the CG backend: `upsertFragment` per visible fragment,
/// `removeFragments` for the ones that scrolled out, `setViewport` once per layout pass. Glyphs are
/// extracted with `GlyphRunExtractor` (skipped when neither the `CTLine` identity nor the cull rect
/// changed) into per-atlas-page instance buffers, then drawn in a single render pass from
/// `MetalTextCanvasView.draw(_:)`.
///
/// Decoration *drawing* (highlights, marked text, invisibles, fold chips) lands in PR 5; this
/// backend stores `LineFragmentDecorations` on each fragment but does not yet emit decoration
/// geometry. The feature flag stays default-off until then.
@MainActor
final class MetalRenderer: LinePaintBackend, MetalCanvasGlyphEncoding {
    private struct GPUFragment {
        var frame: CGRect
        var lineID: DocumentLineNodeID
        var cacheKey: GlyphExtractCacheKey?
        var glyphs: [GlyphInstance]
        var decorations: LineFragmentDecorations
    }

    private final class PageBucket {
        var buffers: [GlyphInstanceBuffer]
        var cursor = 0

        init(buffers: [GlyphInstanceBuffer]) {
            self.buffers = buffers
        }

        var current: GlyphInstanceBuffer {
            buffers[cursor]
        }

        func advance() {
            cursor = (cursor + 1) % buffers.count
        }
    }

    private weak var canvasView: MetalTextCanvasView?
    private let device: MTLDevice
    private let atlas: GlyphAtlas
    private let coveragePipeline: MTLRenderPipelineState
    private let colorPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private var fragments: [LineFragmentID: GPUFragment] = [:]
    private var pageBuckets: [UInt32: PageBucket] = [:]
    private var pageOrder: [UInt32] = []
    private var needsInstanceRebuild = false
    private var rasterBudget = GlyphRasterBudget()

    private var viewport: CGRect = .zero
    private var canvasFrame: CGRect = .zero
    private var scale: CGFloat = 2

    init?(canvasView: MetalTextCanvasView, context: MetalContext = .shared, atlas: GlyphAtlas? = nil) {
        guard context.isAvailable,
              let device = context.device,
              let library = context.library else {
            return nil
        }
        guard let providedAtlas = atlas ?? GlyphAtlas(context: context) else {
            return nil
        }
        guard let coverage = Self.makePipeline(
            device: device,
            library: library,
            fragmentFunction: "runestone_glyph_coverage_fragment"
        ), let color = Self.makePipeline(
            device: device,
            library: library,
            fragmentFunction: "runestone_glyph_color_fragment"
        ) else {
            return nil
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return nil
        }
        self.canvasView = canvasView
        self.device = device
        self.atlas = providedAtlas
        self.coveragePipeline = coverage
        self.colorPipeline = color
        self.sampler = sampler
        canvasView.glyphEncoder = self
    }

    // MARK: - LinePaintBackend

    var trackedFragmentIDs: Set<LineFragmentID> {
        Set(fragments.keys)
    }

    func upsertFragment(_ spec: LineFragmentPaintSpec) {
        let emitRect = MetalProjection.emitRect(canvasFrame: canvasFrame)
        var fragment = fragments[spec.id] ?? GPUFragment(
            frame: spec.frame,
            lineID: spec.lineID,
            cacheKey: nil,
            glyphs: [],
            decorations: spec.decorations
        )
        fragment.frame = spec.frame
        fragment.lineID = spec.lineID
        // Decorations always refresh (PR 5 renders them); glyphs only when the CTLine or cull moved.
        fragment.decorations = spec.decorations
        if GlyphExtractCacheKey.shouldRebuild(previous: fragment.cacheKey, line: spec.line, emitRect: emitRect) {
            let request = GlyphExtractRequest(
                line: spec.line,
                fragmentFrame: spec.frame,
                descent: spec.descent,
                baseSize: spec.baseSize,
                scaledSize: spec.scaledSize,
                unfocusedAlpha: spec.decorations.unfocusedAlpha,
                focusedRanges: spec.decorations.focusedRanges,
                scale: scale,
                emitRect: emitRect,
                atlasWarmRect: MetalProjection.atlasWarmRect(canvasFrame: canvasFrame),
                fallbackFont: spec.fallbackFont,
                fallbackColor: spec.fallbackColor,
                appearance: spec.appearance
            )
            let result = GlyphRunExtractor.extract(request, atlas: atlas, budget: &rasterBudget)
            fragment.glyphs = result.instances
            fragment.cacheKey = GlyphExtractCacheKey(line: spec.line, emitRect: emitRect)
        }
        fragments[spec.id] = fragment
        needsInstanceRebuild = true
        canvasView?.setNeedsDisplay()
    }

    func removeFragments(ids: Set<LineFragmentID>) {
        guard !ids.isEmpty else {
            return
        }
        for id in ids {
            fragments.removeValue(forKey: id)
        }
        needsInstanceRebuild = true
        canvasView?.setNeedsDisplay()
    }

    func invalidateGlyphs(forLineIDs ids: Set<DocumentLineNodeID>) {
        guard !ids.isEmpty else {
            return
        }
        for (fragmentID, fragment) in fragments where ids.contains(fragment.lineID) {
            fragments[fragmentID]?.cacheKey = nil
        }
        needsInstanceRebuild = true
        canvasView?.setNeedsDisplay()
    }

    func setViewport(_ viewport: CGRect, canvasFrame: CGRect, scale: CGFloat) {
        let scaleChanged = abs(scale - self.scale) > 0.001
        self.viewport = viewport
        self.canvasFrame = canvasFrame
        self.scale = max(scale, 0.001)
        if scaleChanged {
            // Glyph keys embed the backing scale — drop the atlas and force a re-extract.
            atlas.removeAll()
            for id in fragments.keys {
                fragments[id]?.cacheKey = nil
            }
            needsInstanceRebuild = true
        }
        canvasView?.setNeedsDisplay()
    }

    func setNeedsDisplay() {
        canvasView?.setNeedsDisplay()
    }

    func compactInstanceBuffers() {
        for bucket in pageBuckets.values {
            for buffer in bucket.buffers {
                buffer.compact()
            }
        }
    }

    // MARK: - MetalCanvasGlyphEncoding

    func encode(into encoder: MTLRenderCommandEncoder, drawableSize: CGSize) {
        RunestoneSignposts.interval("MetalRenderer.draw") {
            if needsInstanceRebuild {
                rebuildInstanceBuffers()
            }
            guard !pageOrder.isEmpty, canvasFrame.width > 0, canvasFrame.height > 0 else {
                return
            }
            var uniforms = MetalProjection.uniforms(canvasFrame: canvasFrame, scale: scale)
            let stride = MemoryLayout<GlyphInstance>.stride
            for pageID in pageOrder {
                guard let bucket = pageBuckets[pageID],
                      let texture = atlas.pageTexture(id: pageID) else {
                    continue
                }
                let buffer = bucket.current
                guard buffer.primaryCount > 0 || !buffer.overflowBuffers.isEmpty else {
                    continue
                }
                let pipeline = atlas.isColorPage(id: pageID) ? colorPipeline : coveragePipeline
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalProjectionUniforms>.stride, index: 1)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(sampler, index: 0)
                if buffer.primaryCount > 0 {
                    encoder.setVertexBuffer(buffer.metalBuffer, offset: 0, index: 0)
                    encoder.drawPrimitives(
                        type: .triangleStrip,
                        vertexStart: 0,
                        vertexCount: 4,
                        instanceCount: buffer.primaryCount
                    )
                }
                for overflow in buffer.overflowBuffers {
                    let overflowCount = overflow.length / stride
                    guard overflowCount > 0 else {
                        continue
                    }
                    encoder.setVertexBuffer(overflow, offset: 0, index: 0)
                    encoder.drawPrimitives(
                        type: .triangleStrip,
                        vertexStart: 0,
                        vertexCount: 4,
                        instanceCount: overflowCount
                    )
                }
            }
        }
        needsInstanceRebuild = false
        rasterBudget = GlyphRasterBudget()
    }
}

private extension MetalRenderer {
    static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        fragmentFunction: String
    ) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "runestone_glyph_vertex"),
              let fragment = library.makeFunction(name: fragmentFunction) else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = .bgra8Unorm
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        // Premultiplied source-over.
        attachment?.sourceRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func rebuildInstanceBuffers() {
        var instancesByPage: [UInt32: [GlyphInstance]] = [:]
        for fragment in fragments.values {
            for instance in fragment.glyphs where instance.atlasPage != 0 {
                instancesByPage[instance.atlasPage, default: []].append(instance)
            }
        }
        // Drop buckets for atlas pages that were evicted (their `pageID` never comes back — the
        // atlas hands out monotonic ids), and flush the rest that have no instances this frame.
        for pageID in Array(pageBuckets.keys) {
            guard let bucket = pageBuckets[pageID] else {
                continue
            }
            if atlas.pageTexture(id: pageID) == nil {
                pageBuckets.removeValue(forKey: pageID)
            } else if instancesByPage[pageID] == nil {
                bucket.advance()
                bucket.current.write([])
            }
        }
        pageOrder = []
        for (pageID, instances) in instancesByPage {
            let bucket: PageBucket
            if let existing = pageBuckets[pageID] {
                bucket = existing
            } else if let created = makeBucket() {
                pageBuckets[pageID] = created
                bucket = created
            } else {
                continue
            }
            bucket.advance()
            bucket.current.write(instances)
            pageOrder.append(pageID)
        }
    }

    private func makeBucket() -> PageBucket? {
        var buffers: [GlyphInstanceBuffer] = []
        buffers.reserveCapacity(3)
        for _ in 0..<3 {
            guard let buffer = GlyphInstanceBuffer(device: device) else {
                return nil
            }
            buffers.append(buffer)
        }
        return PageBucket(buffers: buffers)
    }
}
