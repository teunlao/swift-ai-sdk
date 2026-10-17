import Foundation

public enum WebSocketMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

public protocol WebSocketLike: Sendable {
    var messages: AsyncThrowingStream<WebSocketMessage, Error> { get }
    func waitUntilOpen() async throws
    func waitForBufferDrain() async throws
    func send(_ message: WebSocketMessage) async throws
    func close(code: Int?)
}

public extension WebSocketLike {
    func waitUntilOpen() async throws {}
    func waitForBufferDrain() async throws {}
}

public typealias WebSocketConstructor = @Sendable (URLRequest) throws -> any WebSocketLike

public func defaultWebSocketConstructor() -> WebSocketConstructor {
    { URLSessionWebSocket(request: $0) }
}

public enum WebSocketError: Error, Sendable, Equatable {
    case invalidURL(String)
    case closed(code: Int?, reason: String?)
    case concurrentReceive
}

public func toWebSocketURL(_ url: String) throws -> URL {
    guard var components = URLComponents(string: url), components.scheme != nil else {
        throw WebSocketError.invalidURL(url)
    }
    switch components.scheme?.lowercased() {
    case "http": components.scheme = "ws"
    case "https": components.scheme = "wss"
    default: break
    }
    guard let result = components.url else { throw WebSocketError.invalidURL(url) }
    return result
}

public func readWebSocketMessageText(_ message: WebSocketMessage) -> String {
    switch message {
    case .text(let text): return text
    case .binary(let data): return String(decoding: data, as: UTF8.self)
    }
}

private final class URLSessionWebSocket: WebSocketLike, @unchecked Sendable {
    let messages: AsyncThrowingStream<WebSocketMessage, Error>
    private let task: URLSessionWebSocketTask
    private let session: URLSession
    private let opening: SocketOpening
    private let closeLock = NSLock()
    private var closed = false

    init(request: URLRequest) {
        let opening = SocketOpening()
        let session = URLSession(configuration: .default, delegate: opening, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        self.opening = opening
        self.session = session
        self.task = task
        messages = AsyncThrowingStream(unfolding: {
            do {
                switch try await task.receive() {
                case .string(let text): return .text(text)
                case .data(let data): return .binary(data)
                @unknown default: throw WebSocketError.closed(code: nil, reason: nil)
                }
            } catch {
                if task.closeCode != .invalid {
                    throw WebSocketError.closed(code: task.closeCode.rawValue,
                        reason: task.closeReason.map { String(decoding: $0, as: UTF8.self) })
                }
                throw error
            }
        })
        task.resume()
    }

    func waitUntilOpen() async throws {
        try await withTaskCancellationHandler {
            try await opening.wait()
        } onCancel: {
            self.close(code: nil)
        }
    }

    func send(_ message: WebSocketMessage) async throws {
        switch message {
        case .text(let text): try await task.send(.string(text))
        case .binary(let data): try await task.send(.data(data))
        }
    }

    func close(code: Int?) {
        guard closeLock.withLock({ if closed { return false }; closed = true; return true }) else { return }
        opening.finish(.failure(CancellationError()))
        if let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code ?? 1000) {
            task.cancel(with: closeCode, reason: nil)
        } else { task.cancel() }
        session.finishTasksAndInvalidate()
    }

    deinit {
        opening.finish(.failure(CancellationError()))
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

private final class SocketOpening: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let completed: Result<Void, Error>? = lock.withLock {
                if let result { return result }
                waiters.append(continuation)
                return nil
            }
            if let completed { continuation.resume(with: completed) }
        }
    }

    func finish(_ completion: Result<Void, Error>) {
        let pending = lock.withLock {
            guard result == nil else { return [] as [CheckedContinuation<Void, Error>] }
            result = completion
            let pending = waiters
            waiters = []
            return pending
        }
        for waiter in pending { waiter.resume(with: completion) }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        finish(.success(()))
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(.failure(WebSocketError.closed(code: closeCode.rawValue, reason: reason.map { String(decoding: $0, as: UTF8.self) })))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(.failure(error ?? WebSocketError.closed(code: nil, reason: nil)))
        session.finishTasksAndInvalidate()
    }
}
