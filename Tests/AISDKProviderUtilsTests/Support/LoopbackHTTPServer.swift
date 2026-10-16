#if canImport(Network)
import Foundation
import Network

/// A minimal HTTP/1.1 server on 127.0.0.1 for transport tests. Each accepted
/// connection is driven by the test's `handler`.
final class LoopbackHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (LoopbackHTTPConnection) async -> Void

    private let listener: NWListener
    let port: UInt16

    var origin: String { "http://127.0.0.1:\(port)" }

    init(handler: @escaping Handler) async throws {
        let queue = DispatchQueue(label: "loopback-http-server")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Task { await handler(LoopbackHTTPConnection(connection: connection)) }
        }

        port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let resumed = LockedFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.set() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if resumed.set() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }
}

struct LoopbackHTTPRequest: Sendable {
    let method: String
    let path: String
    /// Lowercased header names.
    let headers: [String: String]
}

final class LoopbackHTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private var buffer = Data()
    private var isComplete = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func readRequest() async throws -> LoopbackHTTPRequest {
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil {
            guard try await receiveMore() else {
                throw URLError(.networkConnectionLost)
            }
        }
        let range = buffer.range(of: separator)!
        let head = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return LoopbackHTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers)
    }

    /// Reads a `Content-Length` or chunked request body to its end.
    func readBody(of request: LoopbackHTTPRequest) async throws -> Data {
        if let length = request.headers["content-length"].flatMap(Int.init) {
            while buffer.count < length {
                guard try await receiveMore() else { throw URLError(.networkConnectionLost) }
            }
            let body = buffer.prefix(length)
            buffer.removeFirst(length)
            return Data(body)
        }

        guard request.headers["transfer-encoding"]?.lowercased() == "chunked" else {
            return Data()
        }

        var body = Data()
        while true {
            let sizeLine = try await readLine()
            let size = Int(sizeLine.split(separator: ";")[0], radix: 16) ?? 0
            if size == 0 {
                _ = try await readLine()
                return body
            }
            while buffer.count < size + 2 {
                guard try await receiveMore() else { throw URLError(.networkConnectionLost) }
            }
            body.append(buffer.prefix(size))
            buffer.removeFirst(size + 2)
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func sendResponse(status: Int, headers: [String: String] = [:], body: Data = Data()) async throws {
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        try await sendHead(status: status, headers: allHeaders)
        try await send(body)
    }

    func sendHead(status: Int, headers: [String: String]) async throws {
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        try await send(Data(head.utf8))
    }

    /// Waits until the peer closes the connection or it fails, discarding what it sends.
    func waitUntilClosed() async {
        while (try? await receiveMore()) == true {
            buffer.removeAll(keepingCapacity: true)
        }
    }

    /// Closes in stages like a production server (RFC 9112 §9.6): half-close, drain
    /// until the peer closes, then release. Closing with unread request bytes resets
    /// the connection, and the reset can erase the response before the client reads it.
    func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
        await waitUntilClosed()
        connection.cancel()
    }

    private func readLine() async throws -> String {
        let crlf = Data("\r\n".utf8)
        while buffer.range(of: crlf) == nil {
            guard try await receiveMore() else { throw URLError(.networkConnectionLost) }
        }
        let range = buffer.range(of: crlf)!
        let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        return line
    }

    /// Appends received bytes; `false` once the peer finished sending.
    private func receiveMore() async throws -> Bool {
        if isComplete { return false }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
                if let data, !data.isEmpty {
                    buffer.append(data)
                }
                if isComplete {
                    self.isComplete = true
                }
                if let error, data?.isEmpty ?? true {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: !(data?.isEmpty ?? true) || !isComplete)
                }
            }
        }
    }
}

/// Thread-safe counter observed by tests while transfers run.
final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func add(_ amount: Int) {
        lock.withLock { count += amount }
    }
}

/// One-shot flag: `set()` returns `true` only the first time.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    func set() -> Bool {
        lock.withLock {
            defer { isSet = true }
            return !isSet
        }
    }
}

/// Polls `value` until it stops changing for `stableFor` consecutive samples.
func waitUntilStable(_ value: () -> Int, stableFor: Int = 4, interval: UInt64 = 50_000_000) async throws -> Int {
    var last = value()
    var stableSamples = 0
    while stableSamples < stableFor {
        try await Task.sleep(nanoseconds: interval)
        let current = value()
        stableSamples = current == last ? stableSamples + 1 : 0
        last = current
    }
    return last
}
#endif
