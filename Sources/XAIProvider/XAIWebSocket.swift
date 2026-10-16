import Foundation

public enum XAIWebSocketMessage: Sendable, Equatable { case text(String), binary(Data) }

public protocol XAIWebSocketConnection: Sendable {
    var messages: AsyncThrowingStream<String, Error> { get }
    func send(_ message: XAIWebSocketMessage) async throws
    func close(code: Int?)
}

public typealias XAIWebSocketFactory = @Sendable (URLRequest) throws -> any XAIWebSocketConnection

func defaultXAIWebSocket(_ request: URLRequest) -> any XAIWebSocketConnection { SessionWebSocket(request) }

private final class SessionWebSocket: XAIWebSocketConnection, @unchecked Sendable {
    let messages: AsyncThrowingStream<String, Error>
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    private let receiver: Task<Void, Never>

    init(_ request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
        socket = session.webSocketTask(with: request)
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        messages = pair.stream
        let socket = socket
        pair.continuation.onTermination = { _ in socket.cancel(with: .goingAway, reason: nil) }
        receiver = Task {
            do {
                while !Task.isCancelled {
                    switch try await socket.receive() {
                    case .string(let text): pair.continuation.yield(text)
                    case .data(let data): if let text = String(data: data, encoding: .utf8) { pair.continuation.yield(text) }
                    @unknown default: break
                    }
                }
                pair.continuation.finish()
            } catch {
                if socket.closeCode != .invalid { pair.continuation.finish() }
                else { pair.continuation.finish(throwing: error) }
            }
        }
        socket.resume()
    }
    func send(_ message: XAIWebSocketMessage) async throws {
        switch message { case .text(let text): try await socket.send(.string(text)); case .binary(let data): try await socket.send(.data(data)) }
    }
    func close(code: Int?) {
        receiver.cancel()
        socket.cancel(with: code == 1000 ? .normalClosure : .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
    deinit { receiver.cancel(); socket.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
}
