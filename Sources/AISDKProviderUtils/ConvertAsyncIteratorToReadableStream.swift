import Foundation

/**
 Converts a generic async iterator into an `AsyncThrowingStream`.

 Port of `@ai-sdk/provider-utils/src/convert-async-iterator-to-readable-stream.ts`.
 */
public func convertAsyncIteratorToReadableStream<Iterator: AsyncIteratorProtocol>(
    _ iterator: Iterator
) -> AsyncThrowingStream<Iterator.Element, Error> where Iterator.Element: Sendable {
    let holder = AsyncIteratorHolder(iterator: iterator)

    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                while !Task.isCancelled {
                    guard let value = try await holder.next() else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(value)
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

private final class AsyncIteratorHolder<Iterator: AsyncIteratorProtocol>: @unchecked Sendable {
    private var iterator: Iterator

    init(iterator: Iterator) {
        self.iterator = iterator
    }

    func next() async throws -> Iterator.Element? {
        try await iterator.next()
    }
}
