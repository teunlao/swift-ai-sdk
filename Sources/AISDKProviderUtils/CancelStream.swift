import Foundation

/**
 Cancels a stream owned by someone else, firing its `onTermination` so the
 producer releases its resources. Elements already buffered are discarded
 rather than read by the caller.

 Port of `ReadableStream.cancel()` for `AsyncThrowingStream`.
 */
func cancelStream<Element: Sendable>(_ stream: AsyncThrowingStream<Element, Error>) async {
    let task = Task {
        var iterator = stream.makeAsyncIterator()
        // In a cancelled task, `next()` terminates the stream instead of waiting.
        while (try? await iterator.next()) != nil {}
    }
    task.cancel()
    await task.value
}
