/**
 Helper function that throws "Not implemented" error.

 Port of `@ai-sdk/ai/src/test/not-implemented.ts`.

 Used in mock models to provide default behavior that fails if not overridden.
 */

import Foundation

/// Error thrown when a mock method is called without being implemented.
public struct NotImplementedError: Error, CustomStringConvertible {
    public let description: String

    public init(description: String = "Not implemented") {
        self.description = description
    }
}

/// Throws a NotImplementedError. Used as default implementation in mock models.
public func notImplemented<T>() throws -> T {
    throw NotImplementedError()
}
