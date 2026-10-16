import Foundation
import AISDKProviderUtils

/**
 Handles the finalisation of a UI message stream, wiring `onFinish` callbacks and
 injecting message identifiers when necessary.

 Port of `@ai-sdk/ai/src/ui-message-stream/handle-ui-message-stream-finish.ts`.
 */
public func handleUIMessageStreamFinish<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    messageId: String?,
    originalMessages: [Message] = [],
    onStepFinish: UIMessageStreamOnStepFinishCallback<Message>? = nil,
    onFinish: UIMessageStreamOnFinishCallback<Message>? = nil,
    onError: @escaping ErrorHandler,
    onStepEnd: UIMessageStreamOnStepEndCallback<Message>? = nil,
    onEnd: UIMessageStreamOnEndCallback<Message>? = nil,
    getOutcome: (@Sendable () -> UIMessageStreamOutcome)? = nil
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    let onStepFinish = onStepEnd ?? onStepFinish
    let onFinish = onEnd ?? onFinish
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

    let idInjectedStream = AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
        let task = Task {
            do {
                for try await chunk in stream {
                    var adjustedChunk = chunk

                    if case .start(let chunkMessageId, let metadata) = chunk {
                        if chunkMessageId == nil, let messageIdForInjection {
                            adjustedChunk = .start(messageId: messageIdForInjection, messageMetadata: metadata)
                        }
                    }

                    if case .abort = chunk {
                        lifecycle.markAborted()
                    }

                    continuation.yield(adjustedChunk)
                }

                continuation.finish()
            } catch {
                if !Task.isCancelled { lifecycle.fail(error) }
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination { task.cancel() }
        }
    }

    if onFinish == nil && onStepFinish == nil {
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

    let finishInvoker: FinishInvoker<Message>? = onFinish.map { callback in
        FinishInvoker(
            onFinish: callback,
            state: state,
            originalMessages: originalMessages.map { $0.clone() },
            lastAssistantMessage: lastAssistantMessage,
            lifecycle: lifecycle
        )
    }

    let stepFinishInvoker: StepFinishInvoker<Message>? = onStepFinish.map { callback in
        StepFinishInvoker(
            onStepFinish: callback,
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
            // Mirror upstream: `onStepFinish` runs as the stream processes a `finish-step` chunk.
            if case .finishStep = chunk {
                await stepFinishInvoker?.call()
            }
        }
    )

    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await chunk in processedStream {
                    continuation.yield(chunk)
                }
                try await finishInvoker?.callIfNeeded(isCancelled: Task.isCancelled)
                continuation.finish()
            } catch {
                if !Task.isCancelled { lifecycle.fail(error) }
                do { try await finishInvoker?.callIfNeeded(isCancelled: Task.isCancelled) }
                catch { continuation.finish(throwing: error); return }
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            // Mirror upstream TransformStream semantics: cancellation should trigger
            // `onFinish` promptly. Cancelling the forward task ensures it hits the
            // `catch` path and invokes `finishInvoker` deterministically.
            task.cancel()
        }
    }
}

// MARK: - Finish Helpers

private actor FinishInvoker<Message: UIMessageConvertible> {
    private var called = false
    private let onFinish: UIMessageStreamOnFinishCallback<Message>
    private let state: StreamingUIMessageState<Message>
    private let originalMessages: [Message]
    private let lastAssistantMessage: Message?
    private let lifecycle: UIMessageStreamLifecycle

    init(
        onFinish: @escaping UIMessageStreamOnFinishCallback<Message>,
        state: StreamingUIMessageState<Message>,
        originalMessages: [Message],
        lastAssistantMessage: Message?,
        lifecycle: UIMessageStreamLifecycle
    ) {
        self.onFinish = onFinish
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
        try await onFinish(
            UIMessageStreamFinishEvent(
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
    private let onStepFinish: UIMessageStreamOnStepFinishCallback<Message>
    private let state: StreamingUIMessageState<Message>
    private let originalMessages: [Message]
    private let lastAssistantMessage: Message?
    private let onError: ErrorHandler

    init(
        onStepFinish: @escaping UIMessageStreamOnStepFinishCallback<Message>,
        state: StreamingUIMessageState<Message>,
        originalMessages: [Message],
        lastAssistantMessage: Message?,
        onError: @escaping ErrorHandler
    ) {
        self.onStepFinish = onStepFinish
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
            try await onStepFinish(
                UIMessageStreamStepFinishEvent(
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
