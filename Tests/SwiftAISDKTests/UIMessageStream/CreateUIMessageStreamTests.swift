import Foundation
import Testing
@testable import SwiftAISDK

/**
 Tests for `createUIMessageStream`.

 Port of `@ai-sdk/ai/src/ui-message-stream/create-ui-message-stream.test.ts`.
 */
@Suite("createUIMessageStream")
struct CreateUIMessageStreamTests {
    @Test("writes chunks and closes the stream")
    func writesChunksAndCloses() async throws {
        let stream = makeStream { writer in
            writer.write(AnyUIMessageChunk.textStart(id: "1", providerMetadata: nil))
            writer.write(AnyUIMessageChunk.textDelta(id: "1", delta: "1a", providerMetadata: nil))
            writer.write(AnyUIMessageChunk.textEnd(id: "1", providerMetadata: nil))
        }

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            AnyUIMessageChunk.textStart(id: "1", providerMetadata: nil),
            AnyUIMessageChunk.textDelta(id: "1", delta: "1a", providerMetadata: nil),
            AnyUIMessageChunk.textEnd(id: "1", providerMetadata: nil)
        ])
    }

    @Test("merge errors become error chunks")
    func mergeErrorsBecomeErrorChunks() async throws {
        struct TestError: Error {}

        let stream = makeStream(
            execute: { writer in
                writer.merge(
                    createAsyncIterableStream(source: AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
                        continuation.yield(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
                        continuation.finish(throwing: TestError())
                    })
                )
            },
            onError: { _ in "error-message" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            AnyUIMessageChunk.textDelta(id: "1", delta: "1a", providerMetadata: nil),
            AnyUIMessageChunk.error(errorText: "error-message")
        ])
    }

    @Test("async execute errors become error chunks")
    func asyncExecuteErrorsBecomeErrorChunks() async throws {
        struct TestError: Error {}

        let stream = makeStream(
            execute: { _ in
                throw TestError()
            },
            onError: { _ in "error-message" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            AnyUIMessageChunk.error(errorText: "error-message")
        ])
    }

    @Test("writing to a closed stream is ignored")
    func writingToClosedStreamIsIgnored() async throws {
        let writerBox = WriterBox<UIMessage>()

        let stream = makeStream { writer in
            writer.write(AnyUIMessageChunk.textDelta(id: "1", delta: "1a", providerMetadata: nil))
            writerBox.store(writer)
        }

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            AnyUIMessageChunk.textDelta(id: "1", delta: "1a", providerMetadata: nil)
        ])

        let writer = try #require(await writerBox.waitForValue())
        writer.write(AnyUIMessageChunk.textDelta(id: "1", delta: "1b", providerMetadata: nil))
    }

    @Test("supports delayed merged streams while another merged stream is still open")
    func supportsDelayedMergedStreams() async throws {
        let firstProbe = ChunkStreamProbe()
        let secondProbe = ChunkStreamProbe()
        let writerProbe = WriterBox<UIMessage>()
        let chunkProbe = FinishEventProbe<AnyUIMessageChunk>()

        let stream = makeStream { writer in
            writer.merge(firstProbe.stream())
            writerProbe.store(writer)
        }

        let consumeTask = Task {
            for try await chunk in stream {
                await chunkProbe.append(chunk)
            }
        }

        let writer = try #require(await writerProbe.waitForValue())
        firstProbe.yield(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
        await chunkProbe.waitUntilCount(1)
        #expect(await chunkProbe.values() == [
            AnyUIMessageChunk.textDelta(id: "1", delta: "1a", providerMetadata: nil)
        ])

        writer.merge(secondProbe.stream())

        firstProbe.finish()
        secondProbe.yield(.textDelta(id: "2", delta: "2a", providerMetadata: nil))
        secondProbe.finish()

        try await consumeTask.value

        #expect(await chunkProbe.values() == [
            AnyUIMessageChunk.textDelta(id: "1", delta: "1a", providerMetadata: nil),
            AnyUIMessageChunk.textDelta(id: "2", delta: "2a", providerMetadata: nil)
        ])
    }

    @Test("onFinish receives generated response message without original messages")
    func onFinishWithoutOriginalMessages() async throws {
        let finishEvents = FinishEventProbe<UIMessageStreamFinishEvent<UIMessage>>()

        let stream = makeStream(
            execute: { writer in
                writer.write(AnyUIMessageChunk.textStart(id: "1", providerMetadata: nil))
                writer.write(AnyUIMessageChunk.textDelta(id: "1", delta: "1a", providerMetadata: nil))
                writer.write(AnyUIMessageChunk.textEnd(id: "1", providerMetadata: nil))
            },
            onFinish: { event in
                await finishEvents.append(event)
            },
            generateId: { "response-message-id" }
        )

        await consumeStream(stream: stream)

        let captured = await finishEvents.values()
        #expect(captured.count == 1)
        guard let event = captured.first else {
            Issue.record("Expected onFinish to be called once")
            return
        }

        #expect(event.finishReason == nil)
        #expect(event.isAborted == false)
        #expect(event.isContinuation == false)
        #expect(event.messages == [event.responseMessage])
        #expect(event.responseMessage == UIMessage(
            id: "response-message-id",
            role: .assistant,
            metadata: nil,
            parts: [
                .text(TextUIPart(text: "1a", state: .done, providerMetadata: nil))
            ]
        ))
    }

    @Test("onFinish continues the last assistant message when original messages exist")
    func onFinishWithOriginalMessagesContinuation() async throws {
        let finishEvents = FinishEventProbe<UIMessageStreamFinishEvent<UIMessage>>()
        let originalMessages = [
            UIMessage(
                id: "0",
                role: .user,
                metadata: nil,
                parts: [.text(TextUIPart(text: "0a", state: .done, providerMetadata: nil))]
            ),
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [.text(TextUIPart(text: "1a", state: .done, providerMetadata: nil))]
            )
        ]

        let stream = makeStream(
            execute: { writer in
                writer.write(AnyUIMessageChunk.textStart(id: "1", providerMetadata: nil))
                writer.write(AnyUIMessageChunk.textDelta(id: "1", delta: "1b", providerMetadata: nil))
                writer.write(AnyUIMessageChunk.textEnd(id: "1", providerMetadata: nil))
            },
            originalMessages: originalMessages,
            onFinish: { event in
                await finishEvents.append(event)
            }
        )

        await consumeStream(stream: stream)

        let captured = await finishEvents.values()
        #expect(captured.count == 1)
        guard let event = captured.first else {
            Issue.record("Expected onFinish to be called once")
            return
        }

        let expectedResponse = UIMessage(
            id: "1",
            role: .assistant,
            metadata: nil,
            parts: [
                .text(TextUIPart(text: "1a", state: .done, providerMetadata: nil)),
                .text(TextUIPart(text: "1b", state: .done, providerMetadata: nil))
            ]
        )

        #expect(event.finishReason == nil)
        #expect(event.isAborted == false)
        #expect(event.isContinuation == true)
        #expect(event.responseMessage == expectedResponse)
        #expect(event.messages == [
            originalMessages[0],
            expectedResponse
        ])
    }

    @Test("injects generated messageId into start chunks when persistence is enabled")
    func injectsGeneratedMessageIdForPersistence() async throws {
        let finishEvents = FinishEventProbe<UIMessageStreamFinishEvent<UIMessage>>()
        let originalMessages = [
            UIMessage(
                id: "0",
                role: .user,
                metadata: nil,
                parts: [.text(TextUIPart(text: "0a", state: .done, providerMetadata: nil))]
            )
        ]

        let stream = makeStream(
            execute: { writer in
                writer.write(AnyUIMessageChunk.start(messageId: nil, messageMetadata: nil))
            },
            originalMessages: originalMessages,
            onFinish: { event in
                await finishEvents.append(event)
            },
            generateId: { "response-message-id" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            AnyUIMessageChunk.start(messageId: "response-message-id", messageMetadata: nil)
        ])

        let captured = await finishEvents.values()
        #expect(captured.count == 1)
        guard let event = captured.first else {
            Issue.record("Expected onFinish to be called once")
            return
        }

        let expectedResponse = UIMessage(
            id: "response-message-id",
            role: .assistant,
            metadata: nil,
            parts: []
        )

        #expect(event.isContinuation == false)
        #expect(event.responseMessage == expectedResponse)
        #expect(event.messages == [
            originalMessages[0],
            expectedResponse
        ])
    }

    @Test("keeps existing messageId from start chunks when persistence is enabled")
    func keepsExistingMessageIdForPersistence() async throws {
        let finishEvents = FinishEventProbe<UIMessageStreamFinishEvent<UIMessage>>()
        let originalMessages = [
            UIMessage(
                id: "0",
                role: .user,
                metadata: nil,
                parts: [.text(TextUIPart(text: "0a", state: .done, providerMetadata: nil))]
            )
        ]

        let stream = makeStream(
            execute: { writer in
                writer.write(AnyUIMessageChunk.start(messageId: "existing-message-id", messageMetadata: nil))
            },
            originalMessages: originalMessages,
            onFinish: { event in
                await finishEvents.append(event)
            },
            generateId: { "response-message-id" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            AnyUIMessageChunk.start(messageId: "existing-message-id", messageMetadata: nil)
        ])

        let captured = await finishEvents.values()
        #expect(captured.count == 1)
        guard let event = captured.first else {
            Issue.record("Expected onFinish to be called once")
            return
        }

        let expectedResponse = UIMessage(
            id: "existing-message-id",
            role: .assistant,
            metadata: nil,
            parts: []
        )

        #expect(event.isContinuation == false)
        #expect(event.responseMessage == expectedResponse)
        #expect(event.messages == [
            originalMessages[0],
            expectedResponse
        ])
    }

    @Test("forwards onStepFinish through createUIMessageStream")
    func forwardsOnStepFinish() async throws {
        let stepEvents = FinishEventProbe<UIMessageStreamStepFinishEvent<UIMessage>>()

        let stream = makeStream(
            execute: { writer in
                writer.write(AnyUIMessageChunk.textStart(id: "1", providerMetadata: nil))
                writer.write(AnyUIMessageChunk.textDelta(id: "1", delta: "hello", providerMetadata: nil))
                writer.write(AnyUIMessageChunk.textEnd(id: "1", providerMetadata: nil))
                writer.write(AnyUIMessageChunk.finishStep)
            },
            onStepFinish: { event in
                await stepEvents.append(event)
            },
            generateId: { "response-message-id" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            AnyUIMessageChunk.textStart(id: "1", providerMetadata: nil),
            AnyUIMessageChunk.textDelta(id: "1", delta: "hello", providerMetadata: nil),
            AnyUIMessageChunk.textEnd(id: "1", providerMetadata: nil),
            AnyUIMessageChunk.finishStep
        ])

        let captured = await stepEvents.values()
        #expect(captured.count == 1)
        guard let event = captured.first else {
            Issue.record("Expected onStepFinish to be called once")
            return
        }

        #expect(event.isContinuation == false)
        #expect(event.responseMessage.id == "response-message-id")
        #expect(event.responseMessage.parts == [
            .text(TextUIPart(text: "hello", state: .done))
        ])
    }
}

