import Foundation
import AISDKProviderUtils

/**
 Handles the finalisation of a UI message stream, wiring `onEnd` callbacks and
 injecting message identifiers when necessary.

 Port of `@ai-sdk/ai/src/ui-message-stream/handle-ui-message-stream-finish.ts`.
 */
public func handleUIMessageStreamFinish<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    messageId: String?,
    originalMessages: [Message] = [],
    onStepEnd: UIMessageStreamOnStepEndCallback<Message>? = nil,
    onEnd: UIMessageStreamOnEndCallback<Message>? = nil,
    onError: @escaping ErrorHandler,
    getOutcome: (@Sendable () -> UIMessageStreamOutcome)? = nil
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    let lifecycle = UIMessageStreamLifecycle(getOutcome: getOutcome)
    var mutableMessageId = messageId

    var lastAssistantMessage: Message? = originalMessages.last?.role == .assistant
        ? originalMessages.last?.clone()
        : nil

    if let assistantMessage = lastAssistantMessage {
        mutableMessageId = assistantMessage.id
    } else {
        lastAssistantMessage = nil
    }

    let messageIdForInjection = mutableMessageId

    // Every stage is pull-based, so the source is read only as fast as the consumer reads.
    let idInjectedStream = pullTransform(stream) { chunk -> [AnyUIMessageChunk] in
        if case .abort = chunk {
            lifecycle.markAborted()
        }
        if case .start(nil, let metadata) = chunk, let messageIdForInjection {
            return [.start(messageId: messageIdForInjection, messageMetadata: metadata)]
        }
        return [chunk]
    }

    if onEnd == nil && onStepEnd == nil {
        return idInjectedStream
    }

    let state = createStreamingUIMessageState(
        lastMessage: lastAssistantMessage,
        messageId: mutableMessageId ?? ""
    )

    let runUpdateMessageJob: @Sendable (_ job: @escaping StreamingUIMessageJob<Message>) async throws -> Void = { job in
        do { try await job(StreamingUIMessageJobContext(state: state, write: {})) }
        catch { lifecycle.fail(error); throw error }
    }

    let finishInvoker: FinishInvoker<Message>? = onEnd.map { callback in
        FinishInvoker(
            onEnd: callback,
            state: state,
            originalMessages: originalMessages.map { $0.clone() },
            lastAssistantMessage: lastAssistantMessage,
            lifecycle: lifecycle
        )
    }

    let stepFinishInvoker: StepFinishInvoker<Message>? = onStepEnd.map { callback in
        StepFinishInvoker(
            onStepEnd: callback,
            state: state,
            originalMessages: originalMessages.map { $0.clone() },
            lastAssistantMessage: lastAssistantMessage,
            onError: onError
        )
    }

    let processedStream = processUIMessageStreamInternal(
        stream: idInjectedStream,
        runUpdateMessageJob: runUpdateMessageJob,
        onError: onError,
        onChunk: { chunk in
            // Mirror upstream: `onStepEnd` runs as the stream processes a `finish-step` chunk.
            if case .finishStep = chunk {
                await stepFinishInvoker?.call()
            }
        }
    )

    let ending = UIMessageStreamEnding(
        stream: processedStream, finishInvoker: finishInvoker, lifecycle: lifecycle
    )
    return AsyncThrowingStream(unfolding: { try await ending.next() })
}

/**
 The last stage of a finish-handled stream: it calls `onEnd` once when the source ends,
 fails, or the consumer cancels or abandons the stream before the end.
 */
private final class UIMessageStreamEnding<Message: UIMessageConvertible>: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<AnyUIMessageChunk, Error>.AsyncIterator
    private let finishInvoker: FinishInvoker<Message>?
    private let lifecycle: UIMessageStreamLifecycle
    private var ended = false

    init(
        stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
        finishInvoker: FinishInvoker<Message>?,
        lifecycle: UIMessageStreamLifecycle
    ) {
        self.iterator = stream.makeAsyncIterator()
        self.finishInvoker = finishInvoker
        self.lifecycle = lifecycle
    }

    func next() async throws -> AnyUIMessageChunk? {
        if ended { return nil }
        do {
            if let chunk = try await iterator.next() { return chunk }
            ended = true
            try await finishInvoker?.callIfNeeded(isCancelled: Task.isCancelled)
            return nil
        } catch {
            if ended { throw error }
            ended = true
            if !Task.isCancelled { lifecycle.fail(error) }
            try await finishInvoker?.callIfNeeded(isCancelled: Task.isCancelled)
            throw error
        }
    }

    // The unfolding stream releases this stage when its consumer is cancelled or the
    // stream is dropped; an end that has not happened yet is a consumer cancellation.
    deinit {
        guard !ended, let finishInvoker else { return }
        Task { try? await finishInvoker.callIfNeeded(isCancelled: true) }
    }
}

