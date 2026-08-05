import Foundation

/// A minimal dependency injection container for EIP services.
///
/// Services are registered by type and resolved lazily. The container supports both singletons
/// and factory-based registration.
public final class DependencyContainer {
    private var registrations: [ObjectIdentifier: () -> Any] = [:]
    private var singletons: [ObjectIdentifier: Any] = [:]
    private let lock = NSLock()

    public init() {}

    /// Register a factory that creates a new instance on each resolve.
    public func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        lock.withLock {
            registrations[ObjectIdentifier(type)] = factory
            singletons.removeValue(forKey: ObjectIdentifier(type))
        }
    }

    /// Register a singleton instance.
    public func registerSingleton<T>(_ instance: T, as type: T.Type = T.self) {
        lock.withLock {
            singletons[ObjectIdentifier(type)] = instance
            registrations.removeValue(forKey: ObjectIdentifier(type))
        }
    }

    /// Resolve a registered service.
    public func resolve<T>(_ type: T.Type = T.self) -> T? {
        lock.withLock {
            let key = ObjectIdentifier(type)
            if let singleton = singletons[key] as? T {
                return singleton
            }
            if let factory = registrations[key] {
                return factory() as? T
            }
            return nil
        }
    }

    /// Resolve a service or throw a dependency error.
    public func resolveRequired<T>(_ type: T.Type = T.self) throws -> T {
        guard let value = resolve(type) else {
            throw DependencyError.missing(String(describing: type))
        }
        return value
    }
}

public enum DependencyError: Error {
    case missing(String)
}
