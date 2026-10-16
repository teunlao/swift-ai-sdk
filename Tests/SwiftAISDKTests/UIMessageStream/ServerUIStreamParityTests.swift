import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK

@Suite("server UI stream lifecycle parity")
struct ServerUIStreamParityTests {
    @Test("writer failures are masked and override declared completion")
    func failureOutcome() async throws {
        let events = UIEndEvents()
        let stream: AsyncThrowingStream<AnyUIMessageChunk, Error> = createUIMessageStream(
            execute: { (writer: DefaultUIMessageStreamWriter<UIMessage>) in
                writer.setOutcome(.completed)
                throw ServerFailure()
            },
            onEnd: { await events.append($0) }
        )
        let chunks = try await collect(stream)
        #expect(chunks == [.error(errorText: "An error occurred.")])
        let event = try #require(await events.values().first)
        #expect(event.outcome.status == "failed")
        guard case .failed(let error) = event.outcome else { return }
        #expect(error is ServerFailure)
        #expect(event.isCancelled == nil)
    }

    @Test("a merged source cancellation error is a failure when the consumer is active")
    func sourceCancellationError() async throws {
        let events = UIEndEvents()
        let stream: AsyncThrowingStream<AnyUIMessageChunk, Error> = createUIMessageStream(
            execute: { (writer: DefaultUIMessageStreamWriter<UIMessage>) in
                writer.merge(createAsyncIterableStream(source: AsyncThrowingStream<AnyUIMessageChunk, Error> { $0.finish(throwing: CancellationError()) }))
            },
            onEnd: { await events.append($0) }
        )
        #expect(try await collect(stream) == [.error(errorText: "An error occurred.")])
        let event = try #require(await events.values().first)
        #expect(event.outcome.status == "failed")
        #expect(event.isCancelled == nil)
    }

