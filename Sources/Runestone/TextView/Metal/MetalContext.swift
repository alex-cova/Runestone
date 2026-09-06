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

    private func handleMemoryPressure() {
        // Glyph-atlas eviction is wired in a later PR.
    }

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
    """#
}