private func makeStream(
    execute: @escaping @Sendable (DefaultUIMessageStreamWriter<UIMessage>) async throws -> Void,
    onError: @escaping @Sendable (Error) -> String = { $0.localizedDescription },
    originalMessages: [UIMessage]? = nil,
    onStepFinish: UIMessageStreamOnStepFinishCallback<UIMessage>? = nil,
    onFinish: UIMessageStreamOnFinishCallback<UIMessage>? = nil,
    generateId: @escaping IDGenerator = generateID
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    createUIMessageStream(
        execute: execute,
        onError: onError,
        originalMessages: originalMessages,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        generateId: generateId
    )
}

private actor FinishEventProbe<Element: Sendable> {
    private var storage: [Element] = []
    private var countWaiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func append(_ value: Element) {
        storage.append(value)
        resumeWaitersIfNeeded()
    }

    func values() -> [Element] {
        storage
    }

    func waitUntilCount(_ expected: Int) async {
        if storage.count >= expected {
            return
        }

        await withCheckedContinuation { continuation in
            countWaiters.append((expected: expected, continuation: continuation))
        }
    }

    private func resumeWaitersIfNeeded() {
        guard !countWaiters.isEmpty else { return }

        var pending: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in countWaiters {
            if storage.count >= waiter.expected {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        countWaiters = pending
    }
}

private final class WriterBox<Message: UIMessageConvertible>: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: DefaultUIMessageStreamWriter<Message>?

    func store(_ writer: DefaultUIMessageStreamWriter<Message>) {
        lock.lock()
        self.writer = writer
        lock.unlock()
    }

    func waitForValue() async -> DefaultUIMessageStreamWriter<Message>? {
        while true {
            let writer = currentValue()
            if let writer {
                return writer
            }

            await Task.yield()
        }
    }

    private func currentValue() -> DefaultUIMessageStreamWriter<Message>? {
        lock.lock()
        let writer = self.writer
        lock.unlock()
        return writer
    }
}

private final class ChunkStreamProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation?

    func stream() -> AsyncIterableStream<AnyUIMessageChunk> {
        createAsyncIterableStream(source: AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        })
    }

    func yield(_ chunk: AnyUIMessageChunk) {
        lock.lock()
        let continuation = continuation
        lock.unlock()
        continuation?.yield(chunk)
    }

    func finish() {
        lock.lock()
        let continuation = continuation
        lock.unlock()
        continuation?.finish()
    }
}
