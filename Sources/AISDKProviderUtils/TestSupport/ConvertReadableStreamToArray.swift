import Foundation

/**
 Collects all elements from an async stream (ReadableStream equivalent) into an array.

 Port of `@ai-sdk/provider-utils/src/test/convert-readable-stream-to-array.ts`.
 */
public func convertReadableStreamToArray<Element>(
    _ stream: AsyncThrowingStream<Element, Error>
) async throws -> [Element] {
    try await convertAsyncIterableToArray(stream)
}
