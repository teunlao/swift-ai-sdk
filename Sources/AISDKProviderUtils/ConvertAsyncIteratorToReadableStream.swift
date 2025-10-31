import Foundation

/**
 Converts a generic async iterator into an `AsyncThrowingStream`.

 Port of `@ai-sdk/provider-utils/src/convert-async-iterator-to-readable-stream.ts`.
 */
@preconcurrency
public func convertAsyncIteratorToReadableStream<Iterator: AsyncIteratorProtocol>(
    _ iterator: Iterator
) -> AsyncThrowingStream<Iterator.Element, Error> where Iterator.Element: Sendable {
    let holder = AnyAsyncIteratorHolder(iterator)

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

private final class AnyAsyncIteratorHolder<Element: Sendable>: @unchecked Sendable {
    private let nextClosure: () async throws -> Element?

    init<Iterator: AsyncIteratorProtocol>(_ iterator: Iterator) where Iterator.Element == Element {
        let storage = UncheckedSendableBox(value: iterator)
        let actor = AsyncIteratorActor(storage: storage)
        self.nextClosure = {
            try await actor.next()
        }
    }

    func next() async throws -> Element? {
        try await nextClosure()
    }
}

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    var value: Value
}

private actor AsyncIteratorActor<Iterator: AsyncIteratorProtocol> {
    private var storage: UncheckedSendableBox<Iterator>

    init(storage: UncheckedSendableBox<Iterator>) {
        self.storage = storage
    }

    func next() async throws -> Iterator.Element? {
        var iterator = storage.value
        let result = try await iterator.next()
        storage.value = iterator
        return result
    }
}
