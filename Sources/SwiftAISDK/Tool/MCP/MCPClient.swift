/**
 MCP Client implementation for connecting to MCP servers and invoking tools.

 Port of `packages/mcp/src/tool/mcp-client.ts`.
 Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4

 A lightweight MCP Client implementation.

 The primary purpose of this client is tool conversion between MCP<>AI SDK
 but can later be extended to support other MCP features.

 Tool parameters are automatically inferred from the server's JSON schema
 if not explicitly provided in the tools configuration.

 This client is meant to be used to communicate with a single server. To communicate and fetch
 tools across multiple servers, it's recommended to create a new client instance per server.

 Not supported:
 - Accepting notifications
 - Automatic session persistence for Streamable HTTP transport
 - Resumable SSE streams
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Abort error for cancelled operations (matches TypeScript AbortError)
public struct AbortError: Error, CustomStringConvertible {
    public let name: String = "AbortError"
    public let message: String
    public let cause: (any Error)?

    public init(message: String = "The operation was aborted", cause: (any Error)? = nil) {
        self.message = message
        self.cause = cause
    }

    public var description: String {
        if let cause {
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

    /// Optional client version, defaults to '1.0.0'
    public let version: String

    /// Optional client capabilities to advertise during initialization.
    ///
    /// NOTE: It is up to the client application to handle the requests properly.
    /// This parameter just helps surface the request from the server.
    public let capabilities: ClientCapabilities
    public let initializationOptions: RequestOptions?
    public let initialInitializeResult: InitializeResult?
    public let maxRetries: Int

    public init(
        transport: MCPTransportVariant,
        onUncaughtError: (@Sendable (Error) -> Void)? = nil,
        name: String = "ai-sdk-mcp-client",
        version: String = "1.0.0",
        capabilities: ClientCapabilities = ClientCapabilities(),
        clientName: String? = nil,
        initializationOptions: RequestOptions? = nil,
        initialInitializeResult: InitializeResult? = nil,
        maxRetries: Int = 0
    ) {
        self.transport = transport
        self.onUncaughtError = onUncaughtError
        self.name = clientName ?? name
        self.version = version
        self.capabilities = capabilities
        self.initializationOptions = initializationOptions
        self.initialInitializeResult = initialInitializeResult
        self.maxRetries = maxRetries
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
    let client = try DefaultMCPClient(config: config)
    try await client.initialize()
    return client
}

@available(*, deprecated, renamed: "createMCPClient")
public func experimental_createMCPClient(config: MCPClientConfig) async throws -> MCPClient {
    try await createMCPClient(config: config)
}

public typealias MCPClientCapabilities = ClientCapabilities
@available(*, deprecated, renamed: "MCPClientConfig")
public typealias experimental_MCPClientConfig = MCPClientConfig
@available(*, deprecated, renamed: "MCPClient")
public typealias experimental_MCPClient = MCPClient
@available(*, deprecated, renamed: "MCPClientCapabilities")
public typealias experimental_MCPClientCapabilities = ClientCapabilities

/// MCP Client protocol
public protocol MCPClient: Sendable {
    var serverInfo: Configuration { get }
    var initializeResult: InitializeResult { get }
    var instructions: String? { get }

    func listTools(options: MCPListToolsOptions?) async throws -> ListToolsResult
    func callTool(name: String, arguments: JSONValue?, options: RequestOptions?) async throws -> CallToolResult
    func toolsFromDefinitions(_ definitions: ListToolsResult, options: MCPToolsOptions?) throws -> [String: Tool]
    func complete(args: CompleteRequestParams, options: RequestOptions?) async throws -> CompleteResult
    /// Returns a set of AI SDK tools from the MCP server.
    ///
    /// - Parameter options: Optional configuration with tool schema definitions.
    /// - Returns: A dictionary of tool names to their implementations.
    func tools(options: MCPToolsOptions?) async throws -> [String: Tool]

    func listResources(options: MCPListResourcesOptions?) async throws -> ListResourcesResult
    func readResource(args: MCPReadResourceArgs) async throws -> ReadResourceResult
    func listResourceTemplates(options: MCPListResourceTemplatesOptions?) async throws -> ListResourceTemplatesResult

    func experimental_listPrompts(options: MCPListPromptsOptions?) async throws -> ListPromptsResult
    func experimental_getPrompt(args: MCPGetPromptArgs) async throws -> GetPromptResult

    func onElicitationRequest(
        schema: Any.Type,
        handler: @escaping @Sendable (ElicitationRequest) async throws -> ElicitResult
    ) throws

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

public typealias MCPListToolsOptions = MCPListResourcesOptions

public struct MCPListResourcesOptions: Sendable {
    public let params: PaginatedRequest.PaginatedParams?
    public let options: RequestOptions?

    public init(params: PaginatedRequest.PaginatedParams? = nil, options: RequestOptions? = nil) {
        self.params = params
        self.options = options
    }
}

public struct MCPReadResourceArgs: Sendable {
    public let uri: String
    public let options: RequestOptions?

    public init(uri: String, options: RequestOptions? = nil) {
        self.uri = uri
        self.options = options
    }
}

public struct MCPListResourceTemplatesOptions: Sendable {
    public let options: RequestOptions?

    public init(options: RequestOptions? = nil) {
        self.options = options
    }
}

public struct MCPListPromptsOptions: Sendable {
    public let params: PaginatedRequest.PaginatedParams?
    public let options: RequestOptions?

    public init(params: PaginatedRequest.PaginatedParams? = nil, options: RequestOptions? = nil) {
        self.params = params
        self.options = options
    }
}

public struct MCPGetPromptArgs: Sendable {
    public let name: String
    public let arguments: [String: JSONValue]?
    public let options: RequestOptions?

    public init(
        name: String,
        arguments: [String: JSONValue]? = nil,
        options: RequestOptions? = nil
    ) {
        self.name = name
        self.arguments = arguments
        self.options = options
    }
}

public extension MCPClient {
    func tools() async throws -> [String: Tool] { try await tools(options: nil) }
    func listTools() async throws -> ListToolsResult { try await listTools(options: nil) }
    func listResources() async throws -> ListResourcesResult { try await listResources(options: nil) }
    func listResourceTemplates() async throws -> ListResourceTemplatesResult { try await listResourceTemplates(options: nil) }
    func experimental_listPrompts() async throws -> ListPromptsResult { try await experimental_listPrompts(options: nil) }
    func callTool(name: String, arguments: JSONValue? = nil) async throws -> CallToolResult {
        try await callTool(name: name, arguments: arguments, options: nil)
    }
    func toolsFromDefinitions(_ definitions: ListToolsResult) throws -> [String: Tool] {
        try toolsFromDefinitions(definitions, options: nil)
    }
    func complete(args: CompleteRequestParams) async throws -> CompleteResult { try await complete(args: args, options: nil) }
}

public extension Tool {
    func execute(input: JSONValue, options: ToolCallOptions? = nil) async throws -> ToolExecutionResult<JSONValue> {
        guard let execute else { throw MCPClientError(message: "Tool has no execute function") }
        return try await execute(input, options ?? ToolCallOptions(toolCallId: "", messages: []))
    }
}

// MARK: - Default implementation

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
internal final class DefaultMCPClient: MCPClient, @unchecked Sendable {
    private var transport: MCPTransport
    private let onUncaughtError: (@Sendable (Error) -> Void)?
    private let clientInfo: Configuration
    private let clientCapabilities: ClientCapabilities
    private let initializationOptions: RequestOptions?
    private let initialInitializeResult: InitializeResult?
    private let maxRetries: Int
    private var _initializeResult = InitializeResult(
        protocolVersion: LATEST_PROTOCOL_VERSION,
        capabilities: ServerCapabilities(),
        serverInfo: Configuration(name: "", version: "")
    )

    var initializeResult: InitializeResult { lock.withLock { _initializeResult } }
    var serverInfo: Configuration { initializeResult.serverInfo }
    var instructions: String? { initializeResult.instructions }

    private let lock = NSLock()
    private var requestMessageId: Int = 0
    private var responseHandlers: [Int: @Sendable (Result<JSONRPCResponse, Error>) -> Void] = [:]
    private var serverCapabilities: ServerCapabilities = ServerCapabilities()
    private var isClosed: Bool = true
    private var elicitationRequestHandler: (@Sendable (ElicitationRequest) async throws -> ElicitResult)?

    init(config: MCPClientConfig) throws {
        onUncaughtError = config.onUncaughtError
        clientInfo = Configuration(name: config.name, version: config.version)
        clientCapabilities = config.capabilities
        initializationOptions = config.initializationOptions
        initialInitializeResult = config.initialInitializeResult
        maxRetries = config.maxRetries
        guard maxRetries >= 0 else {
            throw MCPClientError(message: "maxRetries must be >= 0")
        }

        switch config.transport {
        case .config(let transportConfig):
            transport = try createMcpTransport(config: transportConfig)
        case .custom(let customTransport):
            transport = customTransport
        }

        transport.onclose = { [weak self] in
            self?.handleClose()
        }

        transport.onerror = { [weak self] error in
            self?.handleError(error)
        }

        transport.onmessage = { [weak self] message in
            guard let self else { return }

            switch message {
            case .request(let request):
                Task { [weak self] in
                    await self?.onRequestMessage(request)
                }

            case .notification:
                self.handleError(MCPClientError(message: "Unsupported message type"))

            case .response(let response):
                self.handleResponse(.success(response))

            case .error(let errorResponse):
                let error = MCPClientError(
                    message: errorResponse.error.message,
                    cause: errorResponse.error,
                    data: errorResponse.error.data,
                    code: errorResponse.error.code
                )
                self.handleErrorResponse(errorResponse, error: error)
            }
        }
    }

    func initialize() async throws {
        lock.withLock { isClosed = false }
        let interrupted = MCPAbortState()
        do {
            try await runMCPOperation(
                options: initializationOptions,
                timeoutMessage: { "MCP client initialization timed out after \($0)ms" },
                abortMessage: "MCP client initialization was aborted",
                onAbort: { interrupted.abort() }
            ) { [self] in
                try await transport.start()
                if let initialInitializeResult {
                    try applyInitializeResult(initialInitializeResult)
                    return
                }
                transport.setProtocolVersion(LATEST_PROTOCOL_VERSION)
                let result: InitializeResult = try await request(
                    method: "initialize",
                    additionalParams: [
                        "protocolVersion": .string(LATEST_PROTOCOL_VERSION),
                        "capabilities": try encodeToJSONValue(clientCapabilities),
                        "clientInfo": try encodeToJSONValue(clientInfo),
                    ]
                )
                try applyInitializeResult(result)
                try await sendNotification(method: "notifications/initialized")
            }
        } catch {
            handleClose()
            if interrupted.isAborted {
                Task { try? await transport.close(options: .init(signal: { true })) }
            } else {
                try? await transport.close(options: .init(signal: initializationOptions?.signal))
            }
            throw error
        }
    }

    private func applyInitializeResult(_ result: InitializeResult) throws {
        guard SUPPORTED_PROTOCOL_VERSIONS.contains(result.protocolVersion) else {
            throw MCPClientError(message: "Server's protocol version is not supported: \(result.protocolVersion)")
        }
        lock.withLock {
            _initializeResult = result
            serverCapabilities = result.capabilities
        }
        transport.setProtocolVersion(result.protocolVersion)
    }

    func close() async throws {
        let wasClosed = lock.withLock { isClosed }
        guard !wasClosed else { return }

        try await transport.close()
        handleClose()
    }

    func tools(options: MCPToolsOptions? = nil) async throws -> [String: Tool] {
        var definitions = try await listTools()
        var tools = definitions.tools
        while let cursor = definitions.nextCursor {
            definitions = try await listTools(params: .init(cursor: cursor))
            tools.append(contentsOf: definitions.tools)
        }
        return try toolsFromDefinitions(ListToolsResult(tools: tools), options: options)
    }

    func toolsFromDefinitions(_ definitions: ListToolsResult, options: MCPToolsOptions? = nil) throws -> [String: Tool] {
        let schemas = options?.schemas ?? .automatic
        var result: [String: Tool] = [:]
        for mcpTool in definitions.tools {
            let name = mcpTool.name

            if case .schemas(let schemaDict) = schemas {
                if schemaDict[name] == nil { continue }
            }

            let resolvedTitle = mcpTool.title ?? mcpTool.annotations?.title
            let outputSchema = outputSchemaForTool(named: name, schemas: schemas)
            var metadata: [String: JSONValue] = [
                "clientName": .string(clientInfo.name), "toolName": .string(name),
            ]
            if let resolvedTitle { metadata["title"] = .string(resolvedTitle) }
            if let annotations = mcpTool.annotations {
                metadata["annotations"] = try encodeToJSONValue(annotations)
            }
            if var app = try getMCPAppToolMeta(meta: mcpTool.meta), app["resourceUri"] != nil {
                app["mimeType"] = .string(MCP_APP_MIME_TYPE)
                metadata["app"] = .object(app)
            }

            let execute: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { [self] args, options in
                if let abortSignal = options.abortSignal, abortSignal() {
                    throw AbortError(message: "The operation was aborted")
                }

                let callResult: CallToolResult = try await self.callTool(
                    name: name,
                    args: args,
                    options: RequestOptions(signal: options.abortSignal)
                )

                if !callResult.isError, let outputSchema {
                    let extracted = try await self.extractStructuredContent(
                        callResult,
                        outputSchema: outputSchema,
                        toolName: name
                    )
                    return .value(extracted)
                }

                return .value(try self.callToolResultToJSON(callResult))
            }

            let tool: Tool
            switch schemas {
            case .automatic:
                let schema = normalizeToolInputSchema(mcpTool.inputSchema)
                tool = AISDKProviderUtils.dynamicTool(
                    description: mcpTool.description,
                    title: resolvedTitle,
                    _meta: mcpTool.meta,
                    metadata: metadata,
                    inputSchema: FlexibleSchema(jsonSchema(schema)),
                    execute: execute,
                    toModelOutput: Self.mcpToModelOutput
                )

            case .schemas(let schemaDict):
                guard let schemaDefinition = schemaDict[name] else { continue }
                tool = AISDKProviderUtils.tool(
                    description: mcpTool.description,
                    title: resolvedTitle,
                    _meta: mcpTool.meta,
                    metadata: metadata,
                    inputSchema: schemaDefinition.inputSchema,
                    execute: execute,
                    outputSchema: outputSchema,
                    toModelOutput: Self.mcpToModelOutput
                )
            }

            result[name] = tool
        }

        return result
    }

    func complete(args: CompleteRequestParams, options: RequestOptions? = nil) async throws -> CompleteResult {
        try await request(method: "completion/complete", params: encodeToJSONValue(args), options: options)
    }

    func listResources(options: MCPListResourcesOptions? = nil) async throws -> ListResourcesResult {
        try await listResourcesInternal(params: options?.params, options: options?.options)
    }

    func readResource(args: MCPReadResourceArgs) async throws -> ReadResourceResult {
        try await readResourceInternal(uri: args.uri, options: args.options)
    }

    func listResourceTemplates(options: MCPListResourceTemplatesOptions? = nil) async throws -> ListResourceTemplatesResult {
        try await listResourceTemplatesInternal(options: options?.options)
    }

    func experimental_listPrompts(options: MCPListPromptsOptions? = nil) async throws -> ListPromptsResult {
        try await listPromptsInternal(params: options?.params, options: options?.options)
    }

    func experimental_getPrompt(args: MCPGetPromptArgs) async throws -> GetPromptResult {
        try await getPromptInternal(name: args.name, args: args.arguments, options: args.options)
    }

    func onElicitationRequest(
        schema: Any.Type,
        handler: @escaping @Sendable (ElicitationRequest) async throws -> ElicitResult
    ) throws {
        guard schema == ElicitationRequestSchema.self else {
            throw MCPClientError(
                message: "Unsupported request schema. Only ElicitationRequestSchema is supported."
            )
        }

        lock.withLock { elicitationRequestHandler = handler }
    }

    // MARK: - Requests

    private func assertCapability(method: String) throws {
        switch method {
        case "initialize":
            break
        case "tools/list", "tools/call":
            let hasTools = lock.withLock { serverCapabilities.tools != nil }
            guard hasTools else {
                throw MCPClientError(message: "Server does not support tools")
            }
        case "completion/complete":
            guard lock.withLock({ serverCapabilities.completions != nil }) else {
                throw MCPClientError(message: "Server does not support completions")
            }
        case "resources/list", "resources/read", "resources/templates/list":
            let hasResources = lock.withLock { serverCapabilities.resources != nil }
            guard hasResources else {
                throw MCPClientError(message: "Server does not support resources")
            }
        case "prompts/list", "prompts/get":
            let hasPrompts = lock.withLock { serverCapabilities.prompts != nil }
            guard hasPrompts else {
                throw MCPClientError(message: "Server does not support prompts")
            }
        default:
            throw MCPClientError(message: "Unsupported method: \(method)")
        }
    }

    private func request<T: Decodable & Sendable>(
        method: String,
        params: JSONValue? = nil,
        additionalParams: [String: JSONValue] = [:],
        options: RequestOptions? = nil
    ) async throws -> T {
        guard !lock.withLock({ isClosed }) else {
            throw MCPClientError(message: "Attempted to send a request from a closed client")
        }
        try assertCapability(method: method)
        if Task.isCancelled || options?.signal?() == true {
            throw MCPClientError(message: "Request was aborted", cause: Task.isCancelled ? CancellationError() : nil)
        }
        let messageId = lock.withLock {
            let id = requestMessageId
            requestMessageId += 1
            return id
        }
        var requestParams: [String: JSONValue] = [:]
        if case .object(let object) = params { requestParams = object }
        requestParams.merge(additionalParams) { _, value in value }
        let message = JSONRPCRequest(
            id: .int(messageId), method: method,
            params: requestParams.isEmpty ? nil : .object(requestParams)
        )
        let pending = MCPOperation<JSONRPCResponse>()
        let interrupted = MCPAbortState()
        defer {
            _ = lock.withLock { responseHandlers.removeValue(forKey: messageId) }
        }
        let response = try await runMCPOperation(options: options, onAbort: { interrupted.abort() }) { [self] in
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pending.install(continuation)
                    let closed = lock.withLock {
                        guard !isClosed, !pending.isFinished else { return true }
                        responseHandlers[messageId] = { pending.finish($0) }
                        return false
                    }
                    guard !closed else {
                        pending.finish(.failure(MCPClientError(message: "Connection closed")))
                        return
                    }
                    pending.own(Task {
                        do { try await transport.send(message: .request(message), options: .init(signal: { interrupted.isAborted || options?.signal?() == true })) }
                        catch { pending.finish(.failure(error)) }
                    }, cancelOnSuccess: false)
                }
            } onCancel: {
                interrupted.abort()
                pending.finish(.failure(MCPClientError(message: "Request was aborted", cause: CancellationError())))
            }
        }
        do {
            return try decodeResult(response.result, as: T.self)
        } catch {
            throw MCPClientError(message: "Failed to parse server response", cause: error)
        }
    }

    func listTools(options: MCPListToolsOptions?) async throws -> ListToolsResult {
        try await listTools(params: options?.params, options: options?.options)
    }

    private func listTools(
        params: PaginatedRequest.PaginatedParams? = nil,
        options: RequestOptions? = nil
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
            options: options
        )
    }

    private func callTool(
        name: String,
        args: JSONValue,
        options: RequestOptions?
    ) async throws -> CallToolResult {
        try await callTool(name: name, arguments: args, options: options)
    }

    func callTool(name: String, arguments: JSONValue?, options: RequestOptions?) async throws -> CallToolResult {
        let retry = retryWithExponentialBackoff(
            maxRetries: maxRetries,
            abortSignal: options?.signal,
            shouldRetry: { [self] in isRetryableToolCallError($0) },
            createRetryError: { message, _, errors in
                MCPClientError(message: message, cause: errors.last)
            }
        )
        return try await retry { [self] in
            try await request(
                method: "tools/call",
                additionalParams: ["name": .string(name), "arguments": arguments ?? .object([:])],
                options: options
            )
        }
    }

    private func isRetryableToolCallError(_ error: Error) -> Bool {
        let status = (error as? MCPClientError)?.statusCode ?? (error as? APICallError)?.statusCode
        if let status { return [408, 409, 429].contains(status) || status >= 500 }
        if let error = error as? MCPClientError, error.code != nil { return false }
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain {
            return [POSIXErrorCode.EPIPE, .ECONNRESET, .ECONNREFUSED, .ETIMEDOUT].contains { Int($0.rawValue) == error.code }
        }
        return error.domain == NSURLErrorDomain && [NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut].contains(error.code)

    }

    private func listResourcesInternal(
        params: PaginatedRequest.PaginatedParams? = nil,
        options: RequestOptions? = nil
    ) async throws -> ListResourcesResult {
        var additionalParams: [String: JSONValue] = [:]
        if let cursor = params?.cursor {
            additionalParams["cursor"] = .string(cursor)
        }
        if let meta = params?.meta {
            additionalParams["_meta"] = .object(meta)
        }

        return try await request(
            method: "resources/list",
            params: nil,
            additionalParams: additionalParams,
            options: options
        )
    }

    private func readResourceInternal(
        uri: String,
        options: RequestOptions?
    ) async throws -> ReadResourceResult {
        return try await request(
            method: "resources/read",
            params: nil,
            additionalParams: ["uri": .string(uri)],
            options: options
        )
    }

    private func listResourceTemplatesInternal(
        options: RequestOptions? = nil
    ) async throws -> ListResourceTemplatesResult {
        return try await request(
            method: "resources/templates/list",
            params: nil,
            additionalParams: [:],
            options: options
        )
    }

    private func listPromptsInternal(
        params: PaginatedRequest.PaginatedParams? = nil,
        options: RequestOptions? = nil
    ) async throws -> ListPromptsResult {
        var additionalParams: [String: JSONValue] = [:]
        if let cursor = params?.cursor {
            additionalParams["cursor"] = .string(cursor)
        }
        if let meta = params?.meta {
            additionalParams["_meta"] = .object(meta)
        }

        return try await request(
            method: "prompts/list",
            params: nil,
            additionalParams: additionalParams,
            options: options
        )
    }

    private func getPromptInternal(
        name: String,
        args: [String: JSONValue]?,
        options: RequestOptions?
    ) async throws -> GetPromptResult {
        var additionalParams: [String: JSONValue] = ["name": .string(name)]
        if let args {
            additionalParams["arguments"] = .object(args)
        }

        return try await request(
            method: "prompts/get",
            params: nil,
            additionalParams: additionalParams,
            options: options
        )
    }

    private func sendNotification(method: String, params: JSONValue? = nil) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        try await transport.send(message: .notification(notification))
    }

    // MARK: - Tool conversion

    private func outputSchemaForTool(named name: String, schemas: ToolSchemas) -> FlexibleSchema<JSONValue>? {
        switch schemas {
        case .automatic:
            return nil
        case .schemas(let dict):
            return dict[name]?.outputSchema
        }
    }

    private func normalizeToolInputSchema(_ inputSchema: JSONValue) -> JSONValue {
        guard case .object(var dict) = inputSchema else {
            return inputSchema
        }

        if dict["properties"] == nil {
            dict["properties"] = .object([:])
        }

        dict["additionalProperties"] = .bool(false)
        return .object(dict)
    }

    private func extractStructuredContent(
        _ result: CallToolResult,
        outputSchema: FlexibleSchema<JSONValue>,
        toolName: String
    ) async throws -> JSONValue {
        if let structuredContent = structuredContent(from: result) {
            let validation = await safeValidateTypes(
                ValidateTypesOptions(value: structuredContent, schema: outputSchema)
            )

            switch validation {
            case .success(let value, _):
                return value
            case .failure(let error, _):
                throw MCPClientError(
                    message: "Tool \"\(toolName)\" returned structuredContent that does not match the expected outputSchema",
                    cause: error
                )
            }
        }

        if let text = firstTextContent(from: result) {
            let parseResult = await safeParseJSON(
                ParseJSONWithSchemaOptions(text: text, schema: outputSchema)
            )

            switch parseResult {
            case .success(let value, _):
                return value
            case .failure(let error, _):
                throw MCPClientError(
                    message: "Tool \"\(toolName)\" returned content that does not match the expected outputSchema",
                    cause: error
                )
            }
        }

        throw MCPClientError(
            message: "Tool \"\(toolName)\" did not return structuredContent or parseable text content"
        )
    }

    private func structuredContent(from result: CallToolResult) -> JSONValue? {
        switch result {
        case .content(_, let structuredContent, _, _):
            if structuredContent == .null { return nil }
            return structuredContent
        case .toolResult:
            return nil
        case .raw(let raw):
            guard case .object(let obj) = raw else { return nil }
            if case .null = obj["structuredContent"] { return nil }
            return obj["structuredContent"]
        }
    }

    private func firstTextContent(from result: CallToolResult) -> String? {
        switch result {
        case .content(let content, _, _, _):
            for part in content {
                if case .text(let text) = part { return text.text }
                if case .unknown(.object(let raw)) = part, raw["type"] == .string("text"), case .string(let text) = raw["text"] { return text }
            }
            return nil
        case .toolResult:
            return nil
        case .raw(let raw):
            guard case .object(let obj) = raw,
                  case .array(let contentArray) = obj["content"] else {
                return nil
            }

            for entry in contentArray {
                guard case .object(let entryObj) = entry else { continue }
                guard case .string(let type) = entryObj["type"], type == "text" else { continue }
                if case .string(let text) = entryObj["text"] {
                    return text
                }
            }

            return nil
        }
    }

    // MARK: - toModelOutput

    private static func mcpToModelOutput(_ output: JSONValue) -> LanguageModelV3ToolResultOutput {
        guard case .object(let obj) = output,
              case .array(let content) = obj["content"] else {
            return .json(value: output)
        }

        let converted: [LanguageModelV3ToolResultContentPart] = content.map { part in
            guard case .object(let partObj) = part,
                  case .string(let type) = partObj["type"] else {
                return .text(text: jsonStringify(part))
            }

            if type == "text", case .string(let text) = partObj["text"] {
                return .text(text: text)
            }

            if type == "image",
               case .string(let data) = partObj["data"],
               case .string(let mimeType) = partObj["mimeType"] {
                return .media(data: data, mediaType: mimeType)
            }

            return .text(text: jsonStringify(part))
        }

        return .content(value: converted)
    }

    private static func jsonStringify(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    private static func jsonStringify<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    // MARK: - Elicitation

    private func onRequestMessage(_ request: JSONRPCRequest) async {
        do {
            if request.method == "ping" {
                try await transport.send(message: .response(JSONRPCResponse(id: request.id, result: .object([:]))))
                return
            }
            if request.method != "elicitation/create" {
                try await transport.send(
                    message: .error(
                        JSONRPCError(
                            id: request.id,
                            error: JSONRPCErrorObject(
                                code: -32601,
                                message: "Unsupported request method: \(request.method)"
                            )
                        )
                    )
                )
                return
            }

            guard let handler = lock.withLock({ elicitationRequestHandler }) else {
                try await transport.send(
                    message: .error(
                        JSONRPCError(
                            id: request.id,
                            error: JSONRPCErrorObject(
                                code: -32601,
                                message: "No elicitation handler registered on client"
                            )
                        )
                    )
                )
                return
            }

            guard let params = request.params else {
                try await transport.send(
                    message: .error(
                        JSONRPCError(
                            id: request.id,
                            error: JSONRPCErrorObject(
                                code: -32602,
                                message: "Invalid elicitation request: missing params",
                                data: .array([])
                            )
                        )
                    )
                )
                return
            }

            let parsedParams: ElicitationRequestParams
            do {
                let data = try JSONSerialization.data(withJSONObject: params.toAnyObject(), options: [])
                parsedParams = try JSONDecoder().decode(ElicitationRequestParams.self, from: data)
            } catch {
                try await transport.send(
                    message: .error(
                        JSONRPCError(
                            id: request.id,
                            error: JSONRPCErrorObject(
                                code: -32602,
                                message: "Invalid elicitation request: \(error.localizedDescription)",
                                data: .array([])
                            )
                        )
                    )
                )
                return
            }

            do {
                let elicitationRequest = ElicitationRequest(method: request.method, params: parsedParams)
                let result = try await handler(elicitationRequest)
                let validatedResult = try encodeToJSONValue(result)
                try await transport.send(
                    message: .response(
                        JSONRPCResponse(id: request.id, result: validatedResult)
                    )
                )
            } catch {
                let errorMessage: String = {
                    if let error = error as? LocalizedError, let description = error.errorDescription {
                        return description
                    }
                    return (error as NSError).localizedDescription
                }()

                try await transport.send(
                    message: .error(
                        JSONRPCError(
                            id: request.id,
                            error: JSONRPCErrorObject(
                                code: -32603,
                                message: errorMessage
                            )
                        )
                    )
                )
                handleError(error)
            }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Decoding helpers

    private func decodeResult<T: Decodable>(_ result: JSONValue, as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: result.toAnyObject(), options: [])
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: jsonObject)
    }

    private func callToolResultToJSON(_ result: CallToolResult) throws -> JSONValue {
        let data = try JSONEncoder().encode(result)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        var jsonValueResult = try jsonValue(from: jsonObject)

        // Upstream (zod) applies a default for `isError` and retains it in the parsed object.
        // Mirror that by ensuring `isError` is always present for the content variant.
        if case .content(_, _, let isError, _) = result, case .object(var dict) = jsonValueResult {
            dict["isError"] = .bool(isError)
            jsonValueResult = .object(dict)
        }

        return jsonValueResult
    }

    // MARK: - Event handlers

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
        if let onUncaughtError {
            onUncaughtError(error)
        }
    }

    private func handleResponse(_ result: Result<JSONRPCResponse, Error>) {
        guard case .success(let response) = result else {
            if case .failure(let error) = result {
                handleError(error)
            }
            return
        }

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

        guard let handler else {
            handleError(MCPClientError(
                message: "Protocol error: Received a response for an unknown message ID: \(Self.jsonStringify(response))"
            ))
            return
        }

        handler(result)
    }

    private func handleErrorResponse(_ response: JSONRPCError, error: MCPClientError) {
        guard let id = response.id else {
            handleError(MCPClientError(message: "Protocol error: Received a response without a message ID: \(Self.jsonStringify(response))"))
            return
        }
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

        guard let handler else {
            handleError(MCPClientError(
                message: "Protocol error: Received a response for an unknown message ID: \(Self.jsonStringify(response))"
            ))
            return
        }

        handler(.failure(error))
    }
}

// MARK: - JSONValue helpers

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
