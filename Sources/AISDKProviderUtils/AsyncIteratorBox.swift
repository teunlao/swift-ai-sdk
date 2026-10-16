import Foundation

/**
 Holds the iterator of a source sequence for a pull-based stream: each `next()`
 pulls exactly one element, in the consumer's task. Demand therefore paces the
 source, consumer cancellation reaches it, and releasing the stream releases the
 source iterator.

 Callers pull from one consumer at a time, as `AsyncThrowingStream(unfolding:)` does.
 */
final class AsyncIteratorBox<Base: AsyncIteratorProtocol>: @unchecked Sendable {
    private var iterator: Base

    init(_ iterator: Base) {
        self.iterator = iterator
    }

    func next() async throws -> Base.Element? {
        try await iterator.next()
    }
}
