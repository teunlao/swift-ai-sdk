import Foundation
import AISDKProvider
import AISDKProviderUtils

func prepareOpenAIStream<Chunk: Sendable, Request: Sendable>(
    stream: AsyncThrowingStream<ParseJSONResult<Chunk>, Error>,
    getError: @escaping @Sendable (Chunk) -> JSONValue?,
    isOutput: @escaping @Sendable (Chunk) -> Bool,
    url: String,
    requestBodyValues: Request,
    responseHeaders: SharedV4Headers?
) async throws -> AsyncThrowingStream<ParseJSONResult<Chunk>, Error> {
    let readiness = StreamReadiness()
    let (checkedStream, continuation) = AsyncThrowingStream<ParseJSONResult<Chunk>, Error>.makeStream()
    let producer = Task {
        do {
            for try await chunk in stream {
                try Task.checkCancellation()
                if await readiness.isPending {
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
    private var result: Result<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?

    var isPending: Bool { result == nil }

    func wait() async throws {
        if let result { return try result.get() }
        try await withCheckedThrowingContinuation { waiter = $0 }
    }

    func complete(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        self.result = result
        waiter?.resume(with: result)
        waiter = nil
    }
}
