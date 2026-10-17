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
    func waitForBufferDrain() async throws
    func send(_ text: String) async throws
    func close(code: Int?)
}

public typealias OpenAIWebSocketFactory = @Sendable (OpenAIWebSocketRequest) throws -> any OpenAIWebSocketConnection

public extension OpenAIWebSocketConnection {
    func waitUntilOpen() async throws {}
    func waitForBufferDrain() async throws {}
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

    public struct ImageInputCapabilities: Sendable {
        public let supportsFileInputs: Bool?
        public let supportsMaskInputs: Bool?

        public init(supportsFileInputs: Bool? = nil, supportsMaskInputs: Bool? = nil) {
            self.supportsFileInputs = supportsFileInputs
            self.supportsMaskInputs = supportsMaskInputs
        }
    }

    public let provider: String
    public let baseURL: String?
    public let explicitMessageItemType: Bool?
    public let imageInputCapabilities: ImageInputCapabilities?
    public let url: @Sendable (_ options: URLOptions) throws -> String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?
    public let webSocket: OpenAIWebSocketFactory?
    public let generateId: (@Sendable () -> String)?
    public let fileIdPrefixes: [String]?
    public let supportsWebSearchSourcesInclude: Bool?
    public let _internal: InternalOptions?

    public init(
        provider: String,
        baseURL: String? = nil,
        explicitMessageItemType: Bool? = nil,
        imageInputCapabilities: ImageInputCapabilities? = nil,
        url: @escaping @Sendable (_ options: URLOptions) throws -> String,
        headers: @escaping @Sendable () throws -> [String: String?] = { [:] },
        fetch: FetchFunction? = nil,
        webSocket: OpenAIWebSocketFactory? = nil,
        generateId: (@Sendable () -> String)? = nil,
        fileIdPrefixes: [String]? = nil,
        supportsWebSearchSourcesInclude: Bool? = nil,
        _internal: InternalOptions? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.explicitMessageItemType = explicitMessageItemType
        self.imageInputCapabilities = imageInputCapabilities
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.webSocket = webSocket
        self.generateId = generateId
        self.fileIdPrefixes = fileIdPrefixes
        self.supportsWebSearchSourcesInclude = supportsWebSearchSourcesInclude
        self._internal = _internal
    }
}

func makeDefaultOpenAIWebSocketConnection(request: OpenAIWebSocketRequest) -> any OpenAIWebSocketConnection {
    URLSessionOpenAIWebSocketConnection(request: request)
}

private final class URLSessionOpenAIWebSocketConnection: OpenAIWebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let session: URLSession
    private let opening: SocketOpening
    private let closeLock = NSLock()
    private var closed = false
    let messages: AsyncThrowingStream<String, Error>

    init(request: OpenAIWebSocketRequest) {
        var urlRequest = URLRequest(url: request.url)
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if !request.protocols.isEmpty {
            urlRequest.setValue(request.protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        let opening = SocketOpening()
        let session = URLSession(configuration: .default, delegate: opening, delegateQueue: nil)
        let task = session.webSocketTask(with: urlRequest)
        self.opening = opening
        self.session = session
        self.task = task
        messages = AsyncThrowingStream(unfolding: {
            do {
                switch try await task.receive() {
                case .string(let text): return text
                case .data(let data): return String(decoding: data, as: UTF8.self)
                @unknown default: throw WebSocketError.closed(code: nil, reason: nil)
                }
            } catch {
                if task.closeCode != .invalid { return nil }
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

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func close(code: Int?) {
        guard closeLock.withLock({ if closed { return false }; closed = true; return true }) else { return }
        opening.finish(.failure(CancellationError()))
        if let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code ?? 1000) {
            task.cancel(with: closeCode, reason: nil)
        } else {
            task.cancel()
        }
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
                return nil as Result<Void, Error>?
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

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish(.failure(WebSocketError.closed(code: closeCode.rawValue, reason: reason.map { String(decoding: $0, as: UTF8.self) })))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(.failure(error ?? WebSocketError.closed(code: nil, reason: nil)))
        session.finishTasksAndInvalidate()
    }
}
