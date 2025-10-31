/**
 MCP Client implementation for connecting to MCP servers and invoking tools.

 Port of `@ai-sdk/ai/src/tool/mcp/mcp-client.ts`.

 A lightweight MCP Client implementation. The primary purpose of this client is tool conversion
 between MCP<>AI SDK but can later be extended to support other MCP features.

 Tool parameters are automatically inferred from the server's JSON schema
 if not explicitly provided in the tools configuration.

 This client is meant to be used to communicate with a single server. To communicate and fetch
 tools across multiple servers, it's recommended to create a new client instance per server.

 Not supported:
 - Client options (e.g. sampling, roots) as they are not needed for tool conversion
 - Accepting notifications
 - Session management (when passing a sessionId to an instance of the Streamable HTTP transport)
 - Resumable SSE streams
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Client version constant
private let clientVersion = "1.0.0"

/// Abort error for cancelled operations (matches TypeScript AbortError)
public struct AbortError: Error, CustomStringConvertible {
    public let name: String = "AbortError"
    public let message: String
    public let cause: Error?

    public init(message: String = "The operation was aborted", cause: Error? = nil) {
        self.message = message
        self.cause = cause
    }

    public var description: String {
        if let cause = cause {
            return "\(name): \(message) (caused by: \(cause))"
        }
        return "\(name): \(message)"
    }
}

/// Configuration for creating an MCP client
public struct MCPClientConfig: Sendable {
    /// Transport configuration for connecting to the MCP server
    public let transport: MCPTransportVariant

    /// Optional callback for uncaught errors
    public let onUncaughtError: (@Sendable (Error) -> Void)?

    /// Optional client name, defaults to 'ai-sdk-mcp-client'
    public let name: String

    public init(
        transport: MCPTransportVariant,
        onUncaughtError: (@Sendable (Error) -> Void)? = nil,
        name: String = "ai-sdk-mcp-client"
    ) {
        self.transport = transport
        self.onUncaughtError = onUncaughtError
        self.name = name
    }
}

/// Transport variant (config or custom instance)
public enum MCPTransportVariant: Sendable {
    case config(MCPTransportConfig)
    case custom(MCPTransport)
}

/// Creates and initializes an MCP client
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public func createMCPClient(config: MCPClientConfig) async throws -> MCPClient {
    let client = DefaultMCPClient(config: config)
    try await client.initialize()
    return client
}

/// MCP Client protocol
public protocol MCPClient: Sendable {
    /// Returns a set of AI SDK tools from the MCP server
    /// - Parameter options: Optional configuration with tool schema definitions
    /// - Returns: A dictionary of tool names to their implementations
    func tools(options: MCPToolsOptions?) async throws -> [String: Tool]

    /// Closes the client connection
    func close() async throws
}

/// Options for tools() method
public struct MCPToolsOptions: Sendable {
    /// Tool schema definitions (automatic or explicit)
    public let schemas: ToolSchemas

    public init(schemas: ToolSchemas = .automatic) {
        self.schemas = schemas
    }
}

/// Default implementation of MCPClient
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
internal final class DefaultMCPClient: MCPClient, @unchecked Sendable {
    private var transport: MCPTransport
    private let onUncaughtError: (@Sendable (Error) -> Void)?
    private let clientInfo: Configuration

    private let lock = NSLock()
    private var requestMessageId: Int = 0
    private var responseHandlers: [Int: @Sendable (Result<JSONRPCResponse, Error>) -> Void] = [:]
    private var serverCapabilities: ServerCapabilities = ServerCapabilities()
    private var isClosed: Bool = true

    init(config: MCPClientConfig) {
        self.onUncaughtError = config.onUncaughtError
        self.clientInfo = Configuration(name: config.name, version: clientVersion)

        // Resolve transport
        switch config.transport {
        case .config(let transportConfig):
            do {
                self.transport = try createMcpTransport(config: transportConfig)
            } catch {
                // Cannot throw from init, so use fatal error
                fatalError("Failed to create MCP transport: \(error)")
            }
        case .custom(let customTransport):
            self.transport = customTransport
        }

        // Set transport callbacks
        self.transport.onclose = { [weak self] in
            self?.handleClose()
        }

        self.transport.onerror = { [weak self] error in
            self?.handleError(error)
        }

        self.transport.onmessage = { [weak self] message in
            self?.handleMessage(message)
        }
    }

    func initialize() async throws {
        do {
            try await transport.start()

            lock.withLock {
                isClosed = false
            }

            // Send initialize request
            // Note: TypeScript checks for undefined result, but in Swift the decoding
            // process in request() already validates the result is present and valid
            let initResult: InitializeResult = try await request(
                method: "initialize",
                params: nil,
                additionalParams: [
                    "protocolVersion": .string(latestProtocolVersion),
                    "capabilities": .object([:]),
                    "clientInfo": .object([
                        "name": .string(clientInfo.name),
                        "version": .string(clientInfo.version)
                    ])
                ]
            )

            // Additional validation: ensure result has required fields
            // (protocolVersion is non-optional in InitializeResult, so this is already enforced by Codable)

            // Validate protocol version
            guard supportedProtocolVersions.contains(initResult.protocolVersion) else {
                throw MCPClientError(
                    message: "Server's protocol version is not supported: \(initResult.protocolVersion)"
                )
            }

            lock.withLock {
                serverCapabilities = initResult.capabilities
            }

            // Complete initialization handshake
            try await sendNotification(method: "notifications/initialized")

        } catch {
            try? await close()
            throw error
        }
    }

    func close() async throws {
        let wasClosed = lock.withLock { isClosed }
        guard !wasClosed else { return }

        try await transport.close()
        handleClose()
    }

    func tools(options: MCPToolsOptions? = nil) async throws -> [String: Tool] {
        let schemas = options?.schemas ?? .automatic
        var result: [String: Tool] = [:]

        // List all tools from server
        let listResult: ListToolsResult = try await listTools()

        for mcpTool in listResult.tools {
            let name = mcpTool.name

            // Filter by schemas if not automatic
            if case .schemas(let schemaDict) = schemas {
                guard schemaDict[name] != nil else { continue }
            }

            let description = mcpTool.description

            // Weak self for execute closure
            let execute: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { [weak self] args, options in
                guard let self = self else {
                    throw MCPClientError(message: "Client was deallocated")
                }

                // Check abort signal
                if let abortSignal = options.abortSignal, abortSignal() {
                    throw AbortError(message: "The operation was aborted")
                }

                let result: CallToolResult = try await self.callTool(
                    name: name,
                    args: args,
                    abortSignal: options.abortSignal
                )

                // Convert CallToolResult to JSONValue and wrap in ToolExecutionResult
                return .value(try self.callToolResultToJSON(result))
            }

            // Create appropriate tool based on schemas parameter
            let tool: Tool
            switch schemas {
            case .automatic:
                // Use dynamicTool with JSON schema from server
                let inputSchema: Schema<JSONValue> = jsonSchema(mcpTool.inputSchema, validate: nil)
                tool = dynamicTool(
                    description: description,
                    inputSchema: FlexibleSchema(inputSchema),
                    execute: execute
                )

            case .schemas(let schemaDict):
                // Use typed tool with user-provided schema
                guard let toolSchema = schemaDict[name] else {
                    continue
                }
                // Get schema JSONValue
                let schemaJSON = try await toolSchema.inputSchema.resolve().jsonSchema()
                let convertedSchema: Schema<JSONValue> = jsonSchema(schemaJSON, validate: nil)
                tool = AISDKProviderUtils.tool(
                    description: description,
                    inputSchema: FlexibleSchema(convertedSchema),
                    execute: execute
                )
            }

            result[name] = tool
        }

        return result
    }

    // MARK: - Private Methods

    private func assertCapability(method: String) throws {
        switch method {
        case "initialize":
            break
        case "tools/list", "tools/call":
            let hasTools = lock.withLock { serverCapabilities.tools != nil }
            guard hasTools else {
                throw MCPClientError(message: "Server does not support tools")
            }
        default:
            throw MCPClientError(message: "Unsupported method: \(method)")
        }
    }

    private func request<T: Decodable & Sendable>(
        method: String,
        params: JSONValue? = nil,
        additionalParams: [String: JSONValue] = [:],
        abortSignal: (@Sendable () -> Bool)? = nil
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            let closed = lock.withLock { isClosed }
            if closed {
                continuation.resume(throwing: MCPClientError(
                    message: "Attempted to send a request from a closed client"
                ))
                return
            }

            // Check abort signal
            if let abortSignal = abortSignal, abortSignal() {
                continuation.resume(throwing: AbortError(message: "Request was aborted"))
                return
            }

            // Check capability
            do {
                try assertCapability(method: method)
            } catch {
                continuation.resume(throwing: error)
                return
            }

            let messageId = lock.withLock { () -> Int in
                let id = requestMessageId
                requestMessageId += 1
                return id
            }

            // Build request params
            var requestParams: [String: JSONValue] = [:]
            if let params = params, case .object(let paramDict) = params {
                requestParams = paramDict
            }
            for (key, value) in additionalParams {
                requestParams[key] = value
            }

            let jsonrpcRequest = JSONRPCRequest(
                id: .int(messageId),
                method: method,
                params: requestParams.isEmpty ? nil : .object(requestParams)
            )

            // Register response handler
            lock.withLock {
                responseHandlers[messageId] = { [weak self] result in
                    guard let self = self else {
                        continuation.resume(throwing: MCPClientError(message: "Client was deallocated"))
                        return
                    }

                    // Check abort signal again
                    if let abortSignal = abortSignal, abortSignal() {
                        continuation.resume(throwing: AbortError(message: "Request was aborted"))
                        return
                    }

                    switch result {
                    case .success(let response):
                        do {
                            let decoded = try self.decodeResult(response.result, as: T.self)
                            continuation.resume(returning: decoded)
                        } catch {
                            continuation.resume(throwing: MCPClientError(
                                message: "Failed to parse server response",
                                cause: error
                            ))
                        }

                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            // Send request
            Task {
                do {
                    try await transport.send(message: .request(jsonrpcRequest))
                } catch {
                    let _ = self.lock.withLock {
                        self.responseHandlers.removeValue(forKey: messageId)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func listTools(
        params: PaginatedRequest.PaginatedParams? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil
    ) async throws -> ListToolsResult {
        var additionalParams: [String: JSONValue] = [:]
        if let cursor = params?.cursor {
            additionalParams["cursor"] = .string(cursor)
        }
        if let meta = params?.meta {
            additionalParams["_meta"] = .object(meta)
        }

        return try await request(
            method: "tools/list",
            params: nil,
            additionalParams: additionalParams,
            abortSignal: abortSignal
        )
    }

    private func callTool(
        name: String,
        args: JSONValue,
        abortSignal: (@Sendable () -> Bool)?
    ) async throws -> CallToolResult {
        let additionalParams: [String: JSONValue] = [
            "name": .string(name),
            "arguments": args
        ]

        return try await request(
            method: "tools/call",
            params: nil,
            additionalParams: additionalParams,
            abortSignal: abortSignal
        )
    }

    private func sendNotification(method: String, params: JSONValue? = nil) async throws {
        let notification = JSONRPCNotification(
            method: method,
            params: params
        )

        try await transport.send(message: .notification(notification))
    }

    private func decodeResult<T: Decodable>(_ result: JSONValue?, as type: T.Type) throws -> T {
        guard let result = result else {
            throw MCPClientError(message: "Server sent invalid result (nil)")
        }

        // Convert JSONValue to Data for decoding
        let data = try JSONSerialization.data(withJSONObject: result.toAnyObject(), options: [])
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func callToolResultToJSON(_ result: CallToolResult) throws -> JSONValue {
        switch result {
        case .content(let content, let isError, let meta):
            var obj: [String: JSONValue] = [
                "content": .array(content.map { c in
                    switch c {
                    case .text(let textContent):
                        return .object([
                            "type": .string("text"),
                            "text": .string(textContent.text)
                        ])
                    case .image(let imageContent):
                        return .object([
                            "type": .string("image"),
                            "data": .string(imageContent.data),
                            "mimeType": .string(imageContent.mimeType)
                        ])
                    case .resource(let embeddedResource):
                        // Encode resource with full details
                        let resourceValue: JSONValue
                        switch embeddedResource.resource {
                        case .text(let uri, let mimeType, let text):
                            var resourceDict: [String: JSONValue] = [
                                "uri": .string(uri),
                                "text": .string(text)
                            ]
                            if let mimeType = mimeType {
                                resourceDict["mimeType"] = .string(mimeType)
                            }
                            resourceValue = .object(resourceDict)
                        case .blob(let uri, let mimeType, let blob):
                            var resourceDict: [String: JSONValue] = [
                                "uri": .string(uri),
                                "blob": .string(blob)
                            ]
                            if let mimeType = mimeType {
                                resourceDict["mimeType"] = .string(mimeType)
                            }
                            resourceValue = .object(resourceDict)
                        }
                        return .object([
                            "type": .string("resource"),
                            "resource": resourceValue
                        ])
                    }
                }),
                "isError": .bool(isError)
            ]
            if let meta = meta {
                obj["_meta"] = .object(meta)
            }
            return .object(obj)

        case .toolResult(let result, let meta):
            var obj: [String: JSONValue] = [
                "toolResult": result
            ]
            if let meta = meta {
                obj["_meta"] = .object(meta)
            }
            return .object(obj)
        }
    }

    // MARK: - Event Handlers

    private func handleClose() {
        let (shouldHandle, handlers) = lock.withLock { () -> (Bool, [Int: @Sendable (Result<JSONRPCResponse, Error>) -> Void]) in
            guard !isClosed else {
                return (false, [:])
            }

            isClosed = true
            let handlers = responseHandlers
            responseHandlers.removeAll()
            return (true, handlers)
        }

        guard shouldHandle else { return }

        let error = MCPClientError(message: "Connection closed")
        for handler in handlers.values {
            handler(.failure(error))
        }
    }

    private func handleError(_ error: Error) {
        if let callback = onUncaughtError {
            callback(error)
        }
    }

    private func handleMessage(_ message: JSONRPCMessage) {
        switch message {
        case .request, .notification:
            // This lightweight client implementation does not support
            // receiving notifications or requests from server.
            handleError(MCPClientError(message: "Unsupported message type"))

        case .response(let response):
            handleResponse(.success(response))

        case .error(let errorResponse):
            let error = MCPClientError(
                message: errorResponse.error.message,
                data: errorResponse.error.data,
                code: errorResponse.error.code
            )
            handleErrorResponse(errorResponse.id, error: error)
        }
    }

    private func handleResponse(_ result: Result<JSONRPCResponse, Error>) {
        guard case .success(let response) = result else {
            if case .failure(let error) = result {
                handleError(error)
            }
            return
        }

        // Convert ID to integer (accept both int and string IDs like TypeScript)
        let messageId: Int
        switch response.id {
        case .int(let id):
            messageId = id
        case .string(let strId):
            guard let id = Int(strId) else {
                handleError(MCPClientError(
                    message: "Protocol error: Response ID cannot be converted to integer: \(strId)"
                ))
                return
            }
            messageId = id
        }

        let handler = lock.withLock {
            responseHandlers.removeValue(forKey: messageId)
        }

        guard let handler = handler else {
            // Include full response in error message for debugging (matches TypeScript)
            let responseJSON = try? JSONEncoder().encode(response)
            let responseStr = responseJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            handleError(MCPClientError(
                message: "Protocol error: Received a response for an unknown message ID: \(responseStr)"
            ))
            return
        }

        handler(result)
    }

    private func handleErrorResponse(_ id: JSONRPCID?, error: MCPClientError) {
        guard let id = id else {
            handleError(error)
            return
        }

        // Convert ID to integer (accept both int and string IDs like TypeScript)
        let messageId: Int
        switch id {
        case .int(let intId):
            messageId = intId
        case .string(let strId):
            guard let intId = Int(strId) else {
                handleError(error)
                return
            }
            messageId = intId
        }

        let handler = lock.withLock {
            responseHandlers.removeValue(forKey: messageId)
        }

        guard let handler = handler else {
            handleError(MCPClientError(
                message: "Protocol error: Received an error response for an unknown message ID: \(messageId)"
            ))
            return
        }

        handler(.failure(error))
    }
}

// MARK: - Helper Extensions

private extension JSONValue {
    func toAnyObject() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map { $0.toAnyObject() }
        case .object(let dict):
            return dict.mapValues { $0.toAnyObject() }
        }
    }
}
