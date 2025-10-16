import Foundation
import AISDKProvider
import AISDKProviderUtils
import Testing
@testable import SwiftAISDK

/**
 Tests for creating UI message stream responses.

 Port of `@ai-sdk/ai/src/ui-message-stream/create-ui-message-stream-response.test.ts`.
 */
@Suite("createUIMessageStreamResponse")
struct CreateUIMessageStreamResponseTests {
    @Test("should create a Response with correct headers and encoded stream")
    func createsResponseWithHeadersAndStream() async throws {
        let stream = makeAsyncStream(from: [
            AnyUIMessageChunk.textDelta(id: "1", delta: "test-data", providerMetadata: nil)
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

        let headers = response.options?.responseInit?.headers?.lowercasedKeys() ?? [:]
        #expect(headers == [
            "content-type": "text/event-stream",
            "cache-control": "no-cache",
            "connection": "keep-alive",
            "x-vercel-ai-ui-message-stream": "v1",
            "x-accel-buffering": "no",
            "custom-header": "test"
        ])

        #expect(response.options?.responseInit?.status == 200)
        #expect(response.options?.responseInit?.statusText == "OK")

        let chunks = try await collectStream(response.stream)
        #expect(chunks == [
            "data: {\"delta\":\"test-data\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }

    @Test("should handle errors in the stream")
    func handlesErrorsInStream() async throws {
        let stream = makeAsyncStream(from: [
            AnyUIMessageChunk.error(errorText: "Custom error message")
        ])

        let response: UIMessageStreamResponse<UIMessage> = createUIMessageStreamResponse(stream: stream)
        let chunks = try await collectStream(response.stream)

        #expect(chunks == [
            "data: {\"errorText\":\"Custom error message\",\"type\":\"error\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }

    @Test("should call consumeSseStream with a teed stream")
    func callsConsumeSSEStreamWithTeedStream() async throws {
        let probe = StreamConsumerProbe()
        let stream = makeAsyncStream(from: [
            AnyUIMessageChunk.textDelta(id: "1", delta: "test-data-1", providerMetadata: nil),
            AnyUIMessageChunk.textDelta(id: "1", delta: "test-data-2", providerMetadata: nil)
        ])

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    consumeSSEStream: { stream in
                        let values = try await collectStream(stream)
                        await probe.record(values)
                    }
                )
            )
        )

        let responseChunks = try await collectStream(response.stream)
        #expect(responseChunks == [
            "data: {\"delta\":\"test-data-1\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: {\"delta\":\"test-data-2\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: [DONE]\n\n"
        ])

        let consumed = await probe.awaitValues()
        #expect(consumed == responseChunks)
        #expect(await probe.callCount() == 1)
    }

    @Test("should not block the response when consumeSseStream takes time")
    func consumeSSEStreamDoesNotBlockResponse() async throws {
        let probe = StreamConsumerProbe()
        let gate = AsyncGate()

        let stream = makeAsyncStream(from: [
            AnyUIMessageChunk.textDelta(id: "1", delta: "test-data", providerMetadata: nil)
        ])

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    consumeSSEStream: { stream in
                        let values = try await collectStream(stream)
                        await probe.record(values)
                        await gate.wait()
                    }
                )
            )
        )

        let responseChunks = try await collectStream(response.stream)
        #expect(responseChunks == [
            "data: {\"delta\":\"test-data\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: [DONE]\n\n"
        ])

        await probe.waitForCalls(1)
        #expect(await probe.callCount() == 1)
        await gate.open()

        let consumed = await probe.awaitValues()
        #expect(consumed == responseChunks)
    }

    @Test("should handle consumeSseStream errors gracefully")
    func handlesConsumeSSEStreamErrors() async throws {
        let probe = StreamConsumerProbe()

        struct TestError: Error {}

        let stream = makeAsyncStream(from: [
            AnyUIMessageChunk.textDelta(id: "1", delta: "error-test", providerMetadata: nil)
        ])

        let response = createUIMessageStreamResponse(
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    consumeSSEStream: { _ in
                        await probe.registerCall()
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

        await probe.waitForCalls(1)
        #expect(await probe.callCount() == 1)
    }
}

// MARK: - Support Types

private actor StreamConsumerProbe {
    private var valuesQueue: [[String]] = []
    private var waiters: [CheckedContinuation<[String], Never>] = []
    private var calls = 0
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record(_ values: [String]) {
        calls += 1
        resumeCallWaitersIfNeeded()
        if waiters.isEmpty {
            valuesQueue.append(values)
        } else {
            let continuation = waiters.removeFirst()
            continuation.resume(returning: values)
        }
    }

    func registerCall() {
        calls += 1
        resumeCallWaitersIfNeeded()
    }

    func awaitValues() async -> [String] {
        if !valuesQueue.isEmpty {
            return valuesQueue.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func callCount() -> Int {
        calls
    }

    func waitForCalls(_ expected: Int) async {
        if calls >= expected {
            return
        }

        await withCheckedContinuation { continuation in
            callWaiters.append((expected, continuation))
        }
    }

    private func resumeCallWaitersIfNeeded() {
        guard !callWaiters.isEmpty else { return }

        var pending: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expected, continuation) in callWaiters {
            if calls >= expected {
                continuation.resume()
            } else {
                pending.append((expected, continuation))
            }
        }
        callWaiters = pending
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let captured = waiters
        waiters.removeAll()
        for continuation in captured {
            continuation.resume()
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    func lowercasedKeys() -> [String: String] {
        reduce(into: [:]) { partialResult, element in
            partialResult[element.key.lowercased()] = element.value
        }
    }
}
