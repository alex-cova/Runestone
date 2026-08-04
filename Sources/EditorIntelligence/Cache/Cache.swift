import Foundation

/// A simple bounded, actor-isolated cache for typed values.
///
/// The cache evicts the least-recently used entry when it exceeds `maxSize`.
public actor Cache<Key: Hashable & Sendable, Value: Sendable> {
    private let maxSize: Int
    private var storage: [Key: Value] = [:]
    private var accessOrder: [Key] = []

    public init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }

    /// Read a value from the cache.
    public func get(_ key: Key) -> Value? {
        if let value = storage[key] {
            recordAccess(key)
            return value
        }
        return nil
    }

    /// Store a value in the cache.
    public func set(_ value: Value, for key: Key) {
        if storage[key] == nil, storage.count >= maxSize, let oldest = accessOrder.first {
            removeValue(forKey: oldest)
        }
        storage[key] = value
        recordAccess(key)
    }

    /// Remove a value from the cache.
    public func remove(_ key: Key) {
        removeValue(forKey: key)
    }

    /// Clear all cached values.
    public func clear() {
        storage.removeAll()
        accessOrder.removeAll()
    }

    private func removeValue(forKey key: Key) {
        storage.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }

    private func recordAccess(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}
