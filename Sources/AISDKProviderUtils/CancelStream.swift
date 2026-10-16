import Foundation

/**
 Cancels a stream owned by someone else, firing its `onTermination` so the
 producer releases its resources. Elements already buffered are discarded
 rather than read by the caller.

 Port of `ReadableStream.cancel()` for `AsyncThrowingStream`.
 */
public func cancelStream<Element: Sendable>(_ stream: AsyncThrowingStream<Element, Error>) async {
    await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        var iterator = stream.makeAsyncIterator()
        _ = try? await iterator.next()
    }.value
}

public func cancelStream<Element: Sendable>(_ stream: AsyncStream<Element>) async {
    await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
    }.value
}
