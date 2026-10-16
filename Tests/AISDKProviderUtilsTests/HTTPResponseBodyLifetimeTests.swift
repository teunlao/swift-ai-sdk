import Foundation
import Testing
import AISDKProviderUtils

@Suite("HTTP response body lifetime", .timeLimit(.minutes(1)))
struct HTTPResponseBodyLifetimeTests {
    @Test("closure abort cancels a pending binary response body after headers")
    func abortPendingBody() async throws {
        let flag = AbortFlag()
        let reads = AsyncStream<Void>.makeStream()
        let terminated = AsyncStream<Void>.makeStream()
        let body = PendingBody(started: reads.continuation, terminated: terminated.continuation)
        let request = Task {
            try await getFromAPI(
                url: "https://api.example.com/file",
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createBinaryResponseHandler(),
                isAborted: { flag.isAborted },
                fetch: { request in
                    FetchResponse(
                        body: .stream(AsyncThrowingStream { try await body.next() }),
                        urlResponse: HTTPURLResponse(
                            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                        )!
                    )
                }
            )
        }
        defer { request.cancel() }

        var starts = reads.stream.makeAsyncIterator()
        _ = await starts.next()
        flag.abort()

        await #expect(throws: CancellationError.self) {
            try await withDeadline {
                try await withTaskCancellationHandler {
                    _ = try await request.value
                } onCancel: {
                    request.cancel()
                }
            }
        }
        try await withDeadline {
            var endings = terminated.stream.makeAsyncIterator()
            _ = await endings.next()
        }
    }

    @Test("a returned byte stream preserves its prefix and cancels a pending pull", arguments: [false, true])
    func cancelReturnedStream(cancelTask: Bool) async throws {
        let flag = AbortFlag()
        let reads = AsyncStream<Void>.makeStream()
        let terminated = AsyncStream<Void>.makeStream()
        let prefix = Data([1, 2, 3])
        let body = PendingBody(started: reads.continuation, terminated: terminated.continuation, prefix: prefix)
        let response = try await getFromAPI(
            url: "https://api.example.com/file",
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createBinaryStreamResponseHandler(),
            isAborted: { flag.isAborted },
            fetch: bodyFetch { AsyncThrowingStream { try await body.next() } }
        )
        let consumer = Task {
            var iterator = response.value.makeAsyncIterator()
            #expect(try await iterator.next() == prefix)
            return try await iterator.next()
        }
        defer { consumer.cancel() }
        var starts = reads.stream.makeAsyncIterator()
        _ = await starts.next()
        if cancelTask {
            consumer.cancel()
        } else {
            flag.abort()
        }

        await #expect(throws: CancellationError.self) {
            try await withDeadline {
                try await withTaskCancellationHandler {
                    _ = try await consumer.value
                } onCancel: {
                    consumer.cancel()
                }
            }
        }
        try await withDeadline {
            var endings = terminated.stream.makeAsyncIterator()
            _ = await endings.next()
        }
    }

    @Test("EOF releases the source and abort observation while the result stays alive")
    func eofReleasesResources() async throws {
        let sourceReleased = AsyncStream<Void>.makeStream()
        let observerReleased = AsyncStream<Void>.makeStream()
        let response = try await getFromAPI(
            url: "https://api.example.com/file",
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createBinaryStreamResponseHandler(),
            isAborted: abortCheck(released: observerReleased.continuation),
            fetch: bodyFetch { finiteBody(released: sourceReleased.continuation) }
        )
        var iterator = response.value.makeAsyncIterator()
        #expect(try await iterator.next() == Data([1, 2]))
        #expect(try await iterator.next() == Data([3, 4]))
        #expect(try await iterator.next() == nil)
        try await withDeadline {
            var sources = sourceReleased.stream.makeAsyncIterator()
            var observers = observerReleased.stream.makeAsyncIterator()
            _ = await sources.next()
            _ = await observers.next()
        }
        withExtendedLifetime(response) {}
    }

    @Test("dropping an unread result releases the source and abort observation")
    func droppingBodyReleasesResources() async throws {
        let sourceReleased = AsyncStream<Void>.makeStream()
        let observerReleased = AsyncStream<Void>.makeStream()
        do {
            let response = try await getFromAPI(
                url: "https://api.example.com/file",
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createBinaryStreamResponseHandler(),
                isAborted: abortCheck(released: observerReleased.continuation),
                fetch: bodyFetch { finiteBody(released: sourceReleased.continuation) }
            )
            withExtendedLifetime(response) {}
        }
        try await withDeadline {
            var sources = sourceReleased.stream.makeAsyncIterator()
            var observers = observerReleased.stream.makeAsyncIterator()
            _ = await sources.next()
            _ = await observers.next()
        }
    }
}

private func bodyFetch(
    _ makeBody: @escaping @Sendable () -> AsyncThrowingStream<Data, Error>
) -> FetchFunction {
    { request in
        FetchResponse(
            body: .stream(makeBody()),
            urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
        )
    }
}

private func abortCheck(released: AsyncStream<Void>.Continuation) -> @Sendable () -> Bool {
    let resource = BodyResource(released: released)
    return { withExtendedLifetime(resource) { false } }
}

private func finiteBody(released: AsyncStream<Void>.Continuation) -> AsyncThrowingStream<Data, Error> {
    let source = BodyChunks(resource: BodyResource(released: released))
    return AsyncThrowingStream { source.next() }
}

private final class BodyResource: Sendable {
    private let released: AsyncStream<Void>.Continuation

    init(released: AsyncStream<Void>.Continuation) {
        self.released = released
    }

    deinit {
        released.yield()
    }
}

private final class BodyChunks: @unchecked Sendable {
    private let lock = NSLock()
    private let resource: BodyResource
    private var chunks: ArraySlice<Data> = [Data([1, 2]), Data([3, 4])]

    init(resource: BodyResource) {
        self.resource = resource
    }

    func next() -> Data? {
        lock.withLock { chunks.popFirst() }
    }
}

private final class AbortFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isAborted: Bool { lock.withLock { value } }

    func abort() {
        lock.withLock { value = true }
    }
}

private final class PendingBody: @unchecked Sendable {
    private let lock = NSLock()
    private let started: AsyncStream<Void>.Continuation
    private let terminated: AsyncStream<Void>.Continuation
    private var waiter: CheckedContinuation<Data?, Error>?
    private var cancelled = false
    private var prefix: Data?

    init(
        started: AsyncStream<Void>.Continuation,
        terminated: AsyncStream<Void>.Continuation,
        prefix: Data? = nil
    ) {
        self.started = started
        self.terminated = terminated
        self.prefix = prefix
    }

    func next() async throws -> Data? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let prefix {
                    self.prefix = nil
                    lock.unlock()
                    continuation.resume(returning: prefix)
                    return
                }
                waiter = continuation
                lock.unlock()
                started.yield()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let waiter = self.waiter
            self.waiter = nil
            self.lock.unlock()
            waiter?.resume(throwing: CancellationError())
            self.terminated.yield()
        }
    }
}

private enum BodyLifetimeFailure: Error {
    case deadlineExceeded
}

private func withDeadline(
    _ operation: @escaping @Sendable () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(2))
            throw BodyLifetimeFailure.deadlineExceeded
        }
        defer { group.cancelAll() }
        _ = try await group.next()
    }
}