// MARK: - Finish Helpers

private actor FinishInvoker<Message: UIMessageConvertible> {
    private var called = false
    private let onEnd: UIMessageStreamOnEndCallback<Message>
    private let state: StreamingUIMessageState<Message>
    private let originalMessages: [Message]
    private let lastAssistantMessage: Message?
    private let lifecycle: UIMessageStreamLifecycle

    init(
        onEnd: @escaping UIMessageStreamOnEndCallback<Message>,
        state: StreamingUIMessageState<Message>,
        originalMessages: [Message],
        lastAssistantMessage: Message?,
        lifecycle: UIMessageStreamLifecycle
    ) {
        self.onEnd = onEnd
        self.state = state
        self.originalMessages = originalMessages
        self.lastAssistantMessage = lastAssistantMessage
        self.lifecycle = lifecycle
    }

    func callIfNeeded(isCancelled: Bool) async throws {
        guard !called else { return }
        called = true

        let responseMessage = state.message.clone()
        let isContinuation = responseMessage.id == lastAssistantMessage?.id

        var messages = originalMessages.map { $0.clone() }
        if isContinuation {
            if !messages.isEmpty {
                messages[messages.count - 1] = responseMessage
            } else {
                messages = [responseMessage]
            }
        } else {
            messages.append(responseMessage)
        }

        let ending = lifecycle.ending(isCancelled: isCancelled)
        try await onEnd(
            UIMessageStreamEndEvent(
                messages: messages,
                isContinuation: isContinuation,
                isAborted: ending.isAborted,
                responseMessage: responseMessage,
                finishReason: state.finishReason,
                isCancelled: ending.isCancelled,
                outcome: ending.outcome
            )
        )
    }
}

private actor StepFinishInvoker<Message: UIMessageConvertible> {
    private let onStepEnd: UIMessageStreamOnStepEndCallback<Message>
    private let state: StreamingUIMessageState<Message>
    private let originalMessages: [Message]
    private let lastAssistantMessage: Message?
    private let onError: ErrorHandler

    init(
        onStepEnd: @escaping UIMessageStreamOnStepEndCallback<Message>,
        state: StreamingUIMessageState<Message>,
        originalMessages: [Message],
        lastAssistantMessage: Message?,
        onError: @escaping ErrorHandler
    ) {
        self.onStepEnd = onStepEnd
        self.state = state
        self.originalMessages = originalMessages
        self.lastAssistantMessage = lastAssistantMessage
        self.onError = onError
    }

    func call() async {
        let responseMessage = state.message.clone()
        let isContinuation = responseMessage.id == lastAssistantMessage?.id

        var messages = originalMessages.map { $0.clone() }
        if isContinuation {
            if !messages.isEmpty {
                messages[messages.count - 1] = responseMessage
            } else {
                messages = [responseMessage]
            }
        } else {
            messages.append(responseMessage)
        }

        do {
            try await onStepEnd(
                UIMessageStreamStepEndEvent(
                    messages: messages,
                    isContinuation: isContinuation,
                    responseMessage: responseMessage
                )
            )
        } catch {
            onError(error)
        }
    }
}

private final class UIMessageStreamLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var aborted = false
    private var processingError: Error?
    private let getOutcome: (@Sendable () -> UIMessageStreamOutcome)?

    init(getOutcome: (@Sendable () -> UIMessageStreamOutcome)?) { self.getOutcome = getOutcome }

    func markAborted() { lock.lock(); aborted = true; lock.unlock() }
    func fail(_ error: Error) { lock.lock(); processingError = error; lock.unlock() }

    func ending(isCancelled: Bool) -> (isAborted: Bool, isCancelled: Bool?, outcome: UIMessageStreamOutcome) {
        lock.lock()
        let aborted = self.aborted
        let error = processingError
        lock.unlock()
        var outcome = getOutcome?() ?? .unknown
        if let error { outcome = .failed(error: error) }
        else if outcome.status == "unknown", aborted { outcome = .aborted }
        return (aborted || outcome.status == "aborted",
                isCancelled && outcome.status == "unknown" ? true : nil, outcome)
    }
}
