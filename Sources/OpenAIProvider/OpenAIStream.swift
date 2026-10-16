import Foundation
import AISDKProvider
import AISDKProviderUtils

func prepareOpenAIStream<Chunk: Sendable, Request: Sendable>(
    stream: AsyncThrowingStream<ParseJSONResult<Chunk>, Error>,
    getError: @escaping @Sendable (Chunk) -> JSONValue?,
    isOutput: @escaping @Sendable (Chunk) -> Bool,
    isAccepted: (@Sendable (Chunk) -> Bool)? = nil,
    acceptedGrace: Duration = .milliseconds(50),
    url: String,
    requestBodyValues: Request,
    responseHeaders: SharedV4Headers?
) async throws -> AsyncThrowingStream<ParseJSONResult<Chunk>, Error> {
    let readiness = StreamReadiness(grace: acceptedGrace)
    let (checkedStream, continuation) = AsyncThrowingStream<ParseJSONResult<Chunk>, Error>.makeStream()
    let producer = Task {
        do {
            for try await chunk in stream {
                try Task.checkCancellation()
                if await readiness.beginChunk() {
                    switch chunk {
                    case .success(let value, _):
                        if let frame = getError(value) {
                            let error = createOpenAIProviderStreamError(frame)
                            throw APICallError(
                                message: error?.message ?? "OpenAI stream failed before any output was generated",
                                url: url,
                                requestBodyValues: requestBodyValues,
                                statusCode: error?.statusCode ?? 500,
                                responseHeaders: responseHeaders,
                                responseBody: String(decoding: try JSONEncoder().encode(frame), as: UTF8.self),
                                isRetryable: error?.isRetryable,
                                data: frame
                            )
                        }
                        continuation.yield(chunk)
                        if isOutput(value) {
                            await readiness.complete(.success(()))
                        } else {
                            await readiness.observe(accepted: isAccepted?(value) == true)
                        }
                    case .failure:
                        continuation.yield(chunk)
                        await readiness.complete(.success(()))
                    }
                } else {
                    continuation.yield(chunk)
                }
            }
            await readiness.complete(.success(()))
            continuation.finish()
        } catch {
            await readiness.complete(.failure(error))
            continuation.finish(throwing: error)
        }
    }
    continuation.onTermination = { @Sendable _ in
        producer.cancel()
        Task { await readiness.complete(.failure(CancellationError())) }
    }

    return try await withTaskCancellationHandler {
        try await readiness.wait()
        try Task.checkCancellation()
        return checkedStream
    } onCancel: {
        producer.cancel()
        continuation.finish(throwing: CancellationError())
        Task { await readiness.complete(.failure(CancellationError())) }
    }
}

private actor StreamReadiness {
    private let grace: Duration
    private var result: Result<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?
    private var accepted = false
    private var generation = 0
    private var timer: Task<Void, Never>?

    init(grace: Duration) {
        self.grace = grace
    }

    func beginChunk() -> Bool {
        guard result == nil else { return false }
        // A read wins its grace race before frame classification.
        generation += 1
        timer?.cancel()
        timer = nil
        return true
    }

    func wait() async throws {
        if let result { return try result.get() }
        try await withCheckedThrowingContinuation { waiter = $0 }
    }

    func complete(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        self.result = result
        timer?.cancel()
        timer = nil
        waiter?.resume(with: result)
        waiter = nil
    }

    func observe(accepted: Bool) {
        guard result == nil else { return }
        self.accepted = self.accepted || accepted
        guard self.accepted else { return }
        let current = generation
        timer = Task {
            do {
                try await Task.sleep(for: grace)
            } catch is CancellationError {
                return
            } catch {
                complete(.failure(error))
                return
            }
            if current == generation { complete(.success(())) }
        }
    }
}
