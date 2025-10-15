import Foundation
import Testing
@testable import SwiftAISDK

@Suite("createUIMessageStreamResponse")
struct CreateUIMessageStreamResponseTests {
    @Test("should create response with headers and encoded stream")
    func createsResponse() async throws {
        let stream = makeChunkStream([
            .textDelta(id: "1", delta: "test-data", providerMetadata: nil)
        ])

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    headers: ["Custom-Header": "test"],
                    status: 200,
                    statusText: "OK"
                )
            )
        )

        let headers = response.options?.responseInit?.headers?.lowercasedKeys()
        #expect(headers == [
            "Custom-Header": "test",
            "content-type": "text/event-stream",
            "cache-control": "no-cache",
            "connection": "keep-alive",
            "x-vercel-ai-ui-message-stream": "v1",
            "x-accel-buffering": "no"
        ])
        #expect(response.options?.responseInit?.status == 200)
        #expect(response.options?.responseInit?.statusText == "OK")

        let chunks: [String] = try await collectStream(response.stream)
        #expect(chunks == [
            "data: {\"delta\":\"test-data\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }

    @Test("should handle error chunks")
    func handlesErrorChunk() async throws {
        let stream = makeChunkStream([
            .error(errorText: "Custom error message")
        ])

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>()
        )
        let chunks: [String] = try await collectStream(response.stream)
        #expect(chunks == [
            "data: {\"errorText\":\"Custom error message\",\"type\":\"error\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }

    @Test("should call consumeSSEStream with a teed stream")
    func forwardsToConsumer() async throws {
        let recorder = StringRecorder()
        let stream = makeChunkStream([
            .textDelta(id: "1", delta: "test-data-1", providerMetadata: nil),
            .textDelta(id: "1", delta: "test-data-2", providerMetadata: nil)
        ])

        let consumerFlag = BoolFlag()

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    consumeSSEStream: { stream in
                        await consumerFlag.set(true)
                        let values: [String] = try await collectStream(stream)
                        await recorder.append(contentsOf: values)
                    }
                )
            )
        )

        let responseChunks = try await collectStream(response.stream)

        #expect(await consumerFlag.get())
        #expect(responseChunks == [
            "data: {\"delta\":\"test-data-1\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: {\"delta\":\"test-data-2\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: [DONE]\n\n"
        ])

        try? await Task.sleep(nanoseconds: 5_000_000)
        let consumed = await recorder.items()
        #expect(consumed == responseChunks)
    }

    @Test("should not block response when consumeSSEStream takes time")
    func consumerDelayDoesNotBlock() async throws {
        let stream = makeChunkStream([
            .textDelta(id: "1", delta: "test-data", providerMetadata: nil)
        ])

        let signal = AsyncSignal()

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    headers: nil,
                    status: 200,
                    statusText: nil,
                    consumeSSEStream: { stream in
                        _ = try await collectStream(stream) as [String]
                        await signal.wait()
                    }
                )
            )
        )

        #expect(response.options?.responseInit?.status == 200)

        let chunks = try await collectStream(response.stream)
        #expect(chunks == [
            "data: {\"delta\":\"test-data\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: [DONE]\n\n"
        ])

        await signal.signal()
    }

    @Test("should handle synchronous consumeSSEStream")
    func synchronousConsumer() async throws {
        let stream = makeChunkStream([
            .textDelta(id: "1", delta: "sync-test", providerMetadata: nil)
        ])

        let consumedRecorder = StringRecorder()

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    consumeSSEStream: { stream in
                        try await stream.consume { chunk in
                            await consumedRecorder.append(contentsOf: [chunk])
                        }
                    }
                )
            )
        )

        let chunks: [String] = try await collectStream(response.stream)
        #expect(chunks == [
            "data: {\"delta\":\"sync-test\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: [DONE]\n\n"
        ])
        let consumedValues = await consumedRecorder.items()
        #expect(consumedValues == chunks)
    }

    @Test("should handle consumeSSEStream errors gracefully")
    func consumerErrorIsIgnored() async throws {
        let stream = makeChunkStream([
            .textDelta(id: "1", delta: "error-test", providerMetadata: nil)
        ])

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    consumeSSEStream: { _ in
                        throw TestError()
                    }
                )
            )
        )

        let chunks = try await collectStream(response.stream)
        #expect(chunks == [
            "data: {\"delta\":\"error-test\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }
}

// MARK: - Helpers

private func makeChunkStream(
    _ chunks: [AnyUIMessageChunk]
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}

private actor AsyncSignal {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isSignalled = false

    func wait() async {
        if isSignalled {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func signal() {
        guard !isSignalled else {
            return
        }

        isSignalled = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private struct TestError: Error {}

private extension Dictionary where Key == String, Value == String {
    func lowercasedKeys() -> [String: String] {
        reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }
}

private extension AsyncThrowingStream where Element == String, Failure == Error {
    func consume(_ body: @escaping (String) async -> Void) async throws {
        for try await element in self {
            await body(element)
        }
    }
}

private actor BoolFlag {
    private var value = false

    func set(_ newValue: Bool) {
        value = newValue
    }

    func get() -> Bool {
        value
    }
}

private actor StringRecorder {
    private var storage: [String] = []

    func append(contentsOf newValues: [String]) {
        storage.append(contentsOf: newValues)
    }

    func items() -> [String] {
        storage
    }
}
