import Foundation

internal final class MCPOperation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var tasks: [(task: Task<Void, Never>, cancelOnSuccess: Bool)] = []

    var isFinished: Bool { lock.withLock { result != nil } }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let result = lock.withLock { () -> Result<Value, Error>? in
            if let result = self.result { return result }
            self.continuation = continuation
            return nil as Result<Value, Error>?
        }
        if let result { continuation.resume(with: result) }
    }

    func own(_ task: Task<Void, Never>, cancelOnSuccess: Bool = true) {
        let cancel = lock.withLock {
            if let result {
                if case .failure = result { return true }
                return cancelOnSuccess
            }
            tasks.append((task, cancelOnSuccess))
            return false
        }
        if cancel { task.cancel() }
    }

    func finish(_ result: Result<Value, Error>, onFinish: (@Sendable () -> Void)? = nil) {
        let state = lock.withLock { () -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>]) in
            guard self.result == nil else { return (nil, []) }
            onFinish?()
            self.result = result
            let cancelledTasks = tasks.filter {
                if case .failure = result { return true }
                return $0.cancelOnSuccess
            }.map(\.task)
            let state = (continuation, cancelledTasks)
            continuation = nil
            tasks.removeAll()
            return state
        }
        state.1.forEach { $0.cancel() }
        state.0?.resume(with: result)
    }
}

internal final class MCPAbortState: @unchecked Sendable {
    private let lock = NSLock()
    private var aborted = false
    var isAborted: Bool { lock.withLock { aborted } }
    func abort() { lock.withLock { aborted = true } }
}

internal func mcpTimeout(_ options: RequestOptions?) -> TimeInterval? {
    [options?.timeout, options?.maxTotalTimeout].compactMap { $0 }.min()
}

internal func runMCPOperation<Value: Sendable>(
    options: RequestOptions? = nil,
    timeoutMessage: @escaping @Sendable (String) -> String = { "Request timed out after \($0)ms" },
    abortMessage: String = "Request was aborted",
    onAbort: (@Sendable () -> Void)? = nil,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let pending = MCPOperation<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            pending.install(continuation)
            guard !pending.isFinished else { return }
            if options?.signal?() == true {
                pending.finish(.failure(MCPClientError(message: abortMessage)), onFinish: onAbort)
                return
            }
            if let timeout = mcpTimeout(options) {
                pending.own(Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(0, min(timeout, 1e9)) * 1e9))
                        let milliseconds = String(format: "%g", timeout * 1000)
                        pending.finish(.failure(MCPClientError(message: timeoutMessage(milliseconds))), onFinish: onAbort)
                    } catch {}
                })
            }
            if let signal = options?.signal {
                pending.own(Task {
                    do {
                        while !pending.isFinished {
                            if signal() {
                                pending.finish(.failure(MCPClientError(message: abortMessage)), onFinish: onAbort)
                                return
                            }
                            try await Task.sleep(nanoseconds: 10_000_000)
                        }
                    } catch {}
                })
            }
            pending.own(Task {
                do { pending.finish(.success(try await operation())) }
                catch { pending.finish(.failure(error)) }
            })
        }
    } onCancel: {
        pending.finish(.failure(MCPClientError(message: abortMessage, cause: CancellationError())), onFinish: onAbort)
    }
}
