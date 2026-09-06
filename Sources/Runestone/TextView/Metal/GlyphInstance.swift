import Foundation
import Metal
import simd

/// One coverage or color glyph quad in content coordinates.
struct GlyphInstance {
    /// Content-space top-left of the padded quad, in points.
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var uvOrigin: SIMD2<Float>
    var uvSize: SIMD2<Float>
    /// Premultiplied sRGB. Alpha includes focus dimming.
    var color: SIMD4<Float>
    var atlasPage: UInt32
}

extension GlyphInstance: Equatable, Sendable {}

/// Shared-storage instance buffer. Grows 16k → 128k by doubling; `compact()` returns to 16k.
/// Glyphs beyond `maximumCapacity` stay in `instances` rather than being dropped.
@MainActor
final class GlyphInstanceBuffer {
    nonisolated static let minimumCapacity = 16_384
    nonisolated static let maximumCapacity = 131_072

    private let device: MTLDevice
    private(set) var metalBuffer: MTLBuffer
    private(set) var capacity: Int
    private(set) var count = 0
    /// Last `write` payload. Not truncated when `count` exceeds `maximumCapacity`.
    private(set) var instances: [GlyphInstance] = []

    init?(device: MTLDevice) {
        self.device = device
        self.capacity = Self.minimumCapacity
        let length = Self.minimumCapacity * MemoryLayout<GlyphInstance>.stride
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            return nil
        }
        self.metalBuffer = buffer
    }

    func write(_ instances: [GlyphInstance]) {
        self.instances = instances
        count = instances.count
        let needed = Self.capacity(forCount: instances.count)
        if needed > capacity {
            grow(to: needed)
        }
        let copyCount = min(instances.count, capacity)
        guard copyCount > 0 else {
            return
        }
        instances.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                return
            }
            metalBuffer.contents().copyMemory(
                from: base,
                byteCount: copyCount * MemoryLayout<GlyphInstance>.stride
            )
        }
    }

    func compact() {
        instances = []
        count = 0
        guard capacity != Self.minimumCapacity else {
            return
        }
        let length = Self.minimumCapacity * MemoryLayout<GlyphInstance>.stride
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            return
        }
        metalBuffer = buffer
        capacity = Self.minimumCapacity
    }

    nonisolated static func capacity(forCount count: Int) -> Int {
        var capacity = minimumCapacity
        while capacity < count && capacity < maximumCapacity {
            let doubled = capacity * 2
            if doubled <= capacity {
                break
            }
            capacity = doubled
        }
        return min(capacity, maximumCapacity)
    }

    private func grow(to newCapacity: Int) {
        let length = newCapacity * MemoryLayout<GlyphInstance>.stride
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            return
        }
        metalBuffer = buffer
        capacity = newCapacity
    }
}
