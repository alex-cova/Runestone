import Foundation
@preconcurrency import AppKit
import Metal
import QuartzCore

/// Transparent `CAMetalLayer` host. Glyphs still paint in `LineFragmentView`s above this canvas.
///
/// `draw(_:)` is the only place that calls `nextDrawable()`. Layout updates CPU state and
/// `setNeedsDisplay()` so a flick-scroll cannot present faster than vsync.
final class MetalTextCanvasView: UIView {
    var onRenderingFailure: (() -> Void)?

    private var isDisplayDirty = false

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
            return
        }
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
        encodeClearPass(on: metalLayer)
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

    func encodeClearPass(on metalLayer: CAMetalLayer) {
        let context = MetalContext.shared
        guard let commandQueue = context.commandQueue, let commandBuffer = commandQueue.makeCommandBuffer() else {
            context.markUnavailable(reason: "Failed to create Metal command buffer")
            onRenderingFailure?()
            return
        }
        guard let drawable = metalLayer.nextDrawable() else {
            isDisplayDirty = true
            return
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            context.markUnavailable(reason: "Failed to create Metal render command encoder")
            onRenderingFailure?()
            return
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
