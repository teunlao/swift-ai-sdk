import Foundation

public enum WebSocketMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

public protocol WebSocketLike: Sendable {
    var messages: AsyncThrowingStream<WebSocketMessage, Error> { get }
    func send(_ message: WebSocketMessage) async throws
    func close(code: Int?)
}

public typealias WebSocketConstructor = @Sendable (URLRequest) throws -> any WebSocketLike

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

final class URLSessionWebSocket: WebSocketLike, @unchecked Sendable {
    let messages: AsyncThrowingStream<WebSocketMessage, Error>
    private let task: URLSessionWebSocketTask

    init(request: URLRequest) {
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        messages = AsyncThrowingStream(unfolding: {
            do {
                switch try await task.receive() {
                case .string(let text): return .text(text)
                case .data(let data): return .binary(data)
                @unknown default: throw WebSocketError.closed(code: nil, reason: "Unknown WebSocket message")
                }
            } catch {
                if task.closeCode == .normalClosure { return nil }
                if task.closeCode != .invalid {
                    throw WebSocketError.closed(
                        code: task.closeCode.rawValue,
                        reason: task.closeReason.map { String(decoding: $0, as: UTF8.self) }
                    )
                }
                throw error
            }
        })
        task.resume()
    }

    func send(_ message: WebSocketMessage) async throws {
        switch message {
        case .text(let text): try await task.send(.string(text))
        case .binary(let data): try await task.send(.data(data))
        }
    }

    func close(code: Int?) {
        guard let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code ?? 1000) else {
            task.cancel()
            return
        }
        task.cancel(with: closeCode, reason: nil)
    }

    deinit { task.cancel(with: .goingAway, reason: nil) }
}
