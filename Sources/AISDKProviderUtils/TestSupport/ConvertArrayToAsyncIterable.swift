import Foundation

/**
 Creates an `AsyncStream` that yields values from the provided array in order.

 Port of `@ai-sdk/provider-utils/src/test/convert-array-to-async-iterable.ts`.
 */
public func convertArrayToAsyncIterable<Element: Sendable>(
    _ values: [Element]
) -> AsyncStream<Element> {
    AsyncStream { continuation in
        for value in values {
            continuation.yield(value)
        }
        continuation.finish()
    }
}
