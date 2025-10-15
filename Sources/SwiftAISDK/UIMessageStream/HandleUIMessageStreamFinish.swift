import Foundation
import AISDKProviderUtils

/**
 Handles the finalisation of a UI message stream, wiring `onFinish` callbacks and
 injecting message identifiers when necessary.

 Port of `@ai-sdk/ai/src/ui-message-stream/handle-ui-message-stream-finish.ts`.
 */
public func handleUIMessageStreamFinish(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    messageId: String?,
    originalMessages: [UIMessage] = [],
    onFinish: UIMessageStreamOnFinishCallback<UIMessage>?,
    onError: @escaping ErrorHandler
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    var mutableMessageId = messageId

    var lastAssistantMessage: UIMessage? = originalMessages.last?.role == .assistant
        ? originalMessages.last?.clone()
        : nil

    if let assistantMessage = lastAssistantMessage {
        mutableMessageId = assistantMessage.id
    } else {
        lastAssistantMessage = nil
    }

    let abortFlag = AbortFlag()

    let messageIdForInjection = mutableMessageId

    let idInjectedStream = AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
        Task {
            do {
                for try await chunk in stream {
                    var adjustedChunk = chunk

                    if case .start(let chunkMessageId, let metadata) = chunk {
                        if chunkMessageId == nil, let messageIdForInjection {
                            adjustedChunk = .start(messageId: messageIdForInjection, messageMetadata: metadata)
                        }
                    }

                    if case .abort = chunk {
                        await abortFlag.markAborted()
                    }

                    continuation.yield(adjustedChunk)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    guard let onFinishElse = onFinish else {
        return idInjectedStream
    }

    let state = createStreamingUIMessageState(
        lastMessage: lastAssistantMessage,
        messageId: mutableMessageId ?? ""
    )

    let runUpdateMessageJob: @Sendable (_ job: @escaping StreamingUIMessageJob<UIMessage>) async throws -> Void = { job in
        try await job(StreamingUIMessageJobContext(state: state, write: {}))
    }

    let processedStream = processUIMessageStream(
        stream: idInjectedStream,
        runUpdateMessageJob: runUpdateMessageJob,
        onError: onError
    )

    let finishInvoker = FinishInvoker(
        onFinish: onFinishElse,
        state: state,
        originalMessages: originalMessages.map { $0.clone() },
        lastAssistantMessage: lastAssistantMessage,
        isAborted: { await abortFlag.isAborted() }
    )

    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await chunk in processedStream {
                    continuation.yield(chunk)
                }
                await finishInvoker.callIfNeeded()
                continuation.finish()
            } catch {
                await finishInvoker.callIfNeeded()
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { termination in
            if case .cancelled = termination {
                Task {
                    await finishInvoker.callIfNeeded()
                }
            }
        }
    }
}

// MARK: - Finish Helpers

private actor FinishInvoker {
    private var called = false
    private let onFinish: UIMessageStreamOnFinishCallback<UIMessage>
    private let state: StreamingUIMessageState<UIMessage>
    private let originalMessages: [UIMessage]
    private let lastAssistantMessage: UIMessage?
    private let isAborted: @Sendable () async -> Bool

    init(
        onFinish: @escaping UIMessageStreamOnFinishCallback<UIMessage>,
        state: StreamingUIMessageState<UIMessage>,
        originalMessages: [UIMessage],
        lastAssistantMessage: UIMessage?,
        isAborted: @escaping @Sendable () async -> Bool
    ) {
        self.onFinish = onFinish
        self.state = state
        self.originalMessages = originalMessages
        self.lastAssistantMessage = lastAssistantMessage
        self.isAborted = isAborted
    }

    func callIfNeeded() async {
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

        await onFinish(
            UIMessageStreamFinishEvent(
                messages: messages,
                isContinuation: isContinuation,
                isAborted: await isAborted(),
                responseMessage: responseMessage
            )
        )
    }
}

private actor AbortFlag {
    private var value = false

    func markAborted() {
        value = true
    }

    func isAborted() -> Bool {
        value
    }
}
