import Foundation

public struct GoogleWebSocketRequest: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
    public init(url: URL, headers: [String: String] = [:]) { self.url = url; self.headers = headers }
}

public protocol GoogleWebSocketConnection: Sendable {
    var messages: AsyncThrowingStream<String, Error> { get }
    func waitUntilOpen() async throws
    func send(_ text: String) async throws
    func close(code: Int?)
}

public extension GoogleWebSocketConnection {
    func waitUntilOpen() async throws {}
}

public typealias GoogleWebSocketFactory = @Sendable (GoogleWebSocketRequest) throws -> any GoogleWebSocketConnection

func defaultGoogleWebSocket(_ request: GoogleWebSocketRequest) -> any GoogleWebSocketConnection {
    URLSessionGoogleSocket(request)
}

private final class GoogleSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    let opened: AsyncThrowingStream<Void, Error>
    private let continuation: AsyncThrowingStream<Void, Error>.Continuation
    override init() {
        let pair = AsyncThrowingStream<Void, Error>.makeStream()
        opened = pair.stream
        continuation = pair.continuation
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        continuation.yield(())
        continuation.finish()
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        continuation.finish(throwing: URLError(.networkConnectionLost))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { continuation.finish(throwing: error) }
    }
}

private final class URLSessionGoogleSocket: GoogleWebSocketConnection, @unchecked Sendable {
    let messages: AsyncThrowingStream<String, Error>
    private let task: URLSessionWebSocketTask
    private let session: URLSession
    private let delegate: GoogleSocketDelegate
    private let receiver: Task<Void, Never>

    init(_ request: GoogleWebSocketRequest) {
        delegate = GoogleSocketDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        var urlRequest = URLRequest(url: request.url)
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        task = session.webSocketTask(with: urlRequest)
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        messages = pair.stream
        let socket = task
        pair.continuation.onTermination = { _ in socket.cancel(with: .goingAway, reason: nil) }
        receiver = Task {
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    switch message {
                    case .string(let text): pair.continuation.yield(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) { pair.continuation.yield(text) }
                    @unknown default: break
                    }
                }
                pair.continuation.finish()
            } catch { pair.continuation.finish(throwing: error) }
        }
        task.resume()
    }
    func waitUntilOpen() async throws {
        for try await _ in delegate.opened { return }
        throw URLError(.cannotConnectToHost)
    }
    func send(_ text: String) async throws { try await task.send(.string(text)) }
    func close(code: Int?) {
        receiver.cancel()
        task.cancel(with: code == 1000 ? .normalClosure : .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
    deinit { receiver.cancel(); task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
}
