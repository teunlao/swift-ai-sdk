import Foundation
import Testing
@testable import SwiftAISDK

@Suite("createUIMessageStream")
struct CreateUIMessageStreamTests {
    @Test("should send data stream part and close the stream")
    func writesChunks() async throws {
        let stream = createUIMessageStream { writer in
            writer.write(.textStart(id: "1", providerMetadata: nil))
            writer.write(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
            writer.write(.textEnd(id: "1", providerMetadata: nil))
        }

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "1a", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ])
    }

    @Test("should forward a single stream with 2 elements")
    func mergesSingleStream() async throws {
        let controller = ControllableChunkStream()

        let stream = createUIMessageStream { writer in
            writer.merge(controller.iterable)
        }

        await controller.yield(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
        await controller.yield(.textDelta(id: "1", delta: "1b", providerMetadata: nil))
        await controller.finish()

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            .textDelta(id: "1", delta: "1a", providerMetadata: nil),
            .textDelta(id: "1", delta: "1b", providerMetadata: nil)
        ])
    }

    @Test("should send async message annotation and close the stream")
    func writesAfterAwait() async throws {
        let stream = createUIMessageStream { writer in
            try await Task.sleep(nanoseconds: 5_000_000)
            writer.write(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
        }

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            .textDelta(id: "1", delta: "1a", providerMetadata: nil)
        ])
    }

    @Test("should forward elements from multiple streams and data parts")
    func mergesMultipleStreams() async throws {
        let first = ControllableChunkStream()
        let second = ControllableChunkStream()

        let stream = createUIMessageStream(
            execute: { writer in
                writer.write(.textDelta(id: "1", delta: "data-part-1", providerMetadata: nil))
                writer.merge(first.iterable)
                writer.write(.textDelta(id: "1", delta: "data-part-2", providerMetadata: nil))
                writer.merge(second.iterable)
                writer.write(.textDelta(id: "1", delta: "data-part-3", providerMetadata: nil))
            },
            onError: { _ in "error-message" }
        )

        await first.yield(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
        await first.yield(.textDelta(id: "1", delta: "1b", providerMetadata: nil))
        await second.yield(.textDelta(id: "2", delta: "2a", providerMetadata: nil))
        await first.yield(.textDelta(id: "1", delta: "1c", providerMetadata: nil))
        await second.yield(.textDelta(id: "2", delta: "2b", providerMetadata: nil))
        await second.finish()
        await first.yield(.textDelta(id: "1", delta: "1d", providerMetadata: nil))
        await first.yield(.textDelta(id: "1", delta: "1e", providerMetadata: nil))
        await first.finish()

        let chunks = try await collectStream(stream)

        // Data parts are always first in order
        #expect(chunks[0] == .textDelta(id: "1", delta: "data-part-1", providerMetadata: nil))
        #expect(chunks[1] == .textDelta(id: "1", delta: "data-part-2", providerMetadata: nil))
        #expect(chunks[2] == .textDelta(id: "1", delta: "data-part-3", providerMetadata: nil))

        // Merged streams: order may vary in parallel execution, check all present
        #expect(chunks.count == 10)
        let deltas = chunks.compactMap { chunk -> String? in
            if case .textDelta(_, let delta, _) = chunk { return delta }
            return nil
        }
        #expect(deltas.contains("1a"))
        #expect(deltas.contains("1b"))
        #expect(deltas.contains("1c"))
        #expect(deltas.contains("1d"))
        #expect(deltas.contains("1e"))
        #expect(deltas.contains("2a"))
        #expect(deltas.contains("2b"))
    }

    @Test("should add error parts when stream errors")
    func addsErrorChunkOnMergeFailure() async throws {
        let controller = ControllableChunkStream()

        let stream = createUIMessageStream(
            execute: { writer in
                writer.merge(controller.iterable)
            },
            onError: { _ in "error-message" }
        )

        await controller.yield(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
        await controller.fail(TestError())

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            .textDelta(id: "1", delta: "1a", providerMetadata: nil),
            .error(errorText: "error-message")
        ])
    }

    @Test("should add error parts when execute throws")
    func addsErrorChunkOnExecuteThrow() async throws {
        let stream = createUIMessageStream(
            execute: { _ in
                throw TestError()
            },
            onError: { _ in "error-message" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            .error(errorText: "error-message")
        ])
    }

    @Test("should add error parts when execute throws with promise")
    func addsErrorChunkOnAsyncThrow() async throws {
        let stream = createUIMessageStream(
            execute: { _ in
                try await Task.sleep(nanoseconds: 5_000_000)
                throw TestError()
            },
            onError: { _ in "error-message" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            .error(errorText: "error-message")
        ])
    }

    @Test("should suppress error when writing to closed stream")
    func ignoreWritesAfterClose() async throws {
        let writerStore = WriterStore()

        let stream = createUIMessageStream { writer in
            writer.write(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
            await writerStore.set(writer)
        }

        let chunks = try await collectStream(stream)
        #expect(chunks == [.textDelta(id: "1", delta: "1a", providerMetadata: nil)])

        if let writer = await writerStore.get() {
            writer.write(.textDelta(id: "1", delta: "1b", providerMetadata: nil))
        }
    }

    @Test("should support writing from delayed merged streams")
    func mergesAfterExecuteReturns() async throws {
        let first = ControllableChunkStream()
        let writerStore = WriterStore()
        let doneFlag = Flag()

        let stream = createUIMessageStream { writer in
            writer.merge(first.iterable)
            await writerStore.set(writer)
            await doneFlag.set(true)
        }

        while await doneFlag.get() == false {
            await Task.yield()
        }

        var iterator = stream.makeAsyncIterator()

        await first.yield(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
        let firstChunk = try await iterator.next()
        #expect(firstChunk == .textDelta(id: "1", delta: "1a", providerMetadata: nil))

        if let writer = await writerStore.get() {
            let second = ControllableChunkStream()
            writer.merge(second.iterable)
            await first.finish()
            await Task.yield()
            await second.yield(.textDelta(id: "2", delta: "2a", providerMetadata: nil))
            await second.finish()
        }

        let secondChunk = try await iterator.next()
        let end = try await iterator.next()
        #expect(secondChunk == .textDelta(id: "2", delta: "2a", providerMetadata: nil))
        #expect(end == nil)
    }

    @Test("should handle onFinish without original messages")
    func finishEventWithoutOriginalMessages() async throws {
        let events = UIMessageEventCollector<UIMessageStreamFinishEvent<UIMessage>>()

        let stream = createUIMessageStream(
            execute: { writer in
                writer.write(.textStart(id: "1", providerMetadata: nil))
                writer.write(.textDelta(id: "1", delta: "1a", providerMetadata: nil))
                writer.write(.textEnd(id: "1", providerMetadata: nil))
            },
            onFinish: { event in
                await events.append(event)
            },
            generateId: { "response-message-id" }
        )

        await consumeStream(stream: stream)

        let expectedMessage = UIMessage(
            id: "response-message-id",
            role: .assistant,
            metadata: nil,
            parts: [
                .text(TextUIPart(text: "1a", state: .done))
            ]
        )

        let recorded = await events.items()
        #expect(recorded == [
            UIMessageStreamFinishEvent(
                messages: [expectedMessage],
                isContinuation: false,
                isAborted: false,
                responseMessage: expectedMessage
            )
        ])
    }

    @Test("should handle onFinish with messages")
    func finishEventWithExistingMessages() async throws {
        let events = UIMessageEventCollector<UIMessageStreamFinishEvent<UIMessage>>()

        let originalMessages = [
            UIMessage(
                id: "0",
                role: .user,
                metadata: nil,
                parts: [.text(TextUIPart(text: "0a", state: .done))]
            ),
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [.text(TextUIPart(text: "1a", state: .done))]
            )
        ]

        let stream = createUIMessageStream(
            execute: { writer in
                writer.write(.textStart(id: "1", providerMetadata: nil))
                writer.write(.textDelta(id: "1", delta: "1b", providerMetadata: nil))
                writer.write(.textEnd(id: "1", providerMetadata: nil))
            },
            originalMessages: originalMessages,
            onFinish: { event in
                await events.append(event)
            }
        )

        await consumeStream(stream: stream)

        let expectedMessages = [
            originalMessages[0],
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .text(TextUIPart(text: "1a", state: .done)),
                    .text(TextUIPart(text: "1b", state: .done))
                ]
            )
        ]

        let recorded = await events.items()
        #expect(recorded == [
            UIMessageStreamFinishEvent(
                messages: expectedMessages,
                isContinuation: true,
                isAborted: false,
                responseMessage: expectedMessages[1]
            )
        ])
    }

    @Test("should inject a messageId into the stream when originalMessages are provided")
    func injectsMessageId() async throws {
        let stream = createUIMessageStream(
            execute: { writer in
                writer.write(.start(messageId: nil, messageMetadata: nil))
            },
            originalMessages: [
                UIMessage(
                    id: "0",
                    role: .user,
                    metadata: nil,
                    parts: [.text(TextUIPart(text: "0a", state: .done))]
                )
            ],
            generateId: { "response-message-id" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            .start(messageId: "response-message-id", messageMetadata: nil)
        ])
    }

    @Test("should keep existing messageId from start chunk when originalMessages are provided")
    func keepsExistingMessageId() async throws {
        let stream = createUIMessageStream(
            execute: { writer in
                writer.write(.start(messageId: "existing-message-id", messageMetadata: nil))
            },
            originalMessages: [
                UIMessage(
                    id: "0",
                    role: .user,
                    metadata: nil,
                    parts: [.text(TextUIPart(text: "0a", state: .done))]
                )
            ],
            generateId: { "response-message-id" }
        )

        let chunks = try await collectStream(stream)
        #expect(chunks == [
            .start(messageId: "existing-message-id", messageMetadata: nil)
        ])
    }
}

// MARK: - Helpers

private actor ControllableChunkStream {
    private var continuation: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation!

    let iterable: AsyncIterableStream<AnyUIMessageChunk>

    init() {
        var storedContinuation: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation!
        let stream = AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
            storedContinuation = continuation
        }
        self.continuation = storedContinuation
        self.iterable = createAsyncIterableStream(source: stream)
    }

    func yield(_ chunk: AnyUIMessageChunk) {
        continuation.yield(chunk)
    }

    func finish() {
        continuation.finish()
    }

    func fail(_ error: Error) {
        continuation.finish(throwing: error)
    }
}

private actor WriterStore {
    private var writer: DefaultUIMessageStreamWriter?

    func set(_ writer: DefaultUIMessageStreamWriter) {
        self.writer = writer
    }

    func get() -> DefaultUIMessageStreamWriter? {
        writer
    }
}

private actor Flag {
    private var value: Bool = false

    func set(_ newValue: Bool) {
        value = newValue
    }

    func get() -> Bool {
        value
    }
}

private actor UIMessageEventCollector<Element: Sendable> {
    private var storage: [Element] = []

    func append(_ element: Element) {
        storage.append(element)
    }

    func items() -> [Element] {
        storage
    }
}

private struct TestError: Error {}
