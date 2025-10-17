import Foundation

/**
 Fan-out utility that mirrors piping a `ReadableStream` to multiple consumers in the upstream SDK.

 Each subscriber obtains an `AsyncThrowingStream` that replays buffered elements and receives all
 subsequent ones. Finishing the broadcaster completes all registered streams; finishing with an error
 forwards the error to every subscriber.
 */
actor AsyncStreamBroadcaster<Element: Sendable> {
    private enum TerminalState {
        case finished
        case failed(Error)
    }

    private var continuations: [UUID: AsyncThrowingStream<Element, Error>.Continuation] = [:]
    private var buffer: [Element] = []
    private var terminalState: TerminalState?

    func register() -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let identifier = UUID()

            Task { [weak self] in
                guard let self else { return }
                await self.addContinuation(continuation, id: identifier)
            }

            continuation.onTermination = { _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: identifier)
                }
            }
        }
    }

    func send(_ element: Element) {
        guard terminalState == nil else { return }
        buffer.append(element)
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    func finish(error: Error? = nil) {
        guard terminalState == nil else { return }

        if let error {
            terminalState = .failed(error)
            for continuation in continuations.values {
                continuation.finish(throwing: error)
            }
        } else {
            terminalState = .finished
            for continuation in continuations.values {
                continuation.finish()
            }
        }

        continuations.removeAll()
    }

    private func addContinuation(
        _ continuation: AsyncThrowingStream<Element, Error>.Continuation,
        id: UUID
    ) {
        // Replay entire buffer so late subscribers see full history.
        for element in buffer {
            continuation.yield(element)
        }

        if let terminalState {
            switch terminalState {
            case .finished:
                continuation.finish()
            case .failed(let error):
                continuation.finish(throwing: error)
            }
            return
        }

        continuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
