import Foundation
import AISDKProviderUtils

public struct OpenAIWebSocketRequest: Sendable, Equatable {
    public let url: URL
    public let protocols: [String]
    public let headers: [String: String]

    public init(
        url: URL,
        protocols: [String] = [],
        headers: [String: String] = [:]
    ) {
        self.url = url
        self.protocols = protocols
        self.headers = headers
    }
}

public protocol OpenAIWebSocketConnection: Sendable {
    var messages: AsyncThrowingStream<String, Error> { get }

    func waitUntilOpen() async throws
    func send(_ text: String) async throws
    func close(code: Int?)
}

public typealias OpenAIWebSocketFactory = @Sendable (OpenAIWebSocketRequest) throws -> any OpenAIWebSocketConnection

public extension OpenAIWebSocketConnection {
    func waitUntilOpen() async throws {}
}

/// Configuration options for OpenAI provider API calls.
///
/// Mirrors `packages/openai/src/openai-config.ts`.
public struct OpenAIConfig: @unchecked Sendable {
    public struct InternalOptions: Sendable {
        public let currentDate: (@Sendable () -> Date)?

        public init(currentDate: (@Sendable () -> Date)? = nil) {
            self.currentDate = currentDate
        }
    }

    public struct URLOptions: Sendable {

        public let modelId: String
        public let path: String

        public init(modelId: String, path: String) {
            self.modelId = modelId
            self.path = path
        }
    }

    public let provider: String
    public let url: @Sendable (_ options: URLOptions) -> String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?
    public let webSocket: OpenAIWebSocketFactory?
    public let generateId: (@Sendable () -> String)?
    public let fileIdPrefixes: [String]?
    public let _internal: InternalOptions?

    public init(
        provider: String,
        url: @escaping @Sendable (_ options: URLOptions) -> String,
        headers: @escaping @Sendable () throws -> [String: String?],
        fetch: FetchFunction? = nil,
        webSocket: OpenAIWebSocketFactory? = nil,
        generateId: (@Sendable () -> String)? = nil,
        fileIdPrefixes: [String]? = nil,
        _internal: InternalOptions? = nil
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.webSocket = webSocket
        self.generateId = generateId
        self.fileIdPrefixes = fileIdPrefixes
        self._internal = _internal
    }
}

func makeDefaultOpenAIWebSocketConnection(request: OpenAIWebSocketRequest) -> any OpenAIWebSocketConnection {
    URLSessionOpenAIWebSocketConnection(request: request)
}

private final class URLSessionOpenAIWebSocketConnection: OpenAIWebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    let messages: AsyncThrowingStream<String, Error>

    init(request: OpenAIWebSocketRequest) {
        var urlRequest = URLRequest(url: request.url)

        for (key, value) in request.headers where !value.isEmpty {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        if !request.protocols.isEmpty {
            urlRequest.setValue(request.protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }

        let task = URLSession.shared.webSocketTask(with: urlRequest)
        self.task = task
        self.messages = AsyncThrowingStream { continuation in
            let receiveTask = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text):
                            continuation.yield(text)
                        case .data(let data):
                            if let text = String(data: data, encoding: .utf8) {
                                continuation.yield(text)
                            }
                        @unknown default:
                            break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                receiveTask.cancel()
                task.cancel(with: .normalClosure, reason: nil)
            }
        }
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func close(code: Int?) {
        let closeCode: URLSessionWebSocketTask.CloseCode = code == 1001 ? .goingAway : .normalClosure
        task.cancel(with: closeCode, reason: nil)
    }
}
