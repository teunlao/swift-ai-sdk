import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Creates a UI message stream by wiring an execution closure to a writer.

 Port of `@ai-sdk/ai/src/ui-message-stream/create-ui-message-stream.ts`.
 */
public func createUIMessageStream(
    execute: @escaping @Sendable (_ writer: DefaultUIMessageStreamWriter) async throws -> Void,
    onError mapError: @escaping @Sendable (Error) -> String = { AISDKProvider.getErrorMessage($0) },
    originalMessages: [UIMessage]? = nil,
    onFinish: UIMessageStreamOnFinishCallback<UIMessage>? = nil,
    generateId: @escaping IDGenerator = generateID
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    let state = UIMessageStreamState(errorMapper: mapError)
    let rawStream = state.makeStream()
    let writer = DefaultUIMessageStreamWriter(state: state, errorMapper: mapError)

    Task {
        do {
            try await execute(writer)
        } catch {
            state.emitError(error)
        }
        state.requestFinish()
    }

    let finishHandler: ErrorHandler = { error in
        _ = mapError(error)
    }

    let handledStream = handleUIMessageStreamFinish(
        stream: rawStream,
        messageId: generateId(),
        originalMessages: originalMessages ?? [],
        onFinish: onFinish,
        onError: finishHandler
    )

    return handledStream
}

// MARK: - Writer

/**
 Default writer implementation exposed to the execution closure.
 */
public struct DefaultUIMessageStreamWriter: UIMessageStreamWriter {
    public typealias Message = UIMessage

    private let state: UIMessageStreamState
    private let errorMapper: @Sendable (Error) -> String

    init(
        state: UIMessageStreamState,
        errorMapper: @escaping @Sendable (Error) -> String
    ) {
        self.state = state
        self.errorMapper = errorMapper
    }

    public func write(_ part: AnyUIMessageChunk) {
        state.enqueue(part)
    }

    public func merge(_ stream: AsyncIterableStream<AnyUIMessageChunk>) {
        state.merge(stream: stream, errorMapper: errorMapper)
    }

    public var onError: ErrorHandler? {
        { error in
            _ = errorMapper(error)
        }
    }
}

// MARK: - Internal State

final class UIMessageStreamState {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation?
    private var isFinished = false
    private var finishRequested = false
    private var activeMergeCount = 0
    private var mergeTasks: [UUID: Task<Void, Never>] = [:]
    private let errorMapper: @Sendable (Error) -> String

    init(errorMapper: @escaping @Sendable (Error) -> String) {
        self.errorMapper = errorMapper
    }

    func makeStream() -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
        AsyncThrowingStream { continuation in
            self.setContinuation(continuation)

            continuation.onTermination = { termination in
                self.handleTermination(termination)
            }
        }
    }

    func enqueue(_ chunk: AnyUIMessageChunk) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(chunk)
    }

    func emitError(_ error: Error) {
        enqueue(.error(errorText: errorMapper(error)))
    }

    func merge(
        stream: AsyncIterableStream<AnyUIMessageChunk>,
        errorMapper: @escaping @Sendable (Error) -> String
    ) {
        let identifier = UUID()
        let task = Task {
            defer {
                self.mergeFinished(id: identifier)
            }

            var iterator = stream.makeAsyncIterator()
            do {
                while let value = try await iterator.next() {
                    self.enqueue(value)
                }
            } catch is CancellationError {
                // Cancellation propagates silently.
            } catch {
                self.enqueue(.error(errorText: errorMapper(error)))
            }
        }

        if !registerMerge(task: task, id: identifier) {
            task.cancel()
        }
    }

    func requestFinish() {
        let shouldFinish: Bool
        lock.lock()
        finishRequested = true
        shouldFinish = !isFinished && activeMergeCount == 0
        lock.unlock()

        if shouldFinish {
            finish()
        }
    }

    // MARK: - Private helpers

    private func setContinuation(
        _ continuation: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation
    ) {
        lock.lock()
        guard self.continuation == nil else {
            lock.unlock()
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    private func registerMerge(task: Task<Void, Never>, id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if isFinished {
            return false
        }

        activeMergeCount += 1
        mergeTasks[id] = task
        return true
    }

    private func mergeFinished(id: UUID) {
        let shouldFinish: Bool

        lock.lock()
        mergeTasks[id] = nil
        if activeMergeCount > 0 {
            activeMergeCount -= 1
        }
        shouldFinish = finishRequested && !isFinished && activeMergeCount == 0
        lock.unlock()

        if shouldFinish {
            finish()
        }
    }

    private func handleTermination(
        _ termination: AsyncThrowingStream<AnyUIMessageChunk, Error>.Continuation.Termination
    ) {
        switch termination {
        case .finished:
            finish()
        case .cancelled:
            cancelMerges()
            finish()
        @unknown default:
            finish()
        }
    }

    private func finish() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.finish()
        cancelMerges()
    }

    private func cancelMerges() {
        lock.lock()
        let tasks = mergeTasks.values
        mergeTasks.removeAll()
        lock.unlock()
        for task in tasks {
            task.cancel()
        }
    }
}

extension UIMessageStreamState: @unchecked Sendable {}
