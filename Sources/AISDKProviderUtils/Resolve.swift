import Foundation

/**
 Resolves a value that could be a raw value or a closure.
 Port of `@ai-sdk/provider-utils/src/resolve.ts`
 */

// Raw value
public func resolve<T>(_ value: T) async -> T {
    return value
}

// Sync closure
public func resolve<T>(_ value: @escaping @Sendable () -> T) async -> T {
    return value()
}

// Sync throwing closure
public func resolve<T>(_ value: @escaping @Sendable () throws -> T) async throws -> T {
    return try value()
}

// Async throwing closure
public func resolve<T>(_ value: @escaping @Sendable () async throws -> T) async throws -> T {
    return try await value()
}