    @Test("fatal processing errors override owner outcomes")
    func processingFailureOutcome() async throws {
        let events = UIEndEvents()
        let stream: AsyncThrowingStream<AnyUIMessageChunk, Error> = createUIMessageStream(
            execute: { (writer: DefaultUIMessageStreamWriter<UIMessage>) in
                writer.setOutcome(.completed)
                writer.write(.textDelta(id: "missing", delta: "text", providerMetadata: nil))
            },
            onEnd: { await events.append($0) }
        )
        do { _ = try await collect(stream); Issue.record("Expected invalid stream to fail") }
        catch { #expect(error is UIMessageStreamError) }
        let event = try #require(await events.values().first)
        #expect(event.outcome.status == "failed")
        guard case .failed(let error) = event.outcome else { return }
        #expect(error is UIMessageStreamError)
    }

    @Test("consumer cancellation is separate from an unknown operation outcome")
    func consumerCancellation() async throws {
        let source = AsyncThrowingStream<AnyUIMessageChunk, Error>.makeStream()
        defer { source.continuation.finish() }
        let observation = SSEObservation()
        let events = UIEndEvents()
        let stream: AsyncThrowingStream<AnyUIMessageChunk, Error> = createUIMessageStream(
            execute: { (writer: DefaultUIMessageStreamWriter<UIMessage>) in
                writer.write(.start(messageId: "message", messageMetadata: nil))
                writer.merge(createAsyncIterableStream(source: source.stream))
            },
            onEnd: { await events.append($0) }
        )
        let consumer = Task {
            for try await _ in stream { await observation.observeFirst() }
        }
        await observation.waitForFirst()
        consumer.cancel()
        _ = try await consumer.value
        let event = await events.waitForFirst()
        #expect(event.outcome.status == "unknown")
        #expect(event.isCancelled == true)
        #expect(event.isAborted == false)
    }

    @Test("end callback failures reject the output stream")
    func endCallbackFailure() async {
        let stream: AsyncThrowingStream<AnyUIMessageChunk, Error> = createUIMessageStream(
            execute: { (writer: DefaultUIMessageStreamWriter<UIMessage>) in writer.setOutcome(.completed) },
            onEnd: { _ in throw ServerFailure() }
        )
        do { _ = try await collect(stream); Issue.record("End callback failure was discarded") }
        catch { #expect(error is ServerFailure) }
    }

    @Test("step metadata is applied before end snapshots and new callbacks win")
    func callbackOrdering() async throws {
        let events = UIEndEvents()
        let steps = UIStepEvents()
        let parts: [TextStreamPart] = [
            .start, .startStep(request: LanguageModelRequestMetadata(), warnings: []),
            .textStart(id: "text", providerMetadata: nil),
            .textDelta(id: "text", text: "answer", providerMetadata: nil),
            .textEnd(id: "text", providerMetadata: nil),
            .finishStep(response: LanguageModelResponseMetadata(id: "response", timestamp: Date(), modelId: "model"),
                        usage: LanguageModelUsage(), performance: .empty, finishReason: .stop, rawFinishReason: nil, providerMetadata: nil),
            .finish(finishReason: .stop, rawFinishReason: nil, totalUsage: LanguageModelUsage())
        ]
        let input = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }
        let stream = toUIMessageStream(stream: input, options: UIMessageStreamOptions<UIMessage>(
            onFinish: { _ in Issue.record("Deprecated callback took precedence") },
            messageMetadata: { part in
                if case .finishStep = part { return .object(["step": .number(1)]) }
                return nil
            },
            onEnd: { await events.append($0) },
            onStepEnd: { await steps.append($0) },
            onStepFinish: { _ in Issue.record("Deprecated step callback took precedence") }
        ))
        let chunks = try await collect(stream)
        let boundary = try #require(chunks.firstIndex(of: .finishStep))
        #expect(chunks[boundary - 1] == .messageMetadata(.object(["step": .number(1)])))
        let step = try #require(await steps.values().first)
        #expect(step.responseMessage.metadata == .object(["step": .number(1)]))
        #expect(step.responseMessage.parts.last == .text(TextUIPart(text: "answer", state: .done)))
        let event = try #require(await events.values().first)
        #expect(event.outcome.status == "completed")
        #expect(event.finishReason == .stop)
    }

    @Test("conversion keeps explicit source boundaries and masks application tool errors")
    func singleChunkConversion() {
        #expect(toUIMessageChunk(.custom(kind: "provider.state", providerMetadata: nil)) == .custom(kind: "provider.state", providerMetadata: nil))
        let error = TypedToolError.static(StaticToolError(toolCallId: "call", toolName: "shell", input: .null, error: ServerFailure()))
        #expect(toUIMessageChunk(.toolError(error)) == .toolOutputError(toolCallId: "call", errorText: "An error occurred.", providerExecuted: nil, providerMetadata: nil, dynamic: false))
    }

    @Test("generated files preserve their data URI and provider metadata")
    func generatedFileMetadata() {
        let metadata: ProviderMetadata = ["provider": ["id": .string("file")]]
        let file = DefaultGeneratedFile(data: Data([1]), mediaType: "image/png", providerMetadata: metadata)
        #expect(toUIMessageChunk(.file(file: file, providerMetadata: nil)) == .file(url: "data:image/png;base64,AQ==",
                                                      mediaType: "image/png", providerMetadata: metadata))
    }

    @Test("keep-alive sends opening and idle comments without replacing source data")
    func keepAlive() async throws {
        let source = AsyncThrowingStream<String, Error>.makeStream()
        let output = try createSSEStreamWithKeepAlive(stream: source.stream, keepAliveMs: 1)
        var iterator = output.makeAsyncIterator()
        #expect(try await iterator.next() == ": stream-open\n\n")
        #expect(try await iterator.next() == ": keep-alive\n\n")
        source.continuation.yield("data: payload\n\n")
        source.continuation.finish()
        var remaining: [String] = []
        while let value = try await iterator.next() { remaining.append(value) }
        #expect(remaining.filter { !$0.hasPrefix(":") } == ["data: payload\n\n"])
    }

    @Test("keep-alive rejects invalid timer durations at its public boundary")
    func invalidKeepAlive() {
        for duration in [0.0, -1, Double.infinity, Double.nan, 2_147_483_648] {
            let source = AsyncThrowingStream<String, Error> { $0.finish() }
            do {
                _ = try createSSEStreamWithKeepAlive(stream: source, keepAliveMs: duration)
                Issue.record("Invalid timer duration was accepted")
            } catch {
                #expect(error.localizedDescription == "keepAliveMs must be a positive finite timer duration no greater than 2147483647")
            }
        }
    }

    @Test("response construction rejects invalid keep-alive before returning a response")
    func invalidResponseKeepAlive() {
        do {
            let _: UIMessageStreamResponse<UIMessage> = try createUIMessageStreamResponse(
                stream: AsyncThrowingStream { $0.finish() },
                options: StreamTextUIResponseOptions(responseInit: UIMessageStreamResponseInit(keepAliveMs: .infinity))
            )
            Issue.record("Invalid keep-alive was accepted")
        } catch {
            #expect(error.localizedDescription == "keepAliveMs must be a positive finite timer duration no greater than 2147483647")
        }
    }

    @Test("response piping completes the writer and propagates source failures")
    func pipeFailure() async throws {
        let response = PipeResponse()
        let stream = AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
            continuation.yield(.error(errorText: "event"))
            continuation.finish(throwing: ServerFailure())
        }
        do {
            try await pipeUIMessageStreamToResponse(response: response, stream: stream,
                options: StreamTextUIResponseOptions<UIMessage>())
            Issue.record("Source failure was discarded")
        } catch { #expect(error is ServerFailure) }
        #expect(response.result().ended)
        #expect(response.result().body == "data: {\"errorText\":\"event\",\"type\":\"error\"}\n\n")
    }

    @Test("independent SSE consumption continues after response cancellation")
    func independentConsumer() async throws {
        let source = AsyncThrowingStream<AnyUIMessageChunk, Error>.makeStream()
        let observation = SSEObservation()
        let response: UIMessageStreamResponse<UIMessage> = try createUIMessageStreamResponse(
            stream: source.stream,
            options: StreamTextUIResponseOptions(responseInit: UIMessageStreamResponseInit(consumeSSEStream: { stream in
                var values: [String] = []
                for try await value in stream {
                    values.append(value)
                    await observation.observeFirst()
                }
                await observation.complete(values)
            }))
        )
        let responseTask = Task { for try await _ in response.stream {} }
        source.continuation.yield(.start(messageId: "message", messageMetadata: nil))
        await observation.waitForFirst()
        responseTask.cancel()
        _ = try await responseTask.value
        source.continuation.yield(.finish(finishReason: .stop, messageMetadata: nil))
        source.continuation.finish()
        let values = await observation.waitForCompletion()
        #expect(values.last == "data: [DONE]\n\n")
        #expect(values.count == 3)
    }

    private func collect<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
        var values: [T] = []
        for try await value in stream { values.append(value) }
        return values
    }
}

