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
            .finish(messageMetadata: nil)
        ]

        let capturedErrors = ThreadSafeArray<String>()

        let stream = makeAsyncStream(from: inputChunks)
        let resultStream = handleUIMessageStreamFinish(
            stream: stream,
            messageId: "msg-123",
            originalMessages: [UIMessage](),
            onFinish: nil,
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
            .finish(messageMetadata: nil)
        ]

        let stream = makeAsyncStream(from: inputChunks)
        let resultStream = handleUIMessageStreamFinish(
            stream: stream,
            messageId: "injected-123",
            originalMessages: [UIMessage](),
            onFinish: nil,
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
            .finish(messageMetadata: nil)
        ]

        let originalMessages = [
            makeMessage(
                id: "user-msg-1",
                role: .user,
                parts: [.text(TextUIPart(text: "Hello", state: .done))]
            )
        ]

        let finishEvents = ThreadSafeArray<UIMessageStreamFinishEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let resultStream = handleUIMessageStreamFinish(
            stream: stream,
            messageId: "msg-456",
            originalMessages: originalMessages,
            onFinish: { event in finishEvents.append(event) },
            onError: { _ in }
        )

        let result = try await collectStream(resultStream)
        #expect(result == inputChunks)
        let events = finishEvents.values()
        #expect(events.count == 1)

        guard let event = events.first else { return }
        #expect(event.isContinuation == false)
        #expect(event.isAborted == false)
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
            .finish(messageMetadata: nil)
        ]

        let finishEvents = ThreadSafeArray<UIMessageStreamFinishEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-789",
                originalMessages: [UIMessage](),
                onFinish: { event in finishEvents.append(event) },
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
            .finish(messageMetadata: nil)
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

        let events = ThreadSafeArray<UIMessageStreamFinishEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-ignored",
                originalMessages: originalMessages,
                onFinish: { events.append($0) },
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
            .finish(messageMetadata: nil)
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

        let events = ThreadSafeArray<UIMessageStreamFinishEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        _ = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-001",
                originalMessages: originalMessages,
                onFinish: { events.append($0) },
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
            .abort,
            .finish(messageMetadata: nil)
        ]

        let stream = makeAsyncStream(from: inputChunks)
        let events = ThreadSafeArray<UIMessageStreamFinishEvent<UIMessage>>()

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
                onFinish: { events.append($0) },
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
            .finish(messageMetadata: nil)
        ]

        let events = ThreadSafeArray<UIMessageStreamFinishEvent<UIMessage>>()

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
                onFinish: { events.append($0) },
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
            .abort,
            textChunk(id: "text-1", delta: "Some text"),
            .abort,
            .finish(messageMetadata: nil)
        ]

        let events = ThreadSafeArray<UIMessageStreamFinishEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let result = try await collectStream(
            handleUIMessageStreamFinish(
                stream: stream,
                messageId: "msg-multiple-abort",
                originalMessages: [UIMessage](),
                onFinish: { events.append($0) },
                onError: { _ in }
            )
        )

        #expect(result == inputChunks)
        guard let event = events.values().first else { return }
        #expect(event.isAborted == true)
    }

    @Test("triggers onFinish when reader is cancelled")
    func readerCancellationTriggersFinish() async throws {
        let inputChunks: [AnyUIMessageChunk] = [
            .start(messageId: "msg-1", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            textChunk(id: "text-1", delta: "Hello")
        ]

        let events = ThreadSafeArray<UIMessageStreamFinishEvent<UIMessage>>()

        let stream = makeAsyncStream(from: inputChunks)
        let resultStream = handleUIMessageStreamFinish(
            stream: stream,
            messageId: "msg-1",
            originalMessages: [UIMessage](),
            onFinish: { event in events.append(event) },
            onError: { _ in }
        )

        let task = Task {
            var iterator = resultStream.makeAsyncIterator()
            _ = try await iterator.next()
            try await Task.sleep(nanoseconds: 50_000)
        }

        try await Task.sleep(nanoseconds: 100_000)
        task.cancel()
        _ = await task.result

        // Wait for onFinish to be invoked
        for _ in 0..<10 where events.values().isEmpty {
            await Task.yield()
        }

        guard let event = events.values().first else {
            Issue.record("Expected finish event after cancellation")
            return
        }

        #expect(event.isAborted == false)
        #expect(event.responseMessage.id == "msg-1")
    }
}
