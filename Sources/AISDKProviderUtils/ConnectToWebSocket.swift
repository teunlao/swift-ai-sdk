import Foundation

public struct WebSocketConnection: Sendable {
    public let messages: AsyncThrowingStream<String, Error>
    private let state: WebSocketConnectionState

    fileprivate init(socket: any WebSocketLike, abortSignal: (@Sendable () -> Bool)?) {
        let state = WebSocketConnectionState(socket: socket)
        self.state = state
        messages = AsyncThrowingStream(unfolding: { try await state.next() })
        state.observeAbort(abortSignal)
    }

    public func send(_ message: WebSocketMessage) async throws {
        try await state.send(message)
    }

    public func close(code: Int? = nil) {
        state.finish(code: code)
    }
}

public func connectToWebSocket(
    url: String,
    protocols: [String] = [],
    headers: [String: String?] = [:],
    webSocket: WebSocketConstructor? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil
) throws -> WebSocketConnection {
    try Task.checkCancellation()
    if abortSignal?() == true { throw CancellationError() }
    guard let endpoint = URL(string: url), ["ws", "wss"].contains(endpoint.scheme?.lowercased() ?? ""), endpoint.host != nil else {
        throw WebSocketError.invalidURL(url)
    }
    var request = URLRequest(url: endpoint)
    for (name, value) in headers {
        if let value { request.setValue(value, forHTTPHeaderField: name) }
    }
    if !protocols.isEmpty {
        request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
    }
    let socket = try (webSocket ?? defaultWebSocketConstructor())(request)
    if Task.isCancelled || abortSignal?() == true {
        socket.close(code: nil)
        throw CancellationError()
    }
    return WebSocketConnection(socket: socket, abortSignal: abortSignal)
}

private final class WebSocketConnectionState: @unchecked Sendable {
    private enum Completion {
        case finished
        case failed(Error)
    }

    private struct PendingRead {
        let id: UUID
        let continuation: CheckedContinuation<String?, Error>
    }

    private struct PendingSend {
        let task: Task<Void, Never>
        let continuation: CheckedContinuation<Void, Error>
    }

    private let socket: any WebSocketLike
    private let iterator: AsyncIteratorBox<AsyncThrowingStream<WebSocketMessage, Error>.Iterator>
    private let lock = NSLock()
    private var completion: Completion?
    private var pendingRead: PendingRead?
    private var receiveTask: Task<Void, Never>?
    private var abortTask: Task<Void, Never>?
    private var pendingSends: [UUID: PendingSend] = [:]
    private var sendTail: (id: UUID, task: Task<Void, Never>)?

    init(socket: any WebSocketLike) {
        self.socket = socket
        iterator = AsyncIteratorBox(socket.messages.makeAsyncIterator())
    }

    func observeAbort(_ signal: (@Sendable () -> Bool)?) {
        guard let signal else { return }
        // A closure-only signal has no notification channel.
        let monitor = Task { [weak self] in
            while !Task.isCancelled {
                if signal() {
                    self?.finish(error: CancellationError())
                    return
                }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
        let stopped = lock.withLock {
            if completion != nil { return true }
            abortTask = monitor
            return false
        }
        if stopped { monitor.cancel() }
    }

    func next() async throws -> String? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let terminal: Completion? = lock.withLock {
                    if let completion { return completion }
                    guard pendingRead == nil else { return .failed(WebSocketError.concurrentReceive) }
                    let id = UUID()
                    pendingRead = PendingRead(id: id, continuation: continuation)
                    let iterator = self.iterator
                    receiveTask = Task { [weak self] in
                        let result: Result<WebSocketMessage?, Error>
                        do { result = .success(try await iterator.next()) }
                        catch { result = .failure(error) }
                        self?.deliver(result, id: id)
                    }
                    return nil
                }
                if let terminal { resume(continuation, completion: terminal) }
            }
        } onCancel: {
            self.finish(error: CancellationError())
        }
    }

    private func deliver(_ result: Result<WebSocketMessage?, Error>, id: UUID) {
        switch result {
        case .success(.none): finish()
        case .failure(let error): finish(error: error)
        case .success(.some(let message)):
            let continuation = lock.withLock {
                guard pendingRead?.id == id else { return nil as CheckedContinuation<String?, Error>? }
                let continuation = pendingRead?.continuation
                pendingRead = nil
                receiveTask = nil
                return continuation
            }
            continuation?.resume(returning: readWebSocketMessageText(message))
        }
    }

    func send(_ message: WebSocketMessage) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let terminal: Completion? = lock.withLock {
                    if let completion { return completion }
                    let id = UUID()
                    let previous = sendTail?.task
                    let socket = self.socket
                    let task = Task<Void, Never> { [weak self] in
                        if let previous { await previous.value }
                        do {
                            try Task.checkCancellation()
                            try await socket.waitUntilOpen()
                            try await socket.send(message)
                            self?.completeSend(id: id)
                        } catch { self?.finish(error: error) }
                    }
                    pendingSends[id] = PendingSend(task: task, continuation: continuation)
                    sendTail = (id, task)
                    return nil
                }
                if let terminal {
                    switch terminal {
                    case .finished: continuation.resume(throwing: WebSocketError.closed(code: nil, reason: nil))
                    case .failed(let error): continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            self.finish(error: CancellationError())
        }
    }

    private func completeSend(id: UUID) {
        let continuation = lock.withLock {
            if sendTail?.id == id { sendTail = nil }
            return pendingSends.removeValue(forKey: id)?.continuation
        }
        continuation?.resume()
    }

    func finish(error: Error? = nil, code: Int? = nil) {
        let resources: (PendingRead?, Task<Void, Never>?, Task<Void, Never>?, [PendingSend])? = lock.withLock {
            guard completion == nil else { return nil }
            completion = error.map(Completion.failed) ?? .finished
            let resources = (pendingRead, receiveTask, abortTask, Array(pendingSends.values))
            pendingRead = nil
            receiveTask = nil
            abortTask = nil
            pendingSends = [:]
            sendTail = nil
            return resources
        }
        guard let resources else { return }
        resources.1?.cancel()
        resources.2?.cancel()
        for send in resources.3 { send.task.cancel() }
        socket.close(code: code)
        if let pending = resources.0 {
            resume(pending.continuation, completion: error.map(Completion.failed) ?? .finished)
        }
        for send in resources.3 {
            send.continuation.resume(throwing: error ?? WebSocketError.closed(code: code, reason: nil))
        }
    }

    private func resume(_ continuation: CheckedContinuation<String?, Error>, completion: Completion) {
        switch completion {
        case .finished: continuation.resume(returning: nil)
        case .failed(let error): continuation.resume(throwing: error)
        }
    }

    deinit {
        receiveTask?.cancel()
        abortTask?.cancel()
        for send in pendingSends.values { send.task.cancel() }
        if completion == nil { socket.close(code: nil) }
    }
}
