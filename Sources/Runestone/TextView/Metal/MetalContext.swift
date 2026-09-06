import Foundation
import Metal

/// Process-wide Metal device, queue, and shader library.
///
/// Shader compilation is deferred until the first `isAvailable` check that needs the library
/// so XCTest / default-off editors do not pay `makeLibrary` on every `TextView` init.
@MainActor
final class MetalContext {
    static let shared = MetalContext()

    static var isAvailable: Bool {
        shared.isAvailable
    }

    private(set) var device: MTLDevice?
    private(set) var commandQueue: MTLCommandQueue?
    private(set) var library: MTLLibrary?
    private var didFailPermanently = false
    private var didLogFailure = false
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    var isAvailable: Bool {
        guard !didFailPermanently, device != nil, commandQueue != nil else {
            return false
        }
        ensureLibrary()
        return !didFailPermanently && library != nil
    }

    private init() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        if device == nil || commandQueue == nil {
            markUnavailable(reason: "No Metal device or command queue")
        }
        installMemoryPressureSource()
    }

    func markUnavailable(reason: String = "Metal device lost") {
        guard !didFailPermanently else {
            return
        }
        didFailPermanently = true
        library = nil
        logFailureOnce(reason)
    }

    private func ensureLibrary() {
        guard library == nil, !didFailPermanently, let device else {
            return
        }
        let source = "\(Self.shaderSource)"
        do {
            library = try RunestoneSignposts.interval("MetalContext.makeLibrary") {
                try device.makeLibrary(source: source, options: nil)
            }
        } catch {
            markUnavailable(reason: "Failed to compile Metal library: \(error.localizedDescription)")
        }
    }

    private func installMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            self?.handleMemoryPressure()
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressure() {}

    private func logFailureOnce(_ message: String) {
        guard !didLogFailure else {
            return
        }
        didLogFailure = true
        NSLog("Runestone Metal: %@", message)
    }
}

private extension MetalContext {
    static let shaderSource: StaticString = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct ClearVertexOut {
        float4 position [[position]];
    };

    vertex ClearVertexOut runestone_clear_vertex(uint vid [[vertex_id]]) {
        ClearVertexOut out;
        float2 pos;
        if (vid == 0) {
            pos = float2(-1.0, -1.0);
        } else if (vid == 1) {
            pos = float2(3.0, -1.0);
        } else {
            pos = float2(-1.0, 3.0);
        }
        out.position = float4(pos, 0.0, 1.0);
        return out;
    }

    fragment float4 runestone_clear_fragment() {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    // Must match `GlyphInstance` (Swift) field-for-field.
    struct GlyphInstanceData {
        float2 origin;
        float2 size;
        float2 uvOrigin;
        float2 uvSize;
        float4 color;
        uint atlasPage;
    };

    // Must match `MetalProjectionUniforms` (Swift).
    struct GlyphUniforms {
        float2 canvasOrigin;
        float2 canvasSize;
        float scale;
    };

    struct GlyphVertexOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
    };

    vertex GlyphVertexOut runestone_glyph_vertex(uint vid [[vertex_id]],
                                                 uint iid [[instance_id]],
                                                 const device GlyphInstanceData *instances [[buffer(0)]],
                                                 constant GlyphUniforms &u [[buffer(1)]]) {
        // Triangle-strip corners: (0,0) (1,0) (0,1) (1,1).
        float2 corner = float2(float(vid & 1), float(vid >> 1));
        GlyphInstanceData inst = instances[iid];
        float2 contentPos = inst.origin + corner * inst.size;
        // Content space -> NDC. Subtract only the canvas origin; Y is flipped (the view is flipped).
        float2 ndc;
        ndc.x = (contentPos.x - u.canvasOrigin.x) / u.canvasSize.x * 2.0 - 1.0;
        ndc.y = 1.0 - (contentPos.y - u.canvasOrigin.y) / u.canvasSize.y * 2.0;
        GlyphVertexOut out;
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = inst.uvOrigin + corner * inst.uvSize;
        out.color = inst.color;
        return out;
    }

    fragment float4 runestone_glyph_coverage_fragment(GlyphVertexOut in [[stage_in]],
                                                      texture2d<float> atlas [[texture(0)]],
                                                      sampler s [[sampler(0)]]) {
        float coverage = atlas.sample(s, in.uv).r;
        // `in.color` is premultiplied sRGB (focus alpha already folded in).
        return in.color * coverage;
    }

    fragment float4 runestone_glyph_color_fragment(GlyphVertexOut in [[stage_in]],
                                                   texture2d<float> atlas [[texture(0)]],
                                                   sampler s [[sampler(0)]]) {
        // Color atlas texels are already premultiplied; instance alpha carries focus dimming.
        float4 texel = atlas.sample(s, in.uv);
        return texel * in.color.a;
    }
    """#
}
