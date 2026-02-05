/**
 Mock MCP transport for testing.
 
 Port of `packages/mcp/src/tool/mock-mcp-transport.ts`.
 Upstream commit: f3a72bc2a
 
 This transport simulates an MCP server for testing purposes without requiring
 a real MCP server connection.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

private let defaultTools: [MCPTool] = [
    MCPTool(
        name: "mock-tool",
        description: "A mock tool for testing",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "foo": .object(["type": .string("string")])
            ]),
        ])
    ),
    MCPTool(
        name: "mock-tool-no-args",
        description: "A mock tool for testing",
        inputSchema: .object([
            "type": .string("object")
        ])
    ),
]

private let defaultResources: [MCPResource] = [
    MCPResource(
        uri: "file:///mock/resource.txt",
        name: "resource.txt",
        description: "Mock resource",
        mimeType: "text/plain"
    )
]

private let defaultPrompts: [MCPPrompt] = [
    MCPPrompt(
        name: "code_review",
        title: "Request Code Review",
        description: "Asks the LLM to analyze code quality and suggest improvements",
        arguments: [
            PromptArgument(name: "code", description: "The code to review", required: true)
        ]
    )
]

private let defaultPromptResults: [String: GetPromptResult] = [
    "code_review": GetPromptResult(
        description: "Code review prompt",
        messages: [
            MCPPromptMessage(
                role: .user,
                content: .text(
                    ToolContent.TextContent(
                        text: "Please review this code:\nfunction add(a, b) { return a + b; }"
                    )
                )
            )
        ]
    )
]

private let defaultResourceTemplates: [ResourceTemplate] = [
    ResourceTemplate(
        uriTemplate: "file:///{path}",
        name: "mock-template",
        description: "Mock template"
    )
]

private let defaultResourceContents: [ResourceContents] = [
    ResourceContents.text(
        uri: "file:///mock/resource.txt",
        name: nil,
        title: nil,
        mimeType: "text/plain",
        text: "Mock resource content"
    )
]

public final class MockMCPTransport: MCPTransport, @unchecked Sendable {
    private let tools: [MCPTool]
    private let resources: [MCPResource]
    private let resourceTemplates: [ResourceTemplate]
    private let resourceContents: [ResourceContents]
    private let prompts: [MCPPrompt]
    private let promptResults: [String: GetPromptResult]
    private let failOnInvalidToolParams: Bool
    private let initializeResult: JSONValue?
    private let sendError: Bool
    private let toolCallResults: [String: CallToolResult]

    private let sentMessagesLock = NSLock()
    private var _sentMessages: [JSONRPCMessage] = []

    public var onmessage: (@Sendable (JSONRPCMessage) -> Void)?
    public var onclose: (@Sendable () -> Void)?
    public var onerror: (@Sendable (Error) -> Void)?

    public var sentMessages: [JSONRPCMessage] {
        sentMessagesLock.withLock { _sentMessages }
    }

    public init(
        overrideTools: [MCPTool]? = nil,
        resources: [MCPResource]? = nil,
        prompts: [MCPPrompt]? = nil,
        promptResults: [String: GetPromptResult]? = nil,
        resourceTemplates: [ResourceTemplate]? = nil,
        resourceContents: [ResourceContents]? = nil,
        failOnInvalidToolParams: Bool = false,
        initializeResult: JSONValue? = nil,
        sendError: Bool = false,
        toolCallResults: [String: CallToolResult] = [:]
    ) {
        self.tools = overrideTools ?? defaultTools
        self.resources = resources ?? defaultResources
        self.prompts = prompts ?? defaultPrompts
        self.promptResults = promptResults ?? defaultPromptResults
        self.resourceTemplates = resourceTemplates ?? defaultResourceTemplates
        self.resourceContents = resourceContents ?? defaultResourceContents
        self.failOnInvalidToolParams = failOnInvalidToolParams
        self.initializeResult = initializeResult
        self.sendError = sendError
        self.toolCallResults = toolCallResults
    }

    public func start() async throws {
        if sendError {
            onerror?(
                NSError(
                    domain: "UnknownError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown error"]
                )
            )
        }
    }

    public func send(message: JSONRPCMessage) async throws {
        sentMessagesLock.withLock { _sentMessages.append(message) }
        if case .request(let request) = message {
            try await handleRequest(request)
        }
    }

    public func close() async throws {
        onclose?()
    }

    // MARK: - Private

    private func handleRequest(_ request: JSONRPCRequest) async throws {
        switch request.method {
        case "initialize":
            try await delay(10)
            let result = initializeResult ?? defaultInitializeResult()
            onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))

        case "resources/list":
            try await delay(10)
            let result = try encodeToJSONValue(
                ListResourcesResult(resources: resources)
            )
            onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))

        case "resources/read":
            try await delay(10)
            try await handleReadResource(request)

        case "resources/templates/list":
            try await delay(10)
            let result = try encodeToJSONValue(
                ListResourceTemplatesResult(resourceTemplates: resourceTemplates)
            )
            onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))

        case "prompts/list":
            try await delay(10)
            let result = try encodeToJSONValue(
                ListPromptsResult(prompts: prompts)
            )
            onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))

        case "prompts/get":
            try await delay(10)
            try await handleGetPrompt(request)

        case "tools/list":
            try await delay(10)
            if tools.isEmpty {
                onmessage?(
                    .error(
                        JSONRPCError(
                            id: request.id,
                            error: JSONRPCErrorObject(code: -32000, message: "Method not supported")
                        )
                    )
                )
                return
            }

            let result = try encodeToJSONValue(
                ListToolsResult(tools: tools)
            )
            onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))

        case "tools/call":
            try await delay(10)
            try await handleToolCall(request)

        default:
            break
        }
    }

    private func handleReadResource(_ request: JSONRPCRequest) async throws {
        guard let params = request.params, case .object(let dict) = params else { return }
        guard case .string(let uri) = dict["uri"] else { return }

        let contents = resourceContents.filter { $0.uri == uri }
        guard !contents.isEmpty else {
            onmessage?(
                .error(
                    JSONRPCError(
                        id: request.id,
                        error: JSONRPCErrorObject(
                            code: -32002,
                            message: "Resource \(uri) not found"
                        )
                    )
                )
            )
            return
        }

        let result = try encodeToJSONValue(
            ReadResourceResult(contents: contents)
        )
        onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))
    }

    private func handleGetPrompt(_ request: JSONRPCRequest) async throws {
        guard let params = request.params, case .object(let dict) = params else { return }
        guard case .string(let name) = dict["name"] else { return }

        guard let promptResult = promptResults[name] else {
            onmessage?(
                .error(
                    JSONRPCError(
                        id: request.id,
                        error: JSONRPCErrorObject(
                            code: -32602,
                            message: "Invalid params: Unknown prompt \(name)"
                        )
                    )
                )
            )
            return
        }

        let result = try encodeToJSONValue(promptResult)
        onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))
    }

    private func handleToolCall(_ request: JSONRPCRequest) async throws {
        guard let params = request.params, case .object(let dict) = params else { return }
        guard case .string(let toolName) = dict["name"] else { return }
        let arguments = dict["arguments"]

        guard let tool = tools.first(where: { $0.name == toolName }) else {
            onmessage?(
                .error(
                    JSONRPCError(
                        id: request.id,
                        error: JSONRPCErrorObject(
                            code: -32601,
                            message: "Tool \(toolName) not found",
                            data: .object([
                                "availableTools": .array(tools.map { .string($0.name) }),
                                "requestedTool": .string(toolName),
                            ])
                        )
                    )
                )
            )
            return
        }

        if failOnInvalidToolParams {
            onmessage?(
                .error(
                    JSONRPCError(
                        id: request.id,
                        error: JSONRPCErrorObject(
                            code: -32602,
                            message: "Invalid tool inputSchema: \(stringifyJSONValue(arguments))",
                            data: .object([
                                "expectedSchema": tool.inputSchema,
                                "receivedArguments": arguments ?? .null,
                            ])
                        )
                    )
                )
            )
            return
        }

        if let customResult = toolCallResults[toolName] {
            let result = try encodeToJSONValue(customResult)
            onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))
            return
        }

        let result = try encodeToJSONValue(
            CallToolResult.content(
                content: [
                    .text(ToolContent.TextContent(text: "Mock tool call result"))
                ],
                structuredContent: nil,
                isError: false,
                meta: nil
            )
        )

        onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))
    }

    private func defaultInitializeResult() -> JSONValue {
        var capabilities: [String: JSONValue] = [:]
        if !tools.isEmpty { capabilities["tools"] = .object([:]) }
        if !resources.isEmpty { capabilities["resources"] = .object([:]) }
        if !prompts.isEmpty { capabilities["prompts"] = .object([:]) }

        return .object([
            "protocolVersion": .string(LATEST_PROTOCOL_VERSION),
            "serverInfo": .object([
                "name": .string("mock-mcp-server"),
                "version": .string("1.0.0"),
            ]),
            "capabilities": .object(capabilities),
        ])
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func stringifyJSONValue(_ value: JSONValue?) -> String {
        guard let value else { return "null" }
        if let data = try? JSONEncoder().encode(value),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "null"
    }
}

private extension ResourceContents {
    var uri: String {
        switch self {
        case .text(let uri, _, _, _, _):
            return uri
        case .blob(let uri, _, _, _, _):
            return uri
        }
    }
}
