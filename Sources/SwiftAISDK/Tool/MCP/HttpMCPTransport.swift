/**
 HTTP MCP transport implementing the Streamable HTTP style.

 Port of `packages/mcp/src/tool/mcp-http-transport.ts`.
 Upstream commit: f3a72bc2a
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils
import EventSourceParser

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public final class HttpMCPTransport: MCPTransport, @unchecked Sendable {
    private struct ReconnectionOptions: Sendable {
        let initialReconnectionDelay: TimeInterval = 1.0
        let maxReconnectionDelay: TimeInterval = 30.0
        let reconnectionDelayGrowFactor: Double = 1.5
        let maxRetries: Int = 2
    }

    private let stateLock = NSLock()
    private let url: URL
    private let session: URLSession
    private let headers: [String: String]?
    private let authProvider: OAuthClientProvider?
    private var resourceMetadataUrl: URL?
    private var sessionId: String?

    private var _started: Bool = false
    private var _isClosed: Bool = false
    private var _inboundSseTask: Task<Void, Never>?
    private var _inboundSseConnectionActive: Bool = false
    private var _lastInboundEventId: String?
    private var _inboundReconnectAttempts: Int = 0
    private var _reconnectionTask: Task<Void, Never>?
    private var _activeTasks: [Task<Void, Never>] = []

    private let reconnectionOptions = ReconnectionOptions()

    public var onclose: (@Sendable () -> Void)?
    public var onerror: (@Sendable (Error) -> Void)?
    public var onmessage: (@Sendable (JSONRPCMessage) -> Void)?

    public convenience init(config: MCPTransportConfig) throws {
        try self.init(config: config, session: .shared)
    }

    internal init(config: MCPTransportConfig, session: URLSession) throws {
        guard let parsed = URL(string: config.url) else {
            throw MCPClientError(message: "Invalid URL: \(config.url)")
        }

        self.url = parsed
        self.session = session
        self.headers = config.headers
        self.authProvider = config.authProvider
    }

    public convenience init(
        url: String,
        headers: [String: String]? = nil,
        authProvider: OAuthClientProvider? = nil
    ) throws {
        try self.init(url: url, headers: headers, authProvider: authProvider, session: .shared)
    }

    internal init(
        url: String,
        headers: [String: String]? = nil,
        authProvider: OAuthClientProvider? = nil,
        session: URLSession
    ) throws {
        guard let parsed = URL(string: url) else {
            throw MCPClientError(message: "Invalid URL: \(url)")
        }

        self.url = parsed
        self.session = session
        self.headers = headers
        self.authProvider = authProvider
    }

    public func start() async throws {
        let alreadyStarted = stateLock.withLock { _started }
        if alreadyStarted {
            throw MCPClientError(
                message: "MCP HTTP Transport Error: Transport already started. Note: client.connect() calls start() automatically."
            )
        }

        stateLock.withLock {
            _started = true
            _isClosed = false
        }

        // Best-effort, do not await to avoid blocking start().
        stateLock.withLock {
            _inboundSseTask = Task { [weak self] in
                await self?.openInboundSse(triedAuth: false, resumeToken: nil)
            }
        }

        // Match upstream async scheduling: allow the inbound SSE task to start before returning.
        await Task.yield()
    }

    public func close() async throws {
        let (sessionId, inboundTask, reconnectionTask, activeTasks, isClosed): (String?, Task<Void, Never>?, Task<Void, Never>?, [Task<Void, Never>], Bool) =
            stateLock.withLock {
                let isClosed = _isClosed
                _isClosed = true
                _inboundSseConnectionActive = false
                let activeTasks = _activeTasks
                _activeTasks.removeAll()
                return (self.sessionId, _inboundSseTask, _reconnectionTask, activeTasks, isClosed)
            }

        if isClosed {
            onclose?()
            return
        }

        inboundTask?.cancel()
        reconnectionTask?.cancel()
        for task in activeTasks {
            task.cancel()
        }

        do {
            if sessionId != nil {
                let headers = await commonHeaders(base: [:], includeSessionId: true)
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                _ = try await session.data(for: request)
            }
        } catch {
            // ignore
            _ = error
        }

        onclose?()
    }

    public func send(message: JSONRPCMessage) async throws {
        try await attemptSend(message: message, triedAuth: false)
    }

    // MARK: - Private

    private func commonHeaders(base: [String: String], includeSessionId: Bool) async -> [String: String] {
        var merged: [String: String?] = [:]

        // user-provided headers first
        if let headers {
            for (k, v) in headers {
                merged[k] = v
            }
        }

        for (k, v) in base {
            merged[k] = v
        }

        merged["mcp-protocol-version"] = LATEST_PROTOCOL_VERSION

        let currentSessionId = stateLock.withLock { sessionId }
        if includeSessionId, let currentSessionId {
            merged["mcp-session-id"] = currentSessionId
        }

        if let authProvider, let tokens = try? await authProvider.tokens() {
            let accessToken = tokens.accessToken
            merged["Authorization"] = "Bearer \(accessToken)"
        }

        return withUserAgentSuffix(
            merged,
            "ai-sdk/\(VERSION)",
            getRuntimeEnvironmentUserAgent()
        )
    }

    private func attemptSend(message: JSONRPCMessage, triedAuth: Bool) async throws {
        do {
            let headers = await commonHeaders(
                base: [
                    "Content-Type": "application/json",
                    "Accept": "application/json, text/event-stream",
                ],
                includeSessionId: true
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            request.httpBody = try JSONEncoder().encode(message)

            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPClientError(message: "MCP HTTP Transport Error: Invalid response type")
            }

            if let sessionIdHeader = httpResponse.value(forHTTPHeaderField: "mcp-session-id") {
                stateLock.withLock { self.sessionId = sessionIdHeader }
            }

            if httpResponse.statusCode == 401, let authProvider, !triedAuth {
                resourceMetadataUrl = extractResourceMetadataUrl(httpResponse)
                do {
                    let result = try await auth(
                        authProvider,
                        serverUrl: url,
                        authorizationCode: nil,
                        scope: nil,
                        resourceMetadataUrl: resourceMetadataUrl
                    )
                    guard result == .authorized else {
                        let error = UnauthorizedError()
                        onerror?(error)
                        throw error
                    }
                } catch {
                    onerror?(error)
                    throw error
                }

                try await attemptSend(message: message, triedAuth: true)
                return
            }

            // If server accepted the message (e.g. initialized notification), optionally (re)start inbound SSE.
            if httpResponse.statusCode == 202 {
                let (isInboundActive, existingInboundTask) = stateLock.withLock { (_inboundSseConnectionActive, _inboundSseTask) }
                if !isInboundActive {
                    existingInboundTask?.cancel()
                    stateLock.withLock {
                        _inboundSseTask = Task { [weak self] in
                            await self?.openInboundSse(triedAuth: false, resumeToken: nil)
                        }
                    }
                }

                // Drain any body best-effort (usually empty).
                Task { _ = try? await self.collectData(from: bytes) }
                return
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let data = try await collectData(from: bytes)
                let text = String(data: data, encoding: .utf8) ?? "null"
                var errorMessage = "MCP HTTP Transport Error: POSTing to endpoint (HTTP \(httpResponse.statusCode)): \(text)"

                if httpResponse.statusCode == 404 {
                    errorMessage += ". This server does not support HTTP transport. Try using `sse` transport instead"
                }

                let error = MCPClientError(message: errorMessage)
                onerror?(error)
                throw error
            }

            let isNotification: Bool = {
                if case .notification = message { return true }
                return false
            }()

            if isNotification {
                // Drain any body best-effort; servers may respond with JSON acknowledgements.
                Task { _ = try? await self.collectData(from: bytes) }
                return
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "content-type") ?? ""

            if contentType.contains("application/json") {
                let data = try await collectData(from: bytes)

                let decodedMessages: [JSONRPCMessage]
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                    if let array = json as? [Any] {
                        decodedMessages = try array.map { element in
                            let elementData = try JSONSerialization.data(withJSONObject: element, options: [])
                            return try JSONDecoder().decode(JSONRPCMessage.self, from: elementData)
                        }
                    } else {
                        decodedMessages = [try JSONDecoder().decode(JSONRPCMessage.self, from: data)]
                    }
                } else {
                    decodedMessages = [try JSONDecoder().decode(JSONRPCMessage.self, from: data)]
                }

                for m in decodedMessages {
                    onmessage?(m)
                }
                return
            }

            if contentType.contains("text/event-stream") {
                // Process event stream response asynchronously; do not await to avoid blocking send().
                let task = Task { [weak self] in
                    guard let self else { return }
                    await self.processEventStreamBytes(bytes)
                }
                stateLock.withLock { _activeTasks.append(task) }
                return
            }

            // Drain to avoid leaving the response body unread.
            Task { _ = try? await self.collectData(from: bytes) }

            let error = MCPClientError(message: "MCP HTTP Transport Error: Unexpected content type: \(contentType)")
            onerror?(error)
            throw error
        } catch {
            onerror?(error)
            throw error
        }
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        data.reserveCapacity(16_384)
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func dataStream(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var buffer = Data()
                buffer.reserveCapacity(16_384)

                do {
                    for try await byte in bytes {
                        buffer.append(byte)

                        if buffer.count >= 1024 || byte == UInt8(ascii: "\n") {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }

                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func processEventStreamBytes(_ bytes: URLSession.AsyncBytes) async {
        let stream = dataStream(from: bytes)
        let eventStream = EventSourceParserStream.makeStream(from: stream)

        do {
            for try await event in eventStream {
                if Task.isCancelled { return }

                if event.event == "message" {
                    do {
                        let data = Data(event.data.utf8)
                        let msg = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
                        onmessage?(msg)
                    } catch {
                        let e = MCPClientError(
                            message: "MCP HTTP Transport Error: Failed to parse message",
                            cause: error
                        )
                        onerror?(e)
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            onerror?(error)
        }
    }

    private func getNextReconnectionDelay(attempt: Int) -> TimeInterval {
        let delay = reconnectionOptions.initialReconnectionDelay * pow(reconnectionOptions.reconnectionDelayGrowFactor, Double(attempt))
        return min(delay, reconnectionOptions.maxReconnectionDelay)
    }

    private func scheduleInboundSseReconnection() {
        let (attempts, isClosed) = stateLock.withLock { (_inboundReconnectAttempts, _isClosed) }
        if isClosed { return }

        if reconnectionOptions.maxRetries > 0 && attempts >= reconnectionOptions.maxRetries {
            onerror?(
                MCPClientError(
                    message: "MCP HTTP Transport Error: Maximum reconnection attempts (\(reconnectionOptions.maxRetries)) exceeded."
                )
            )
            return
        }

        let delay = getNextReconnectionDelay(attempt: attempts)
        stateLock.withLock { _inboundReconnectAttempts += 1 }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            let (isClosed, resumeToken) = stateLock.withLock { (_isClosed, _lastInboundEventId) }
            if isClosed { return }
            stateLock.withLock {
                _inboundSseTask = Task { [weak self] in
                    await self?.openInboundSse(triedAuth: false, resumeToken: resumeToken)
                }
            }
        }

        stateLock.withLock { _reconnectionTask = task }
    }

    // Open optional inbound SSE stream; best-effort and resumable.
    private func openInboundSse(triedAuth: Bool, resumeToken: String?) async {
        defer {
            stateLock.withLock {
                _inboundSseTask = nil
                _inboundSseConnectionActive = false
            }
        }
        do {
            var baseHeaders: [String: String] = ["Accept": "text/event-stream"]
            if let resumeToken {
                baseHeaders["last-event-id"] = resumeToken
            }

            let headers = await commonHeaders(base: baseHeaders, includeSessionId: true)

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                onerror?(MCPClientError(message: "MCP HTTP Transport Error: Invalid response type"))
                return
            }

            if let sessionIdHeader = httpResponse.value(forHTTPHeaderField: "mcp-session-id") {
                stateLock.withLock { self.sessionId = sessionIdHeader }
            }

            if httpResponse.statusCode == 401, let authProvider, !triedAuth {
                resourceMetadataUrl = extractResourceMetadataUrl(httpResponse)
                do {
                    let result = try await auth(
                        authProvider,
                        serverUrl: url,
                        authorizationCode: nil,
                        scope: nil,
                        resourceMetadataUrl: resourceMetadataUrl
                    )
                    guard result == .authorized else {
                        onerror?(UnauthorizedError())
                        return
                    }
                } catch {
                    onerror?(error)
                    return
                }

                await openInboundSse(triedAuth: true, resumeToken: resumeToken)
                return
            }

            if httpResponse.statusCode == 405 {
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                onerror?(
                    MCPClientError(
                        message: "MCP HTTP Transport Error: GET SSE failed: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                    )
                )
                return
            }

            stateLock.withLock {
                _inboundSseConnectionActive = true
            }

            let eventStream = EventSourceParserStream.makeStream(from: dataStream(from: bytes))

            stateLock.withLock {
                _inboundReconnectAttempts = 0
            }

            for try await event in eventStream {
                if Task.isCancelled { return }

                if let id = event.id {
                    stateLock.withLock { _lastInboundEventId = id }
                }

                if event.event == "message" {
                    do {
                        let data = Data(event.data.utf8)
                        let msg = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
                        onmessage?(msg)
                    } catch {
                        onerror?(
                            MCPClientError(
                                message: "MCP HTTP Transport Error: Failed to parse message",
                                cause: error
                            )
                        )
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            if (error as NSError).domain == NSURLErrorDomain, (error as NSError).code == NSURLErrorCancelled {
                return
            }

            onerror?(error)

            let isClosed = stateLock.withLock { _isClosed }
            if !isClosed {
                scheduleInboundSseReconnection()
            }
        }
    }
}
