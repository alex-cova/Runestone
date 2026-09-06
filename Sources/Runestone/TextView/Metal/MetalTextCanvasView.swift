import Foundation
@preconcurrency import AppKit
import Metal
import QuartzCore

/// Encodes glyph/decoration draws into the canvas's render pass. Implemented by `MetalRenderer`.
@MainActor
protocol MetalCanvasGlyphEncoding: AnyObject {
    /// Called inside `MetalTextCanvasView.draw(_:)` with a live encoder whose color attachment is
    /// already cleared to transparent. Must not call `endEncoding` / `present` / `commit`.
    func encode(into encoder: MTLRenderCommandEncoder, drawableSize: CGSize)
    /// The canvas left its window (cached / hidden host): release grown instance buffers.
    func hostDidLeaveWindow()
}

/// Transparent `CAMetalLayer` host. When Metal is active `MetalRenderer` paints glyphs here and the
/// `LineFragmentView`s are gone; when it is inactive the canvas is hidden and only clears.
///
/// `draw(_:)` is the only place that calls `nextDrawable()`. Layout updates CPU state and
/// `setNeedsDisplay()` so a flick-scroll cannot present faster than vsync.
final class MetalTextCanvasView: UIView {
    var onRenderingFailure: (() -> Void)?
    /// Set by `MetalRenderer` when it becomes the active paint backend; cleared when it steps down.
    weak var glyphEncoder: MetalCanvasGlyphEncoding?

    private var isDisplayDirty = false
    private var drawableRetryCount = 0
    private static let maxDrawableRetries = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isUserInteractionEnabled = false
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        wantsLayer = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.device = MetalContext.shared.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = false
        metalLayer.presentsWithTransaction = true
        return metalLayer
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func setNeedsDisplay() {
        isDisplayDirty = true
        super.setNeedsDisplay()
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        isDisplayDirty = true
        super.setNeedsDisplay(invalidRect)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMetalLayerGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            // Off-screen (workbench tab switch, EditorHostCache): stop presenting and shrink the
            // grown instance buffers back to their start size.
            glyphEncoder?.hostDidLeaveWindow()
            return
        }
        updateMetalLayerGeometry()
        if !isHidden {
            setNeedsDisplay()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateMetalLayerGeometry()
        if !isHidden {
            setNeedsDisplay()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard window != nil, !isHidden, isDisplayDirty else {
            return
        }
        guard let metalLayer = layer as? CAMetalLayer else {
            return
        }
        updateMetalLayerGeometry()
        guard metalLayer.drawableSize.width > 0, metalLayer.drawableSize.height > 0 else {
            return
        }
        guard MetalContext.shared.isAvailable else {
            onRenderingFailure?()
            return
        }
        isDisplayDirty = false
        encodePass(on: metalLayer)
    }
}

private extension MetalTextCanvasView {
    func updateMetalLayerGeometry() {
        guard let metalLayer = layer as? CAMetalLayer else {
            return
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    func encodePass(on metalLayer: CAMetalLayer) {
        let context = MetalContext.shared
        guard let commandQueue = context.commandQueue, let commandBuffer = commandQueue.makeCommandBuffer() else {
            context.markUnavailable(reason: "Failed to create Metal command buffer")
            onRenderingFailure?()
            return
        }
        guard let drawable = metalLayer.nextDrawable() else {
            if drawableRetryCount < Self.maxDrawableRetries {
                drawableRetryCount += 1
                setNeedsDisplay()
            }
            return
        }
        drawableRetryCount = 0
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            glyphEncoder?.encode(into: encoder, drawableSize: metalLayer.drawableSize)
            encoder.endEncoding()
        } else {
            // Still present so CAMetalLayer's drawable pool is released, then fall back.
            context.markUnavailable(reason: "Failed to create Metal render command encoder")
            commandBuffer.present(drawable)
            commandBuffer.commit()
            commandBuffer.waitUntilScheduled()
            onRenderingFailure?()
            return
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        // presentsWithTransaction presents at CA commit; the GPU must have the buffer first.
        commandBuffer.waitUntilScheduled()
    }
}
