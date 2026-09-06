import CoreGraphics
import Foundation
import simd

/// Vertex uniforms for content-space → NDC. The shader subtracts only `canvas.frame.origin`.
struct MetalProjectionUniforms {
    var canvasOrigin: SIMD2<Float>
    var canvasSize: SIMD2<Float>
    var scale: Float
}

enum MetalProjection {
    static func uniforms(canvasFrame: CGRect, scale: CGFloat) -> MetalProjectionUniforms {
        MetalProjectionUniforms(
            canvasOrigin: SIMD2(Float(canvasFrame.minX), Float(canvasFrame.minY)),
            canvasSize: SIMD2(Float(max(canvasFrame.width, .leastNormalMagnitude)),
                              Float(max(canvasFrame.height, .leastNormalMagnitude))),
            scale: Float(scale)
        )
    }

    /// Content-space point to Metal NDC. Y is flipped (`UIView.isFlipped` vs Metal Y-up).
    /// `scale` is a drawable uniform and does not change NDC.
    static func project(_ point: SIMD2<Float>, uniforms: MetalProjectionUniforms) -> SIMD2<Float> {
        let x = (point.x - uniforms.canvasOrigin.x) / uniforms.canvasSize.x * 2 - 1
        let y = 1 - (point.y - uniforms.canvasOrigin.y) / uniforms.canvasSize.y * 2
        return SIMD2(x, y)
    }

    static func project(_ point: CGPoint, canvasFrame: CGRect, scale: CGFloat = 1) -> SIMD2<Float> {
        project(
            SIMD2(Float(point.x), Float(point.y)),
            uniforms: uniforms(canvasFrame: canvasFrame, scale: scale)
        )
    }

    /// Visible instance cull rect: `canvas.frame` expanded by 2 pt for AA.
    static func emitRect(canvasFrame: CGRect) -> CGRect {
        canvasFrame.insetBy(dx: -2, dy: -2)
    }

    /// Atlas pre-warm rect: same visible X as the canvas, Y expanded by the layout pad.
    static func atlasWarmRect(
        canvasFrame: CGRect,
        verticalLayoutPadding: CGFloat = GlyphRunExtractor.verticalLayoutPadding
    ) -> CGRect {
        canvasFrame.insetBy(dx: 0, dy: -verticalLayoutPadding)
    }
}
