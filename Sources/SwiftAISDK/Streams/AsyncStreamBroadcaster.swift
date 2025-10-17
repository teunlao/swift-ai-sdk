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
        // Capture snapshot length for deterministic replay without losing events
        // that may arrive while we are yielding the buffer.
        let replayCount = buffer.count

        // Register first so any elements appended after the snapshot are delivered live.
        continuations[id] = continuation

        // Replay the snapshot [0 ..< replayCount]. Elements appended after the snapshot
        // will be forwarded by `send(_:)` thanks to the registration above.
        if replayCount > 0 {
            for i in 0..<replayCount {
                continuation.yield(buffer[i])
            }
        }

        // If the broadcaster is already terminal, finish the continuation now.
        if let terminalState {
            switch terminalState {
            case .finished:
                continuation.finish()
            case .failed(let error):
                continuation.finish(throwing: error)
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
