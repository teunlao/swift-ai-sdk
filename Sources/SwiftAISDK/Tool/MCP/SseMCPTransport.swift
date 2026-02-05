/**
 Server-Sent Events (SSE) transport implementation for MCP.

 Port of `packages/mcp/src/tool/mcp-sse-transport.ts`.
 Upstream commit: f3a72bc2a

 This transport uses SSE for receiving messages and HTTP POST for sending messages,
 following the MCP specification.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils
import EventSourceParser

// MARK: - URL Extensions

extension URL {
    /// Returns the origin of the URL (scheme + host + port)
    /// Matches TypeScript's URL.origin behavior
    var origin: String {
        guard let scheme = scheme?.lowercased(),
              let host = host?.lowercased()
        else {
            // Best-effort fallback for non-absolute URLs.
            var components: [String] = []

            if let scheme = scheme {
                components.append("\(scheme)://")
            }

            if let host = host {
                components.append(host)
            }

            if let port = port {
                components.append(":\(port)")
            }

            return components.joined()
        }

        var origin = "\(scheme)://\(host)"

        if let port = port {
            let defaultPort: Int? = switch scheme {
            case "http": 80
            case "https": 443
            default: nil
            }

            if port != defaultPort {
                origin.append(":\(port)")
            }
        }

        return origin
    }
}

/**
 SSE-based transport for MCP communication.

 The transport:
 1. Connects via SSE to receive an endpoint URL
 2. Receives messages via SSE events
 3. Sends messages via HTTP POST to the endpoint URL

 - Note: Requires macOS 12.0+ for streaming bytes API
 */
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public final class SseMCPTransport: MCPTransport, @unchecked Sendable {
    private let stateLock = NSLock()
    private var _endpoint: URL?
    private var _streamTask: Task<Void, Never>?
    private let url: URL
    private let session: URLSession
    private var _connected = false
    private let headers: [String: String]?
    private let authProvider: (any OAuthClientProvider)?
    private var resourceMetadataUrl: URL?

    private var endpoint: URL? {
        get { stateLock.withLock { _endpoint } }
        set { stateLock.withLock { _endpoint = newValue } }
    }

    private var streamTask: Task<Void, Never>? {
        get { stateLock.withLock { _streamTask } }
        set { stateLock.withLock { _streamTask = newValue } }
    }

    private var connected: Bool {
        get { stateLock.withLock { _connected } }
        set { stateLock.withLock { _connected = newValue } }
    }

    public var onclose: (@Sendable () -> Void)?
    public var onerror: (@Sendable (Error) -> Void)?
    public var onmessage: (@Sendable (JSONRPCMessage) -> Void)?

    public convenience init(config: MCPTransportConfig) throws {
        try self.init(config: config, session: .shared)
    }

    internal init(config: MCPTransportConfig, session: URLSession) throws {
        guard let parsedUrl = URL(string: config.url) else {
            throw MCPClientError(message: "Invalid URL: \(config.url)")
        }
        self.url = parsedUrl
        self.session = session
        self.headers = config.headers
        self.authProvider = config.authProvider
    }

    public convenience init(
        url: String,
        headers: [String: String]? = nil,
        authProvider: (any OAuthClientProvider)? = nil
    ) throws {
        try self.init(url: url, headers: headers, authProvider: authProvider, session: .shared)
    }

    internal init(
        url: String,
        headers: [String: String]? = nil,
        authProvider: (any OAuthClientProvider)? = nil,
        session: URLSession
    ) throws {
        guard let parsedUrl = URL(string: url) else {
            throw MCPClientError(message: "Invalid URL: \(url)")
        }
        self.url = parsedUrl
        self.session = session
        self.headers = headers
        self.authProvider = authProvider
    }

    private func commonHeaders(base: [String: String]) async -> [String: String] {
        var merged: [String: String?] = [:]

        if let headers {
            for (k, v) in headers {
                merged[k] = v
            }
        }

        for (k, v) in base {
            merged[k] = v
        }

        merged["mcp-protocol-version"] = LATEST_PROTOCOL_VERSION

        if let authProvider, let tokens = try? await authProvider.tokens() {
            merged["Authorization"] = "Bearer \(tokens.accessToken)"
        }

        return withUserAgentSuffix(
            merged,
            "ai-sdk/\(VERSION)",
            getRuntimeEnvironmentUserAgent()
        )
    }

    public func start() async throws {
        if connected {
            return
        }

        try await establishConnection(triedAuth: false)
    }

    public func close() async throws {
        connected = false
        streamTask?.cancel()
        streamTask = nil
        onclose?()
    }

    public func send(message: JSONRPCMessage) async throws {
        guard let endpoint = endpoint, connected else {
            throw MCPClientError(message: "MCP SSE Transport Error: Not connected")
        }

        await attemptSend(endpoint: endpoint, message: message, triedAuth: false)
    }

    // MARK: - Private Methods

    private func attemptSend(endpoint: URL, message: JSONRPCMessage, triedAuth: Bool) async {
        do {
            let headers = await commonHeaders(base: [
                "Content-Type": "application/json"
            ])

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            request.httpBody = try JSONEncoder().encode(message)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                onerror?(MCPClientError(message: "MCP SSE Transport Error: Invalid response type"))
                return
            }

            if http.statusCode == 401, let authProvider, !triedAuth {
                resourceMetadataUrl = extractResourceMetadataUrl(http)
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

                await attemptSend(endpoint: endpoint, message: message, triedAuth: true)
                return
            }

            guard (200...299).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "null"
                onerror?(
                    MCPClientError(
                        message: "MCP SSE Transport Error: POSTing to endpoint (HTTP \(http.statusCode)): \(text)"
                    )
                )
                return
            }
        } catch is CancellationError {
            return
        } catch {
            onerror?(error)
        }
    }

    private func establishConnection(triedAuth: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var didResolve = false

            streamTask = Task {
                do {
                    var triedAuthLocal = triedAuth
                    var asyncBytes: URLSession.AsyncBytes?

                    while true {
                        var request = URLRequest(url: url)
                        request.httpMethod = "GET"

                        let headers = await commonHeaders(base: [
                            "Accept": "text/event-stream"
                        ])
                        for (key, value) in headers {
                            request.setValue(value, forHTTPHeaderField: key)
                        }

                        let (bytes, response) = try await session.bytes(for: request)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw MCPClientError(message: "MCP SSE Transport Error: Invalid response type")
                        }

                        if httpResponse.statusCode == 401, let authProvider, !triedAuthLocal {
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
                                    if !didResolve {
                                        didResolve = true
                                        continuation.resume(throwing: error)
                                    }
                                    return
                                }
                            } catch {
                                onerror?(error)
                                if !didResolve {
                                    didResolve = true
                                    continuation.resume(throwing: error)
                                }
                                return
                            }

                            triedAuthLocal = true
                            continue
                        }

                        guard (200...299).contains(httpResponse.statusCode) else {
                            var errorMessage = "MCP SSE Transport Error: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                            if httpResponse.statusCode == 405 {
                                errorMessage += ". This server does not support SSE transport. Try using `http` transport instead"
                            }
                            let error = MCPClientError(message: errorMessage)
                            onerror?(error)
                            if !didResolve {
                                didResolve = true
                                continuation.resume(throwing: error)
                            }
                            return
                        }

                        asyncBytes = bytes
                        break
                    }

                    guard let asyncBytes else { return }

                    // Convert URLSession.AsyncBytes to AsyncThrowingStream<Data, Error>
                    let dataStream = AsyncThrowingStream<Data, Error> { streamContinuation in
                        Task {
                            do {
                                var buffer = Data()
                                for try await byte in asyncBytes {
                                    buffer.append(byte)
                                    // Yield chunks periodically (every 1KB or at line breaks)
                                    if buffer.count >= 1024 || byte == UInt8(ascii: "\n") {
                                        streamContinuation.yield(buffer)
                                        buffer.removeAll(keepingCapacity: true)
                                    }
                                }
                                // Yield remaining buffer
                                if !buffer.isEmpty {
                                    streamContinuation.yield(buffer)
                                }
                                streamContinuation.finish()
                            } catch {
                                streamContinuation.finish(throwing: error)
                            }
                        }
                    }

                    // Parse SSE stream
                    let eventStream = EventSourceParserStream.makeStream(from: dataStream)

                    // Process events
                    for try await event in eventStream {
                        // Check for cancellation
                        if Task.isCancelled {
                            return
                        }

                        switch event.event {
                        case "endpoint":
                            // Parse and validate endpoint URL
                            guard let endpointUrl = URL(string: event.data, relativeTo: url) else {
                                throw MCPClientError(
                                    message: "MCP SSE Transport Error: Invalid endpoint URL: \(event.data)"
                                )
                            }

                            // Verify same origin (matches TypeScript: endpointUrl.origin !== url.origin)
                            if endpointUrl.origin != url.origin {
                                throw MCPClientError(
                                    message: "MCP SSE Transport Error: Endpoint origin does not match connection origin: \(endpointUrl.origin)"
                                )
                            }

                            self.endpoint = endpointUrl
                            self.connected = true

                            // Resolve connection promise
                            if !didResolve {
                                didResolve = true
                                continuation.resume()
                            }

                        case "message":
                            // Parse and validate JSON-RPC message
                            guard let data = event.data.data(using: .utf8) else {
                                let error = MCPClientError(
                                    message: "MCP SSE Transport Error: Failed to decode message data"
                                )
                                self.onerror?(error)
                                continue
                            }

                            do {
                                let decoder = JSONDecoder()
                                let message = try decoder.decode(JSONRPCMessage.self, from: data)
                                self.onmessage?(message)
                            } catch {
                                let mcpError = MCPClientError(
                                    message: "MCP SSE Transport Error: Failed to parse message",
                                    cause: error
                                )
                                self.onerror?(mcpError)
                                // Continue processing other messages
                            }

                        default:
                            // Ignore other event types
                            break
                        }
                    }

                    // Stream ended
                    if self.connected {
                        self.connected = false
                        throw MCPClientError(
                            message: "MCP SSE Transport Error: Connection closed unexpectedly"
                        )
                    } else if !didResolve {
                        let error = MCPClientError(
                            message: "MCP SSE Transport Error: Connection closed unexpectedly"
                        )
                        didResolve = true
                        continuation.resume(throwing: error)
                    }
                } catch is CancellationError {
                    // Task was cancelled, exit gracefully
                    if !didResolve {
                        didResolve = true
                        continuation.resume(throwing: CancellationError())
                    }
                } catch {
                    self.onerror?(error)
                    if !didResolve {
                        didResolve = true
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

/**
 Deserialize a line of text as a JSON-RPC message.

 - Parameter line: The line to deserialize
 - Returns: The deserialized JSON-RPC message
 - Throws: DecodingError if the line is not a valid JSON-RPC message
 */
public func deserializeMessage(_ line: String) throws -> JSONRPCMessage {
    guard let data = line.data(using: .utf8) else {
        throw MCPClientError(message: "Failed to encode line as UTF-8")
    }
    let decoder = JSONDecoder()
    return try decoder.decode(JSONRPCMessage.self, from: data)
}
