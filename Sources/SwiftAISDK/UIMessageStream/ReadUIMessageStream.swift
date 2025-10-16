import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Reads a UI message stream and yields intermediate `Message` snapshots.

 Port of `@ai-sdk/ai/src/ui-message-stream/read-ui-message-stream.ts`.
 */
public func readUIMessageStream<Message: UIMessageConvertible>(
    message: Message? = nil,
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    terminateOnError: Bool = false,
    onError: (@Sendable (Error) -> Void)? = nil
) -> AsyncIterableStream<Message> {
    let state = createStreamingUIMessageState(
        lastMessage: message,
        messageId: message?.id ?? ""
    )

    let output = AsyncThrowingStream<Message, Error> { continuation in
        let controller = ReadUIMessageStreamController(
            state: state,
            continuation: continuation,
            terminateOnError: terminateOnError,
            onError: onError
        )
        controller.start(stream: stream)
    }

    return createAsyncIterableStream(source: output)
}

// MARK: - Controller

private final class ReadUIMessageStreamController<Message: UIMessageConvertible>: @unchecked Sendable {
    private let state: StreamingUIMessageState<Message>
    private let terminateOnError: Bool
    private let errorHandler: (@Sendable (Error) -> Void)?
    private let lock = NSLock()

    private var continuation: AsyncThrowingStream<Message, Error>.Continuation?
    private var hasErrored = false
    private var consumeTask: Task<Void, Never>?

    init(
        state: StreamingUIMessageState<Message>,
        continuation: AsyncThrowingStream<Message, Error>.Continuation,
        terminateOnError: Bool,
        onError: (@Sendable (Error) -> Void)?
    ) {
        self.state = state
        self.continuation = continuation
        self.terminateOnError = terminateOnError
        self.errorHandler = onError
    }

    func start(stream: AsyncThrowingStream<AnyUIMessageChunk, Error>) {
        let processedStream = processUIMessageStream(
            stream: stream,
            runUpdateMessageJob: { job in
                try await job(
                    StreamingUIMessageJobContext(
                        state: self.state,
                        write: { self.emitCurrentMessage() }
                    )
                )
            },
            onError: { error in
                self.handleError(error)
            }
        )

        consumeTask = Task {
            await consumeStream(
                stream: processedStream,
                onError: { error in
                    self.handleError(error)
                }
            )
            self.finishIfNeeded()
        }

        continuation?.onTermination = { _ in
            self.cancel()
        }
    }

    private func emitCurrentMessage() {
        lock.lock()
        guard let continuation, !hasErrored else {
            lock.unlock()
            return
        }
        let snapshot = state.message.clone()
        lock.unlock()

        continuation.yield(snapshot)
    }

    private func handleError(_ error: Error) {
        errorHandler?(error)

        guard terminateOnError else {
            return
        }

        lock.lock()
        guard !hasErrored else {
            lock.unlock()
            return
        }
        hasErrored = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.finish(throwing: error)
        cancel()
    }

    private func finishIfNeeded() {
        lock.lock()
        guard !hasErrored else {
            lock.unlock()
            return
        }
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.finish()
    }

    private func cancel() {
        lock.lock()
        let task = consumeTask
        consumeTask = nil
        continuation = nil
        lock.unlock()

        task?.cancel()
    }
}
