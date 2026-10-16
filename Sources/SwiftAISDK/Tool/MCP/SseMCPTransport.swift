import Foundation
import AISDKProvider
import AISDKProviderUtils
import EventSourceParser

extension URL {
    var origin: String {
        guard let scheme = scheme?.lowercased(), let host = host?.lowercased() else { return "null" }
        let hostName = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let defaultPort = scheme == "https" ? 443 : scheme == "http" ? 80 : nil
        return "\(scheme)://\(hostName)" + (port != nil && port != defaultPort ? ":\(port!)" : "")
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public final class SseMCPTransport: MCPTransport, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let url: URL
    private let fetchFn: FetchFunction
    private let headers: [String: String]?
    private let authProvider: (any OAuthClientProvider)?
    private let redirect: MCPRedirectMode
    private let authorization = MCPTransportAuthorization()
    private var protocolVersion = LATEST_PROTOCOL_VERSION
    private var endpoint: URL?
    private var streamTask: Task<Void, Never>?
    private var startup: MCPOperation<Void>?
    private var sends: [UUID: Task<Void, Error>] = [:]
    private var connected = false

    public var onclose: (@Sendable () -> Void)?
    public var onerror: (@Sendable (Error) -> Void)?
    public var onmessage: (@Sendable (JSONRPCMessage) -> Void)?

    public convenience init(config: MCPTransportConfig) throws { try self.init(config: config, fetch: config.fetch ?? defaultFetchFunction()) }

    public convenience init(config: MCPTransportConfig, session: URLSession) throws {
        try self.init(config: config, fetch: config.fetch ?? mcpSessionFetch(session))
    }

    private init(config: MCPTransportConfig, fetch: @escaping FetchFunction) throws {
        guard let url = URL(string: config.url), ["http", "https"].contains(url.scheme), url.host != nil else {
            throw MCPClientError(message: "Invalid URL: \(config.url)")
        }
        self.url = url
        fetchFn = fetch
        headers = config.headers
        authProvider = config.authProvider
        redirect = config.redirect
    }

    public convenience init(url: String, headers: [String: String]? = nil, authProvider: (any OAuthClientProvider)? = nil) throws {
        try self.init(config: .init(url: url, headers: headers, authProvider: authProvider))
    }

    internal convenience init(url: String, headers: [String: String]? = nil, authProvider: (any OAuthClientProvider)? = nil, session: URLSession) throws {
        try self.init(config: .init(url: url, headers: headers, authProvider: authProvider), session: session)
    }

    public func setProtocolVersion(_ version: String) { lock.withLock { protocolVersion = version } }

    private func commonHeaders(_ base: [String: String]) async throws -> [String: String] {
        var merged: [String: String?] = [:]
        for (key, value) in headers ?? [:] { merged[key.lowercased()] = value }
        for (key, value) in base { merged[key.lowercased()] = value }
        merged["mcp-protocol-version"] = lock.withLock { protocolVersion }
        if let tokens = try await authProvider?.tokens(), !tokens.accessToken.isEmpty { merged["authorization"] = "Bearer \(tokens.accessToken)" }
        return withUserAgentSuffix(merged, "ai-sdk/\(VERSION)", getRuntimeEnvironmentUserAgent())
    }

    private func authorize(_ response: HTTPURLResponse) async throws {
        guard let authProvider else { throw UnauthorizedError() }
        let challenge = extractWWWAuthenticateParams(response)
        let result = try await authorization.authorize { [self] in
            try await auth(authProvider, serverUrl: url, scope: challenge.scope, resourceMetadataUrl: challenge.resourceMetadataUrl, fetchFn: mcpOAuthFetch(fetchFn))
        }
        guard result == .authorized else { throw UnauthorizedError() }
    }

    public func start() async throws {
        if lock.withLock({ connected }) { return }
        let pending = MCPOperation<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.install(continuation)
                lock.withLock {
                    guard !pending.isFinished else { return }
                    startup = pending
                    streamTask = Task { [self] in await establishConnection(pending) }
                }
            }
        } onCancel: {
            pending.finish(.failure(CancellationError()))
            self.lock.withLock { self.streamTask?.cancel() }
        }
    }

    private func establishConnection(_ pending: MCPOperation<Void>) async {
        do {
            var triedAuth = false
            while true {
                try Task.checkCancellation()
                var request = URLRequest(url: url)
                for (key, value) in try await commonHeaders(["Accept": "text/event-stream"]) {
                    request.setValue(value, forHTTPHeaderField: key)
                }
                let (bytes, response) = try await fetchMCPResponse(request, fetch: fetchFn, redirect: redirect)
                guard let response = response as? HTTPURLResponse else { throw MCPClientError(message: "MCP SSE Transport Error: Invalid response type") }
                if response.statusCode == 401, authProvider != nil, !triedAuth {
                    await cancelResponseBody(.init(url: url, httpResponse: response, body: bytes))
                    try await authorize(response)
                    triedAuth = true
                    continue
                }
                let hasBody: Bool
                if case .none = bytes { hasBody = false } else { hasBody = true }
                guard (200...299).contains(response.statusCode), hasBody else {
                    await cancelResponseBody(.init(url: url, httpResponse: response, body: bytes))
                    var message = "MCP SSE Transport Error: \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))"
                    if response.statusCode == 405 { message += ". This server does not support SSE transport. Try using `http` transport instead" }
                    throw MCPClientError(message: message)
                }
                for try await event in EventSourceParserStream.makeStream(from: bytes.makeStream()) {
                    try Task.checkCancellation()
                    if event.event == "endpoint" {
                        if lock.withLock({ endpoint != nil }) { continue }
                        guard let endpoint = URL(string: event.data, relativeTo: url)?.absoluteURL else {
                            throw MCPClientError(message: "MCP SSE Transport Error: Invalid endpoint URL: \(event.data)")
                        }
                        guard endpoint.origin == url.origin else {
                            lock.withLock { connected = false; self.endpoint = nil }
                            throw MCPClientError(message: "MCP SSE Transport Error: Endpoint origin does not match connection origin: \(endpoint.origin)")
                        }
                        let accepted = lock.withLock {
                            guard startup === pending, !Task.isCancelled else { return false }
                            self.endpoint = endpoint
                            connected = true
                            return true
                        }
                        if accepted { pending.finish(.success(())) }
                    } else if event.event == nil || event.event == "message" {
                        do {
                            let message = try deserializeMessage(event.data)
                            lock.withLock {
                                guard startup === pending, !Task.isCancelled else { return }
                                onmessage?(message)
                            }
                        }
                        catch { onerror?(MCPClientError(message: "MCP SSE Transport Error: Failed to parse message", cause: error)) }
                    }
                }
                try Task.checkCancellation()
                let wasConnected = lock.withLock { let value = connected; connected = false; return value }
                throw MCPClientError(message: wasConnected
                    ? "MCP SSE Transport Error: Connection closed unexpectedly"
                    : "MCP SSE Transport Error: Connection closed before endpoint event was received")
            }
        } catch {
            pending.finish(.failure(error))
            if !Task.isCancelled { onerror?(error) }
        }
    }

    public func send(message: JSONRPCMessage) async throws {
        try Task.checkCancellation()
        let id = UUID()
        let task = try lock.withLock {
            guard connected, let endpoint else {
                throw MCPClientError(message: "MCP SSE Transport Error: Not connected")
            }
            let task = Task { [self] in try await attemptSend(endpoint: endpoint, message: message) }
            sends[id] = task
            return task
        }
        defer { _ = lock.withLock { sends.removeValue(forKey: id) } }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func attemptSend(endpoint: URL, message: JSONRPCMessage) async throws {
        do {
            var triedAuth = false
            while true {
                try Task.checkCancellation()
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                for (key, value) in try await commonHeaders(["Content-Type": "application/json"]) { request.setValue(value, forHTTPHeaderField: key) }
                request.httpBody = try JSONEncoder().encode(message)
                let (body, rawResponse) = try await fetchMCPResponse(request, fetch: fetchFn, redirect: redirect)
                guard let response = rawResponse as? HTTPURLResponse else { throw MCPClientError(message: "MCP SSE Transport Error: Invalid response type") }
                if response.statusCode == 401, let authProvider, !triedAuth {
                    await cancelResponseBody(.init(url: endpoint, httpResponse: response, body: body))
                    let accessToken = try await authProvider.tokens()?.accessToken
                    if accessToken == nil || request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accessToken!)" {
                        try await authorize(response)
                    }
                    triedAuth = true
                    continue
                }
                guard (200...299).contains(response.statusCode) else {
                    let text = String(data: try await body.collectData(), encoding: .utf8)
                    throw MCPClientError(
                        message: "MCP SSE Transport Error: POSTing to endpoint (HTTP \(response.statusCode)): \(text ?? "null")",
                        statusCode: response.statusCode, url: endpoint.absoluteString, responseBody: text
                    )
                }
                await cancelResponseBody(.init(url: endpoint, httpResponse: response, body: body))
                return
            }
        } catch {
            if !Task.isCancelled { onerror?(error) }
            throw error
        }
    }

    public func close() async throws {
        lock.withLock {
            connected = false
            endpoint = nil
            streamTask?.cancel()
            streamTask = nil
            startup?.finish(.failure(CancellationError()))
            startup = nil
            sends.values.forEach { $0.cancel() }
            sends.removeAll()
        }
        onclose?()
    }
}

public func deserializeMessage(_ line: String) throws -> JSONRPCMessage {
    try JSONDecoder().decode(JSONRPCMessage.self, from: Data(line.utf8))
}