private struct ServerFailure: Error {}

private final class PipeResponse: StreamTextResponseWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var body = Data()
    private var ended = false

    func writeHead(status: Int, statusText: String?, headers: [String: String]) {}
    func write(_ data: Data) { lock.lock(); body.append(data); lock.unlock() }
    func end() { lock.lock(); ended = true; lock.unlock() }
    func result() -> (body: String, ended: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (String(decoding: body, as: UTF8.self), ended)
    }
}

private actor SSEObservation {
    private var firstObserved = false
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private var values: [String]?
    private var completionWaiter: CheckedContinuation<[String], Never>?

    func observeFirst() {
        firstObserved = true
        firstWaiter?.resume()
        firstWaiter = nil
    }
    func waitForFirst() async {
        if firstObserved { return }
        await withCheckedContinuation { firstWaiter = $0 }
    }
    func complete(_ values: [String]) {
        self.values = values
        completionWaiter?.resume(returning: values)
        completionWaiter = nil
    }
    func waitForCompletion() async -> [String] {
        if let values { return values }
        return await withCheckedContinuation { completionWaiter = $0 }
    }
}

private actor UIEndEvents {
    private var events: [UIMessageStreamEndEvent<UIMessage>] = []
    private var waiter: CheckedContinuation<UIMessageStreamEndEvent<UIMessage>, Never>?
    func append(_ event: UIMessageStreamEndEvent<UIMessage>) {
        events.append(event)
        waiter?.resume(returning: event)
        waiter = nil
    }
    func values() -> [UIMessageStreamEndEvent<UIMessage>] { events }
    func waitForFirst() async -> UIMessageStreamEndEvent<UIMessage> {
        if let event = events.first { return event }
        return await withCheckedContinuation { waiter = $0 }
    }
}

private actor UIStepEvents {
    private var events: [UIMessageStreamStepEndEvent<UIMessage>] = []
    func append(_ event: UIMessageStreamStepEndEvent<UIMessage>) { events.append(event) }
    func values() -> [UIMessageStreamStepEndEvent<UIMessage>] { events }
}
