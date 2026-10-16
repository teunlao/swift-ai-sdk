/**
 HTTP MCP transport implementing the Streamable HTTP style.

 Port of `packages/mcp/src/tool/mcp-http-transport.ts`.
 Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
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

    private let stateLock = NSRecursiveLock()
    private let url: URL
    private let fetchFn: FetchFunction
    private let headers: [String: String]?
    private let authProvider: OAuthClientProvider?
    private var resourceMetadataUrl: URL?
    private var sessionId: String?
    private var protocolVersion = LATEST_PROTOCOL_VERSION
    private let redirect: MCPRedirectMode
    private let onSessionIdChange: (@Sendable (String?) -> Void)?
    private let onSessionExpired: (@Sendable (String) -> Void)?
    private let terminateSessionOnClose: Bool
    private let authorization = MCPTransportAuthorization()

    public func setProtocolVersion(_ version: String) {
        stateLock.withLock { protocolVersion = version }
    }

    private var _started: Bool = false
    private var _isClosed: Bool = false
    private var _inboundSseTask: Task<Void, Never>?
    private var _inboundGeneration: UUID?
    private var _inboundSseConnectionActive: Bool = false
    private var _lastInboundEventId: String?
    private var _inboundReconnectAttempts: Int = 0
    private var _reconnectionTask: Task<Void, Never>?
    private var _activeTasks: [UUID: Task<Void, Never>] = [:]
    private var _sendTasks: [UUID: Task<Void, Error>] = [:]

    private let reconnectionOptions = ReconnectionOptions()

    public var onclose: (@Sendable () -> Void)?
    public var onerror: (@Sendable (Error) -> Void)?
    public var onmessage: (@Sendable (JSONRPCMessage) -> Void)?

    public convenience init(config: MCPTransportConfig) throws {
        try self.init(config: config, fetch: config.fetch ?? defaultFetchFunction())
    }

    public convenience init(config: MCPTransportConfig, session: URLSession) throws {
        try self.init(config: config, fetch: config.fetch ?? mcpSessionFetch(session))
    }

    private init(config: MCPTransportConfig, fetch: @escaping FetchFunction) throws {
        guard let parsed = URL(string: config.url), ["http", "https"].contains(parsed.scheme), parsed.host != nil else {
            throw MCPClientError(message: "Invalid URL: \(config.url)")
        }
        url = parsed
        fetchFn = fetch
        headers = config.headers
        authProvider = config.authProvider
        redirect = config.redirect
        sessionId = config.initialSessionId
        protocolVersion = config.initialProtocolVersion ?? LATEST_PROTOCOL_VERSION
        onSessionIdChange = config.onSessionIdChange
        onSessionExpired = config.onSessionExpired
        terminateSessionOnClose = config.terminateSessionOnClose
    }

    public convenience init(url: String, headers: [String: String]? = nil, authProvider: OAuthClientProvider? = nil) throws {
        try self.init(config: .init(type: "http", url: url, headers: headers, authProvider: authProvider))
    }

    internal convenience init(url: String, headers: [String: String]? = nil, authProvider: OAuthClientProvider? = nil, session: URLSession) throws {
        try self.init(config: .init(type: "http", url: url, headers: headers, authProvider: authProvider), session: session)
    }

    public func start() async throws {
        try stateLock.withLock {
            guard !_started else {
                throw MCPClientError(message: "MCP HTTP Transport Error: Transport already started. Note: client.connect() calls start() automatically.")
            }
            _started = true
            _isClosed = false
        }

        // Best-effort, do not await to avoid blocking start().
        startInboundSse()

        // Match upstream async scheduling: allow the inbound SSE task to start before returning.
        await Task.yield()
    }

    public func close() async throws { try await close(options: nil) }

    public func close(options: MCPTransportCloseOptions?) async throws {
        let (sessionId, inboundTask, reconnectionTask, activeTasks, isClosed): (String?, Task<Void, Never>?, Task<Void, Never>?, [Task<Void, Never>], Bool) =
            stateLock.withLock {
                let isClosed = _isClosed
                _isClosed = true
                _inboundSseConnectionActive = false
                let inboundTask = _inboundSseTask
                let reconnectionTask = _reconnectionTask
                _inboundSseTask = nil
                _inboundGeneration = nil
                _reconnectionTask = nil
                let activeTasks = Array(_activeTasks.values)
                _activeTasks.removeAll()
                _sendTasks.values.forEach { $0.cancel() }
                _sendTasks.removeAll()
                return (self.sessionId, inboundTask, reconnectionTask, activeTasks, isClosed)
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
            if sessionId?.isEmpty == false, terminateSessionOnClose, options?.signal?() != true {
                let headers = try await commonHeaders(base: [:], includeSessionId: true)
                if options?.signal?() == true { onclose?(); return }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                let preparedRequest = request
                _ = try await runMCPOperation(options: .init(signal: options?.signal)) { [self] in
                    let (body, response) = try await fetchMCPResponse(preparedRequest, fetch: fetchFn, redirect: redirect)
                    if let http = response as? HTTPURLResponse {
                        await cancelResponseBody(.init(url: url, httpResponse: http, body: body))
                    }
                }
            }
        } catch {
            // ignore
            _ = error
        }

        onclose?()
    }

    public func send(message: JSONRPCMessage) async throws {
        try await send(message: message, options: nil)
    }

    public func send(message: JSONRPCMessage, options: MCPTransportSendOptions?) async throws {
        try Task.checkCancellation()
        guard options?.signal?() != true else { throw CancellationError() }
        let id = UUID()
        let task = try stateLock.withLock {
            guard !_isClosed else { throw CancellationError() }
            let task = Task { try await attemptSend(message: message, triedAuth: false, options: options) }
            _sendTasks[id] = task
            return task
        }
        defer { task.cancel(); _ = stateLock.withLock { _sendTasks.removeValue(forKey: id) } }
        try await withTaskCancellationHandler {
            try await runMCPOperation(options: .init(signal: options?.signal)) { try await task.value }
        } onCancel: { task.cancel() }
    }

    // MARK: - Private

    private func receive(_ message: JSONRPCMessage, generation: UUID? = nil) {
        stateLock.withLock {
            guard !_isClosed, !Task.isCancelled else { return }
            if let generation, _inboundGeneration != generation { return }
            onmessage?(message)
        }
    }

    private func isInitialize(_ message: JSONRPCMessage) -> Bool {
        if case .request(let request) = message { return request.method == "initialize" }
        return false
    }

    private func setSessionId(_ value: String?) {
        let changed = stateLock.withLock {
            guard sessionId != value else { return false }
            sessionId = value
            return true
        }
        if changed { onSessionIdChange?(value) }
    }

    private func expireSessionId(_ value: String) {
        let cleared = stateLock.withLock {
            guard sessionId == value else { return false }
            sessionId = nil
            return true
        }
        if cleared { onSessionIdChange?(nil) }
        onSessionExpired?(value)
    }

    private func commonHeaders(base: [String: String], includeSessionId: Bool) async throws -> [String: String] {
        var merged: [String: String?] = [:]

        // user-provided headers first
        if let headers {
            for (k, v) in headers {
                merged[k.lowercased()] = v
            }
        }

        for (k, v) in base {
            merged[k.lowercased()] = v
        }

        merged["mcp-protocol-version"] = stateLock.withLock { protocolVersion }

        let currentSessionId = stateLock.withLock { sessionId }
        if includeSessionId, let currentSessionId, !currentSessionId.isEmpty {
            merged["mcp-session-id"] = currentSessionId
        }

        if let authProvider, let tokens = try await authProvider.tokens(), !tokens.accessToken.isEmpty {
            let accessToken = tokens.accessToken
            merged["authorization"] = "Bearer \(accessToken)"
        }

        return withUserAgentSuffix(
            merged,
            "ai-sdk/\(VERSION)",
            getRuntimeEnvironmentUserAgent()
        )
    }

    private func attemptSend(message: JSONRPCMessage, triedAuth: Bool, options: MCPTransportSendOptions?) async throws {
        do {
            try Task.checkCancellation()
            let sessionIdForRequest = isInitialize(message) ? nil : stateLock.withLock { sessionId }
            let headers = try await commonHeaders(
                base: [
                    "Content-Type": "application/json",
                    "Accept": "application/json, text/event-stream",
                ],
                includeSessionId: { if case .request(let request) = message { return request.method != "initialize" }; return true }()
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            request.httpBody = try JSONEncoder().encode(message)

            let (bytes, response) = try await fetchMCPResponse(request, fetch: fetchFn, redirect: redirect)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPClientError(message: "MCP HTTP Transport Error: Invalid response type")
            }

            if let sessionIdHeader = httpResponse.value(forHTTPHeaderField: "mcp-session-id"), !sessionIdHeader.isEmpty {
                setSessionId(sessionIdHeader)
            }

            if httpResponse.statusCode == 401, let authProvider, !triedAuth {
                await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes))
                let challenge = extractWWWAuthenticateParams(httpResponse)
                resourceMetadataUrl = challenge.resourceMetadataUrl
                do {
                    let result = try await authorization.authorize { [self] in try await auth(
                        authProvider,
                        serverUrl: url,
                        authorizationCode: nil,
                        scope: challenge.scope,
                        resourceMetadataUrl: challenge.resourceMetadataUrl,
                        fetchFn: mcpOAuthFetch(fetchFn)
                    ) }
                    guard result == .authorized else {
                        let error = UnauthorizedError()
                        onerror?(error)
                        throw error
                    }
                } catch {
                    onerror?(error)
                    throw error
                }

                try await attemptSend(message: message, triedAuth: true, options: options)
                return
            }

            // If server accepted the message (e.g. initialized notification), optionally (re)start inbound SSE.
            if httpResponse.statusCode == 202 {
                startInboundSse()
                await Task.yield()

                // Drain any body best-effort (usually empty).
                await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes))
                return
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let data = try await collectData(from: bytes)
                let text = String(data: data, encoding: .utf8) ?? "null"
                if case .error(let response) = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) {
                    let id: JSONRPCID?
                    switch message {
                    case .request(let request): id = request.id
                    case .response(let response): id = response.id
                    case .error(let response): id = response.id
                    case .notification: id = nil
                    }
                    if let id {
                        receive(.error(JSONRPCError(id: response.id ?? id, error: response.error)))
                        return
                    }
                }
                var errorMessage = "MCP HTTP Transport Error: POSTing to endpoint (HTTP \(httpResponse.statusCode)): \(text)"

                if httpResponse.statusCode == 404 {
                    if let sessionIdForRequest {
                        expireSessionId(sessionIdForRequest)
                        errorMessage += ". The MCP session expired. Create a new client without `initialSessionId` to start a fresh session"
                    } else {
                        errorMessage += ". This server does not support HTTP transport. Try using `sse` transport instead"
                    }
                }

                let error = MCPClientError(message: errorMessage, statusCode: httpResponse.statusCode, url: url.absoluteString, responseBody: text)
                onerror?(error)
                throw error
            }

            let isNotification: Bool = {
                if case .notification = message { return true }
                return false
            }()

            if isNotification {
                // Drain any body best-effort; servers may respond with JSON acknowledgements.
                await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes))
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
                    receive(m)
                }
                return
            }

            if contentType.contains("text/event-stream") {
                if case .none = bytes {
                    throw MCPClientError(message: "MCP HTTP Transport Error: text/event-stream response without body", statusCode: httpResponse.statusCode, url: url.absoluteString)
                }
                // Process event stream response asynchronously; do not await to avoid blocking send().
                let id = UUID()
                let scheduled = stateLock.withLock {
                    guard !_isClosed, !Task.isCancelled else { return false }
                    _activeTasks[id] = Task { [weak self] in
                        guard let self else { return }
                        defer { _ = stateLock.withLock { _activeTasks.removeValue(forKey: id) } }
                        try? await runMCPOperation(options: .init(signal: options?.signal)) { [self] in
                            await processEventStreamBytes(bytes)
                        }
                    }
                    return true
                }
                if !scheduled { await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes)) }
                return
            }

            // Drain to avoid leaving the response body unread.
            await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes))

            let error = MCPClientError(message: "MCP HTTP Transport Error: Unexpected content type: \(contentType)", statusCode: httpResponse.statusCode, url: url.absoluteString)
            onerror?(error)
            throw error
        } catch {
            if !Task.isCancelled && options?.signal?() != true { onerror?(error) }
            throw error
        }
    }

    private func collectData(from bytes: ProviderHTTPResponseBody) async throws -> Data {
        try await bytes.collectData()
    }

    private func dataStream(from bytes: ProviderHTTPResponseBody) -> AsyncThrowingStream<Data, Error> {
        bytes.makeStream()
    }

    private func processEventStreamBytes(_ bytes: ProviderHTTPResponseBody) async {
        let stream = dataStream(from: bytes)
        let eventStream = EventSourceParserStream.makeStream(from: stream)

        do {
            for try await event in eventStream {
                if Task.isCancelled { return }

                if event.event == nil || event.event == "message" {
                    do {
                        let data = Data(event.data.utf8)
                        let msg = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
                        receive(msg)
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
            if !Task.isCancelled { onerror?(error) }
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
            startInboundSse(resumeToken: resumeToken, onlyIfInactive: false)
        }

        stateLock.withLock { _reconnectionTask = task }
    }

    private func startInboundSse(resumeToken: String? = nil, onlyIfInactive: Bool = true) {
        stateLock.withLock {
            guard !_isClosed, !Task.isCancelled, !onlyIfInactive || !_inboundSseConnectionActive else { return }
            _inboundSseTask?.cancel()
            let generation = UUID()
            _inboundGeneration = generation
            _inboundSseConnectionActive = false
            _inboundSseTask = Task { [weak self] in
                await self?.openInboundSse(triedAuth: false, resumeToken: resumeToken, generation: generation)
            }
        }
    }

    private func openInboundSse(triedAuth: Bool, resumeToken: String?, generation: UUID) async {
        defer {
            stateLock.withLock {
                guard _inboundGeneration == generation else { return }
                _inboundSseTask = nil
                _inboundGeneration = nil
                _inboundSseConnectionActive = false
            }
        }
        do {
            let sessionIdForRequest = stateLock.withLock { sessionId }
            var baseHeaders: [String: String] = ["Accept": "text/event-stream"]
            if let resumeToken {
                baseHeaders["last-event-id"] = resumeToken
            }

            let headers = try await commonHeaders(base: baseHeaders, includeSessionId: true)

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let (bytes, response) = try await fetchMCPResponse(request, fetch: fetchFn, redirect: redirect)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                onerror?(MCPClientError(message: "MCP HTTP Transport Error: Invalid response type"))
                return
            }

            if let sessionIdHeader = httpResponse.value(forHTTPHeaderField: "mcp-session-id"), !sessionIdHeader.isEmpty {
                setSessionId(sessionIdHeader)
            }

            if httpResponse.statusCode == 401, let authProvider, !triedAuth {
                await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes))
                let challenge = extractWWWAuthenticateParams(httpResponse)
                resourceMetadataUrl = challenge.resourceMetadataUrl
                do {
                    let result = try await authorization.authorize { [self] in try await auth(
                        authProvider,
                        serverUrl: url,
                        authorizationCode: nil,
                        scope: challenge.scope,
                        resourceMetadataUrl: challenge.resourceMetadataUrl,
                        fetchFn: mcpOAuthFetch(fetchFn)
                    ) }
                    guard result == .authorized else {
                        onerror?(UnauthorizedError())
                        return
                    }
                } catch {
                    onerror?(error)
                    return
                }

                await openInboundSse(triedAuth: true, resumeToken: resumeToken, generation: generation)
                return
            }

            if httpResponse.statusCode == 405 {
                await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes))
                return
            }

            let hasBody: Bool
            if case .none = bytes { hasBody = false } else { hasBody = true }
            guard (200...299).contains(httpResponse.statusCode), hasBody else {
                await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes))
                if httpResponse.statusCode == 404, let sessionIdForRequest { expireSessionId(sessionIdForRequest) }
                onerror?(
                    MCPClientError(
                            message: "MCP HTTP Transport Error: GET SSE failed: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))",
                            statusCode: httpResponse.statusCode, url: url.absoluteString

                    )
                )
                return
            }

            let accepted = stateLock.withLock {
                guard !_isClosed, _inboundGeneration == generation else { return false }
                _inboundSseConnectionActive = true
                return true
            }
            guard accepted else {
                await cancelResponseBody(.init(url: url, httpResponse: httpResponse, body: bytes))
                return
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

                if event.event == nil || event.event == "message" {
                    do {
                        let data = Data(event.data.utf8)
                        let msg = try JSONDecoder().decode(JSONRPCMessage.self, from: data)
                        receive(msg, generation: generation)
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
