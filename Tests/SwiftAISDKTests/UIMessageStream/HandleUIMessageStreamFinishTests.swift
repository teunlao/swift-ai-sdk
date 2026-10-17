import Foundation
import Testing
@testable import SwiftAISDK

private final class ThreadSafeArray<Element>: @unchecked Sendable {
    private var storage: [Element] = []
    private let lock = NSLock()

    func append(_ value: Element) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    func values() -> [Element] {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot
    }
}

@Suite("handleUIMessageStreamFinish")
struct HandleUIMessageStreamFinishTests {
    private func textChunk(id: String, delta: String) -> AnyUIMessageChunk {
        .textDelta(id: id, delta: delta, providerMetadata: nil)
    }

    private func makeMessage(
        id: String,
        role: UIMessageRole,
        parts: [UIMessagePart]
    ) -> UIMessage {
        UIMessage(id: id, role: role, parts: parts)
    }

    @Test("passes through chunks when onFinish is nil")
    func passThroughWithoutOnFinish() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-123", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Hello"),
            textChunk(id: "text-1", delta: " World"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let capturedErrors = ThreadSafeArray<String>()

        let stream = makeAsyncStream(from: inputChunks)
        let resultStream = handleUIMessageStreamFinish(
            stream: stream,
            messageId: "msg-123",
            originalMessages: [UIMessage](),
            onEnd: nil,
            onError: { capturedErrors.append($0.localizedDescription) }
        )

        let result = try await collectStream(resultStream)

        #expect(result == inputChunks)
        #expect(capturedErrors.values().isEmpty)
    }

    @Test("injects messageId when start chunk lacks one")
    func injectsMessageIdWhenMissing() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: nil, messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Test"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let stream = makeAsyncStream(from: inputChunks)
        let resultStream = handleUIMessageStreamFinish(
            stream: stream,
            messageId: "injected-123",
            originalMessages: [UIMessage](),
            onEnd: nil,
            onError: { _ in }
        )

        let result = try await collectStream(resultStream)

        guard case .start(let messageId, _) = result.first else {
            Issue.record("Expected first chunk to be a start chunk")
            return
        }

        #expect(messageId == "injected-123")
        #expect(Array(result.dropFirst()) == Array(inputChunks.dropFirst()))
    }

    @Test("invokes onFinish with processed stream")
    func invokesOnFinish() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-456", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Hello"),
            textChunk(id: "text-1", delta: " World"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let originalMessages = [
            makeMessage(
                id: "user-msg-1",
                role: .user,
                parts: [.text(TextUIPart(text: "Hello", state: .done))]
            )
        ]

        let finishEvents = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let resultStream = handleUIMessageStreamFinish(
            stream: stream,
            messageId: "msg-456",
            originalMessages: originalMessages,
            onEnd: { event in finishEvents.append(event) },
            onError: { _ in }
        )

        let result = try await collectStream(resultStream)
        #expect(result == inputChunks)
        let events = finishEvents.values()
        #expect(events.count == 1)

        guard let event = events.first else { return }
        #expect(event.isContinuation == false)
        #expect(event.isAborted == false)
        #expect(event.finishReason == nil)
        #expect(event.messages.count == 2)
        #expect(event.messages.first == originalMessages.first)
        #expect(event.responseMessage.id == "msg-456")
        #expect(event.responseMessage.role == .assistant)
    }

    @Test("handles empty original messages")
    func handlesEmptyOriginalMessages() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-789", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Response"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let finishEvents = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-789",
                originalMessages: [UIMessage](),
                onEnd: { event in finishEvents.append(event) },
                onError: { _ in }
            )
        )

        guard let event = finishEvents.values().first else {
            Issue.record("Expected finish event")
            return
        }

        #expect(event.isContinuation == false)
        #expect(event.messages.count == 1)
        #expect(event.messages[0] == event.responseMessage)
    }

    @Test("continuation when last message assistant")
    func continuationScenario() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "assistant-msg-1", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: " continued"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let originalMessages = [
            makeMessage(
                id: "user-msg-1",
                role: .user,
                parts: [.text(TextUIPart(text: "Continue this", state: .done))]
            ),
            makeMessage(
                id: "assistant-msg-1",
                role: .assistant,
                parts: [.text(TextUIPart(text: "This is", state: .done))]
            )
        ]

        let events = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-ignored",
                originalMessages: originalMessages,
                onEnd: { events.append($0) },
                onError: { _ in }
            )
        )

        guard let event = events.values().first else { return }

        #expect(event.isContinuation == true)
        #expect(event.responseMessage.id == "assistant-msg-1")
        #expect(event.messages.count == 2)
        #expect(event.messages[0] == originalMessages[0])
    }

    @Test("does not treat user message as continuation")
    func noContinuationForUserMessage() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-001", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "New response"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let originalMessages = [
            makeMessage(
                id: "user-msg-1",
                role: .user,
                parts: [.text(TextUIPart(text: "Question", state: .done))]
            ),
            makeMessage(
                id: "user-msg-2",
                role: .user,
                parts: [.text(TextUIPart(text: "Another question", state: .done))]
            )
        ]

        let events = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-001",
                originalMessages: originalMessages,
                onEnd: { events.append($0) },
                onError: { _ in }
            )
        )

        guard let event = events.values().first else { return }

        #expect(event.isContinuation == false)
        #expect(event.messages.count == 3)
        #expect(event.responseMessage.id == "msg-001")
    }

    @Test("marks abort when abort chunk encountered")
    func abortSetsFlag() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-abort-1", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Starting text"),
            .abort(reason: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let stream = makeAsyncStream(from: inputChunks)
        let events = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-abort-1",
                originalMessages: [
                    makeMessage(
                        id: "user-msg-1",
                        role: .user,
                        parts: [.text(TextUIPart(text: "Test request", state: .done))]
                    )
                ],
                onEnd: { events.append($0) },
                onError: { _ in }
            )
        )

        #expect(result == inputChunks)
        guard let event = events.values().first else { return }
        #expect(event.isAborted == true)
        #expect(event.isContinuation == false)
        #expect(event.messages.count == 2)
    }

    @Test("abort flag false when no abort chunk")
    func abortFlagFalse() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-normal", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Complete text"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let events = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-normal",
                originalMessages: [
                    makeMessage(
                        id: "user-msg-1",
                        role: .user,
                        parts: [.text(TextUIPart(text: "Test request", state: .done))]
                    )
                ],
                onEnd: { events.append($0) },
                onError: { _ in }
            )
        )

        guard let event = events.values().first else { return }
        #expect(event.isAborted == false)
        #expect(event.isContinuation == false)
    }

    @Test("multiple abort chunks still set flag")
    func multipleAbortChunks() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-multiple-abort", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            .abort(reason: nil),
            textChunk(id: "text-1", delta: "Some text"),
            .abort(reason: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let events = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-multiple-abort",
                originalMessages: [UIMessage](),
                onEnd: { events.append($0) },
                onError: { _ in }
            )
        )

        #expect(result == inputChunks)
        guard let event = events.values().first else { return }
        #expect(event.isAborted == true)
    }

    @Test("passes abort chunks through when callbacks are omitted")
    func abortPassThroughWithoutCallbacks() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-abort-passthrough", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Text before abort"),
            .abort(reason: nil),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let capturedErrors = ThreadSafeArray<String>()

        let stream = makeAsyncStream(from: inputChunks)
        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-abort-passthrough",
                originalMessages: [UIMessage](),
                onEnd: nil,
                onError: { capturedErrors.append($0.localizedDescription) }
            )
        )

        #expect(result == inputChunks)
        #expect(capturedErrors.values().isEmpty)
    }

    @Test("triggers onEnd when the reader is cancelled while waiting")
    func readerCancellationTriggersEnd() async throws {
        let source = AsyncThrowingStream<AnyUIMessageChunk, Error>.makeStream()
        source.continuation.yield(.start(messageId: "msg-1", messageMetadata: nil))
        source.continuation.yield(.textStart(id: "text-1", providerMetadata: nil))
        source.continuation.yield(textChunk(id: "text-1", delta: "Hello"))
        defer { source.continuation.finish() }

        let events = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()
        let read = ThreadSafeArray<AnyUIMessageChunk>()
        let resultStream = handleUIMessageStreamFinish(
            stream: source.stream,
            messageId: "msg-1",
            originalMessages: [UIMessage](),
            onEnd: { event in events.append(event) },
            onError: { _ in }
        )

        let task = Task {
            for try await chunk in resultStream { read.append(chunk) }
        }
        while read.values().count < 3 { await Task.yield() }
        task.cancel()
        _ = await task.result
        // A cancellation between reads ends the stream from its release, off the consumer task.
        for _ in 0..<1_000 where events.values().isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }

        let event = try #require(events.values().first)
        #expect(event.isCancelled == true)
        #expect(event.isAborted == false)
        #expect(event.responseMessage.id == "msg-1")
    }

    @Test("reads the source only as fast as the consumer reads")
    func readsOnDemand() async throws {
        let reads = ThreadSafeArray<Int>()
        let parts: [TextStreamPart] = [.start, .textStart(id: "t", providerMetadata: nil)]
            + Array(repeating: .textDelta(id: "t", text: "x", providerMetadata: nil), count: 1_000)
        let source = AsyncThrowingStream<TextStreamPart, Error>(unfolding: {
            let index = reads.values().count
            guard index < parts.count else { return nil }
            reads.append(index)
            return parts[index]
        })
        let stream = toUIMessageStream(stream: source, options: UIMessageStreamOptions<UIMessage>(onEnd: { _ in }))

        var iterator = stream.makeAsyncIterator()
        for _ in 0..<3 { _ = try await iterator.next() }
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(reads.values().count == 3)
    }

    @Test("passes abort reason through")
    func abortReasonPassThrough() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-abort-reason", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Starting text"),
            .abort(reason: "manual abort"),
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let events = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-abort-reason",
                originalMessages: [UIMessage](),
                onEnd: { events.append($0) },
                onError: { _ in }
            )
        )

        #expect(result == inputChunks)
        guard let event = events.values().first else { return }
        #expect(event.isAborted == true)
    }

    @Test("captures finishReason from finish chunk")
    func finishReasonCaptured() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-finish-reason", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Done"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finish(finishReason: .stop, messageMetadata: nil)
        ]

        let events = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-finish-reason",
                originalMessages: [UIMessage](),
                onEnd: { events.append($0) },
                onError: { _ in }
            )
        )

        #expect(result == inputChunks)
        guard let event = events.values().first else { return }
        #expect(event.finishReason == .stop)
    }

    // MARK: - onStepFinish

    @Test("calls onStepFinish when finish-step chunk is encountered")
    func stepFinishCalled() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-step-1", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Step 1 text"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let originalMessages = [
            makeMessage(
                id: "user-msg-1",
                role: .user,
                parts: [.text(TextUIPart(text: "Hello", state: .done))]
            )
        ]

        let stepEvents = ThreadSafeArray<UIMessageStreamStepEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-step-1",
                originalMessages: originalMessages,
                onStepEnd: { stepEvents.append($0) },
                onEnd: nil,
                onError: { _ in }
            )
        )

        #expect(result == inputChunks)

        let captured = stepEvents.values()
        #expect(captured.count == 1)
        guard let event = captured.first else { return }
        #expect(event.isContinuation == false)
        #expect(event.responseMessage.id == "msg-step-1")
        #expect(event.responseMessage.role == .assistant)
        #expect(event.messages.count == 2)
        #expect(event.messages[0] == originalMessages[0])
    }

    @Test("calls onStepFinish multiple times for multiple steps")
    func stepFinishMultipleSteps() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-multi-step", messageMetadata: nil),
            // Step 1
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Step 1"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            // Step 2
            .startStep,
            .textStart(id: "text-2", providerMetadata: nil),
            textChunk(id: "text-2", delta: "Step 2"),
            .textEnd(id: "text-2", providerMetadata: nil),
            .finishStep,
            // Step 3
            .startStep,
            .textStart(id: "text-3", providerMetadata: nil),
            textChunk(id: "text-3", delta: "Step 3"),
            .textEnd(id: "text-3", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let stepEvents = ThreadSafeArray<UIMessageStreamStepEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-multi-step",
                originalMessages: [UIMessage](),
                onStepEnd: { stepEvents.append($0) },
                onEnd: nil,
                onError: { _ in }
            )
        )

        let captured = stepEvents.values()
        #expect(captured.count == 3)
        #expect(captured[0].responseMessage.parts.count == 1)
        #expect(captured[1].responseMessage.parts.count == 3)
        #expect(captured[2].responseMessage.parts.count == 5)
    }

    @Test("calls both onStepFinish and onFinish when both are provided")
    func stepFinishAndFinishBothCalled() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-both", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Hello"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let stepEvents = ThreadSafeArray<UIMessageStreamStepEndEvent<UIMessage>>()
        let finishEvents = ThreadSafeArray<UIMessageStreamEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-both",
                originalMessages: [UIMessage](),
                onStepEnd: { stepEvents.append($0) },
                onEnd: { finishEvents.append($0) },
                onError: { _ in }
            )
        )

        #expect(stepEvents.values().count == 1)
        #expect(finishEvents.values().count == 1)
    }

    @Test("onStepFinish errors are reported via onError and streaming continues")
    func stepFinishErrorHandling() async throws {
        struct StepError: Error {}

        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-error", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Step 1"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .startStep,
            .textStart(id: "text-2", providerMetadata: nil),
            textChunk(id: "text-2", delta: "Step 2"),
            .textEnd(id: "text-2", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let onErrorCalls = ThreadSafeArray<String>()
        let stepEvents = ThreadSafeArray<UIMessageStreamStepEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-error",
                originalMessages: [UIMessage](),
                onStepEnd: { event in
                    stepEvents.append(event)
                    throw StepError()
                },
                onEnd: nil,
                onError: { onErrorCalls.append($0.localizedDescription) }
            )
        )

        #expect(result == inputChunks)
        #expect(stepEvents.values().count == 2)
        #expect(onErrorCalls.values().count == 2)
    }

    @Test("continuation scenario works with onStepFinish")
    func stepFinishContinuationScenario() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "assistant-msg-1", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: " continued"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let originalMessages = [
            makeMessage(
                id: "user-msg-1",
                role: .user,
                parts: [.text(TextUIPart(text: "Continue this", state: .done))]
            ),
            makeMessage(
                id: "assistant-msg-1",
                role: .assistant,
                parts: [.text(TextUIPart(text: "This is", state: .done))]
            )
        ]

        let stepEvents = ThreadSafeArray<UIMessageStreamStepEndEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-ignored",
                originalMessages: originalMessages,
                onStepEnd: { stepEvents.append($0) },
                onEnd: nil,
                onError: { _ in }
            )
        )

        let captured = stepEvents.values()
        #expect(captured.count == 1)
        guard let event = captured.first else { return }
        #expect(event.isContinuation == true)
        #expect(event.responseMessage.id == "assistant-msg-1")
        #expect(event.messages.count == 2)
    }

    @Test("onStepFinish receives a cloned message (mutations do not leak into onFinish)")
    func stepFinishCloneIsolation() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-clone", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Hello"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let finishEvents = ThreadSafeArray<UIMessageStreamEndEvent<RefUIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-clone",
                originalMessages: [RefUIMessage](),
                onStepEnd: { event in
                    // Mutate the message we received in onStepFinish
                    event.responseMessage.parts.append(
                        .text(TextUIPart(text: "MUTATION!", state: .done))
                    )
                },
                onEnd: { finishEvents.append($0) },
                onError: { _ in }
            )
        )

        guard let finishEvent = finishEvents.values().first else {
            Issue.record("Expected finish event")
            return
        }

        // onFinish should not observe the onStepFinish mutation.
        #expect(finishEvent.responseMessage.parts.count == 1)
    }

    @Test("finish-step chunks are passed through when no callbacks are provided")
    func finishStepPassThroughWithoutCallbacks() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-passthrough", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Test"),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        let capturedErrors = ThreadSafeArray<String>()

        let stream = makeAsyncStream(from: inputChunks)
        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-passthrough",
                originalMessages: [UIMessage](),
                onStepEnd: nil,
                onEnd: nil,
                onError: { capturedErrors.append($0.localizedDescription) }
            )
        )

        #expect(result == inputChunks)
        #expect(capturedErrors.values().isEmpty)
    }
}

// MARK: - Reference-typed UIMessageConvertible for clone isolation tests

private final class RefUIMessage: UIMessageConvertible, @unchecked Sendable {
    var id: String
    var role: UIMessageRole
    var metadata: JSONValue?
    var parts: [UIMessagePart]

    init(id: String, role: UIMessageRole, metadata: JSONValue?, parts: [UIMessagePart]) {
        self.id = id
        self.role = role
        self.metadata = metadata
        self.parts = parts
    }

    func clone() -> RefUIMessage {
        RefUIMessage(id: id, role: role, metadata: metadata, parts: parts)
    }

    static func == (lhs: RefUIMessage, rhs: RefUIMessage) -> Bool {
        lhs.id == rhs.id &&
            lhs.role == rhs.role &&
            lhs.metadata == rhs.metadata &&
            lhs.parts == rhs.parts
    }
}
