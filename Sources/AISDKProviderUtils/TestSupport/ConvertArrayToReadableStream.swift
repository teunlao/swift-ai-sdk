import Foundation

/**
 Creates an `AsyncThrowingStream` from an array of values.

 Port of `@ai-sdk/provider-utils/src/test/convert-array-to-readable-stream.ts`.
 */
public func convertArrayToReadableStream<Element: Sendable>(
    _ values: [Element]
) -> AsyncThrowingStream<Element, Error> {
    AsyncThrowingStream { continuation in
        for value in values {
            continuation.yield(value)
        }
        continuation.finish()
    }
}
