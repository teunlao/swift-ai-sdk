/**
 Server-Sent Events (SSE) transport implementation for MCP.

 Port of `@ai-sdk/ai/src/tool/mcp/mcp-sse-transport.ts`.

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
    // State synchronized via actor or explicit locking
    private let stateLock = NSLock()
    private var _endpoint: URL?
    private var _streamTask: Task<Void, Never>?
    private let url: URL
    private var _connected = false
    private let headers: [String: String]?

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

    public init(url: String, headers: [String: String]? = nil) {
        guard let parsedUrl = URL(string: url) else {
            fatalError("Invalid URL: \(url)")
        }
        self.url = parsedUrl
        self.headers = headers
    }

    public func start() async throws {
        if connected {
            return
        }

        try await establishConnection()
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

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"

            // Add headers with user agent
            var headersDict: [String: String?] = headers?.mapValues { $0 as String? } ?? [:]
            headersDict["Content-Type"] = "application/json"

            let allHeaders = withUserAgentSuffix(
                headersDict,
                "ai-sdk/\(VERSION)",
                getRuntimeEnvironmentUserAgent()
            )

            for (key, value) in allHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }

            // Encode message
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(message)

            // Send request
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = MCPClientError(
                    message: "MCP SSE Transport Error: Invalid response type"
                )
                onerror?(error)
                return
            }

            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
                // Extract response text (with fallback to null if extraction fails)
                let text = String(data: data, encoding: .utf8)
                let error = MCPClientError(
                    message: "MCP SSE Transport Error: POSTing to endpoint (HTTP \(httpResponse.statusCode)): \(text ?? "null")"
                )
                onerror?(error)
                return
            }
        } catch {
            onerror?(error)
        }
    }

    // MARK: - Private Methods

    private func establishConnection() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var didResolve = false

            streamTask = Task {
                do {
                    // Create request
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"

                    // Add headers with user agent
                    var headersDict: [String: String?] = headers?.mapValues { $0 as String? } ?? [:]
                    headersDict["Accept"] = "text/event-stream"

                    let allHeaders = withUserAgentSuffix(
                        headersDict,
                        "ai-sdk/\(VERSION)",
                        getRuntimeEnvironmentUserAgent()
                    )

                    for (key, value) in allHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }

                    // Make request
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw MCPClientError(message: "MCP SSE Transport Error: Invalid response")
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw MCPClientError(
                            message: "MCP SSE Transport Error: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
                        )
                    }

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
