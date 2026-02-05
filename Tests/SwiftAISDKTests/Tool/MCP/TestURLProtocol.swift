import Foundation

@testable import AISDKProvider

/// A lightweight URLProtocol-based test server for transport integration tests.
///
/// This is intentionally minimal and purpose-built for MCP transport parity tests
/// (SSE + Streamable HTTP), ported from `@ai-sdk/test-server` use in upstream.
final class TestURLProtocol: URLProtocol {
    final class LockedValue<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value

        init(_ initialValue: Value) {
            self.value = initialValue
        }

        func get() -> Value {
            lock.withLock { value }
        }

        func set(_ newValue: Value) {
            lock.withLock { value = newValue }
        }
    }

    struct RecordedCall: Sendable {
        let requestMethod: String
        let requestUrl: String
        let requestHeaders: [String: String]
        let requestUserAgent: String?
        let requestBody: Data?
    }

    enum Response: Sendable {
        case empty(status: Int = 200, headers: [String: String] = [:])
        case data(status: Int = 200, headers: [String: String] = [:], body: Data)
        case jsonValue(status: Int = 200, headers: [String: String] = [:], body: JSONValue)
        case stream(status: Int = 200, headers: [String: String] = [:], controller: TestResponseController)
        case failure(error: URLError)
    }

    /// A controller that allows tests to write streaming response chunks.
    final class TestResponseController: @unchecked Sendable {
        private let lock = NSLock()
        private weak var protocolInstance: TestURLProtocol?
        private var pendingWrites: [Data] = []
        private var finished = false

        fileprivate init() {}

        fileprivate func attach(to protocolInstance: TestURLProtocol) {
            let (pending, shouldFinish): ([Data], Bool) = lock.withLock {
                self.protocolInstance = protocolInstance
                let pending = pendingWrites
                pendingWrites.removeAll(keepingCapacity: true)
                return (pending, finished)
            }

            for chunk in pending {
                protocolInstance.client?.urlProtocol(protocolInstance, didLoad: chunk)
            }

            if shouldFinish {
                protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
            }
        }

        func write(_ string: String) {
            write(Data(string.utf8))
        }

        func write(_ data: Data) {
            let action: WriteAction = lock.withLock {
                guard !finished else { return .drop }
                guard let protocolInstance else {
                    pendingWrites.append(data)
                    return .buffered
                }

                return .write(protocolInstance)
            }

            switch action {
            case .drop, .buffered:
                return
            case .write(let protocolInstance):
                protocolInstance.client?.urlProtocol(protocolInstance, didLoad: data)
            }
        }

        func finish() {
            let action: FinishAction = lock.withLock {
                guard !finished else { return .noop }
                finished = true
                guard let protocolInstance else { return .deferUntilAttach }
                return .finish(protocolInstance)
            }

            switch action {
            case .noop, .deferUntilAttach:
                return
            case .finish(let protocolInstance):
                protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
            }
        }

        private enum WriteAction {
            case drop
            case buffered
            case write(TestURLProtocol)
        }

        private enum FinishAction {
            case noop
            case deferUntilAttach
            case finish(TestURLProtocol)
        }
    }

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var requestHandler: (@Sendable (_ request: URLRequest, _ callNumber: Int) throws -> Response)?
        var calls: [RecordedCall] = []
        var callCount: Int = 0
    }

    private static let storage = Storage()
    private static let exclusiveLock = NSLock()

    private var streamController: TestResponseController?

    static func beginExclusiveAccess() -> @Sendable () -> Void {
        exclusiveLock.lock()
        return { exclusiveLock.unlock() }
    }

    static var requestHandler: (@Sendable (_ request: URLRequest, _ callNumber: Int) throws -> Response)? {
        get { storage.lock.withLock { storage.requestHandler } }
        set { storage.lock.withLock { storage.requestHandler = newValue } }
    }

    static func reset() {
        storage.lock.withLock {
            storage.requestHandler = nil
            storage.calls.removeAll()
            storage.callCount = 0
        }
    }

    static func takeCalls() -> [RecordedCall] {
        storage.lock.withLock { storage.calls }
    }

    static func makeController() -> TestResponseController {
        TestResponseController()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let method = request.httpMethod ?? "GET"
        let headers = normalizeHeaders(request.allHTTPHeaderFields ?? [:])
        let userAgent = headers["user-agent"]

        let body: Data? = request.httpBody ?? readBodyStream(request.httpBodyStream)

        let callNumber: Int = Self.storage.lock.withLock {
            let callNumber = Self.storage.callCount
            Self.storage.callCount += 1
            Self.storage.calls.append(
                RecordedCall(
                    requestMethod: method,
                    requestUrl: url.absoluteString,
                    requestHeaders: headers.filter { $0.key != "user-agent" },
                    requestUserAgent: userAgent,
                    requestBody: body
                )
            )
            return callNumber
        }

        do {
            guard let handler = Self.storage.lock.withLock({ Self.storage.requestHandler }) else {
                let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }

            let response = try handler(request, callNumber)
            try respond(with: response, url: url)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        streamController?.finish()
        streamController = nil
    }

    // MARK: - Private

    private func respond(with response: Response, url: URL) throws {
        switch response {
        case .empty(let status, let headers):
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: normalizeHeaders(headers))!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)

        case .data(let status, let headers, let body):
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: normalizeHeaders(headers))!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)

        case .jsonValue(let status, let headers, let body):
            var mergedHeaders = headers
            if mergedHeaders.keys.map({ $0.lowercased() }).contains("content-type") == false {
                mergedHeaders["content-type"] = "application/json"
            }
            let data = try JSONEncoder().encode(body)
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: normalizeHeaders(mergedHeaders))!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)

        case .stream(let status, let headers, let controller):
            let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: normalizeHeaders(headers))!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            controller.attach(to: self)
            streamController = controller

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func normalizeHeaders(_ headers: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        normalized.reserveCapacity(headers.count)
        for (k, v) in headers {
            normalized[k.lowercased()] = v
        }
        return normalized
    }

    private func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        data.reserveCapacity(1024)

        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }

        return data
    }
}

func makeTestSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TestURLProtocol.self]
    return URLSession(configuration: config)
}

func decodeJSONValue(from data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
}

func normalizeTestURL(_ urlString: String) -> String {
    urlString.hasSuffix("/") ? String(urlString.dropLast()) : urlString
}
