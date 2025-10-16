import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Result container, возвращаемый `streamObject`, предоставляющий доступ к частичным
 результатам, потокам текста и метаданным.

 Port of `@ai-sdk/ai/src/generate-object/stream-object-result.ts`.
 */
public final class StreamObjectResult<PartialValue: Sendable, ResultValue: Sendable, ElementStream>: @unchecked Sendable {
    private let objectPromise = DelayedPromise<ResultValue>()
    private let usagePromise = DelayedPromise<LanguageModelUsage>()
    private let providerMetadataPromise = DelayedPromise<ProviderMetadata?>()
    private let warningsPromise = DelayedPromise<[CallWarning]?>()
    private let requestPromise = DelayedPromise<LanguageModelRequestMetadata>()
    private let responsePromise = DelayedPromise<LanguageModelResponseMetadata>()
    private let finishReasonPromise = DelayedPromise<FinishReason>()

    private let broadcaster = AsyncStreamBroadcaster<ObjectStreamPart<PartialValue>>()
    private let makeElementStream: @Sendable (AsyncIterableStream<ObjectStreamPart<PartialValue>>) -> ElementStream

    public init(
        createElementStream: @escaping @Sendable (AsyncIterableStream<ObjectStreamPart<PartialValue>>) -> ElementStream
    ) {
        self.makeElementStream = createElementStream
    }

    // MARK: - Promised values

    public var object: ResultValue {
        get async throws { try await objectPromise.task.value }
    }

    public var usage: LanguageModelUsage {
        get async throws { try await usagePromise.task.value }
    }

    public var providerMetadata: ProviderMetadata? {
        get async throws { try await providerMetadataPromise.task.value }
    }

    public var warnings: [CallWarning]? {
        get async throws { try await warningsPromise.task.value }
    }

    public var request: LanguageModelRequestMetadata {
        get async throws { try await requestPromise.task.value }
    }

    public var response: LanguageModelResponseMetadata {
        get async throws { try await responsePromise.task.value }
    }

    public var finishReason: FinishReason {
        get async throws { try await finishReasonPromise.task.value }
    }

    // MARK: - Streams

    public var partialObjectStream: AsyncIterableStream<PartialValue> {
        makePartialStream()
    }

    public var elementStream: ElementStream {
        makeElementStream(makeBaseStream())
    }

    public var textStream: AsyncIterableStream<String> {
        makeTextStream()
    }

    public var fullStream: AsyncIterableStream<ObjectStreamPart<PartialValue>> {
        makeBaseStream()
    }

    public func pipeTextStreamToResponse(
        _ response: any StreamTextResponseWriter,
        init initOptions: TextStreamResponseInit? = nil
    ) {
        let stream = makeTextThrowingStream()
        SwiftAISDK.pipeTextStreamToResponse(
            response: response,
            status: initOptions?.status,
            statusText: initOptions?.statusText,
            headers: initOptions?.headers,
            textStream: stream
        )
    }

    public func toTextStreamResponse(
        init initOptions: TextStreamResponseInit? = nil
    ) -> TextStreamResponse {
        let stream = makeTextThrowingStream()
        return SwiftAISDK.createTextStreamResponse(
            status: initOptions?.status,
            statusText: initOptions?.statusText,
            headers: initOptions?.headers,
            textStream: stream
        )
    }

    // MARK: - Internal resolution

    internal func resolveObject(_ value: ResultValue) {
        objectPromise.resolve(value)
    }

    internal func rejectObject(_ error: any Error) {
        objectPromise.reject(error)
    }

    internal func resolveUsage(_ usage: LanguageModelUsage) {
        usagePromise.resolve(usage)
    }

    internal func resolveProviderMetadata(_ metadata: ProviderMetadata?) {
        providerMetadataPromise.resolve(metadata)
    }

    internal func resolveWarnings(_ warnings: [CallWarning]?) {
        warningsPromise.resolve(warnings)
    }

    internal func resolveRequest(_ metadata: LanguageModelRequestMetadata) {
        requestPromise.resolve(metadata)
    }

    internal func resolveResponse(_ metadata: LanguageModelResponseMetadata) {
        responsePromise.resolve(metadata)
    }

    internal func resolveFinishReason(_ reason: FinishReason) {
        finishReasonPromise.resolve(reason)
    }

    internal func publish(_ part: ObjectStreamPart<PartialValue>) async {
        await broadcaster.send(part)
    }

    internal func endStream(error: Error? = nil) async {
        await broadcaster.finish(error: error)
    }

    // MARK: - Helpers

    private func makeBaseStream() -> AsyncIterableStream<ObjectStreamPart<PartialValue>> {
        createAsyncIterableStream(
            source: AsyncThrowingStream { continuation in
                let worker = Task {
                    let source = await broadcaster.register()
                    do {
                        var iterator = source.makeAsyncIterator()
                        while let value = try await iterator.next() {
                            continuation.yield(value)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    worker.cancel()
                }
            }
        )
    }

    private func makePartialStream() -> AsyncIterableStream<PartialValue> {
        let base = makeBaseStream()
        return createAsyncIterableStream(
            source: AsyncThrowingStream { continuation in
                let worker = Task {
                    do {
                        var iterator = base.makeAsyncIterator()
                        while let part = try await iterator.next() {
                            switch part {
                            case .object(let value):
                                continuation.yield(value)
                            case .textDelta, .finish:
                                continue
                            case .error:
                                continue
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    worker.cancel()
                }
            }
        )
    }

    private func makeTextStream() -> AsyncIterableStream<String> {
        let base = makeBaseStream()
        return createAsyncIterableStream(
            source: AsyncThrowingStream { continuation in
                let worker = Task {
                    do {
                        var iterator = base.makeAsyncIterator()
                        while let part = try await iterator.next() {
                            switch part {
                            case .textDelta(let delta):
                                continuation.yield(delta)
                            case .object, .finish:
                                continue
                            case .error:
                                continue
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    worker.cancel()
                }
            }
        )
    }

    private func makeTextThrowingStream() -> AsyncThrowingStream<String, Error> {
        let stream = textStream
        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    var iterator = stream.makeAsyncIterator()
                    while let chunk = try await iterator.next() {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
                Task { await stream.cancel() }
            }
        }
    }
}
