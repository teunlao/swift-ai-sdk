/**
 Mock MCP transport for testing.

 Port of `@ai-sdk/ai/src/tool/mcp/mock-mcp-transport.ts`.

 This transport simulates an MCP server for testing purposes without requiring
 a real MCP server connection.
 */

import AISDKProvider
import AISDKProviderUtils
import Foundation

/// Default tools provided by the mock transport
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

/// Mock MCP transport for testing.
///
/// Simulates an MCP server by responding to standard MCP requests
/// (initialize, tools/list, tools/call) with configurable responses.
public final class MockMCPTransport: MCPTransport, @unchecked Sendable {
    private let tools: [MCPTool]
    private let failOnInvalidToolParams: Bool
    private let initializeResult: JSONValue?
    private let sendError: Bool

    public var onmessage: (@Sendable (JSONRPCMessage) -> Void)?
    public var onclose: (@Sendable () -> Void)?
    public var onerror: (@Sendable (Error) -> Void)?

    public init(
        overrideTools: [MCPTool]? = nil,
        failOnInvalidToolParams: Bool = false,
        initializeResult: JSONValue? = nil,
        sendError: Bool = false
    ) {
        self.tools = overrideTools ?? defaultTools
        self.failOnInvalidToolParams = failOnInvalidToolParams
        self.initializeResult = initializeResult
        self.sendError = sendError
    }

    public func start() async throws {
        if sendError {
            onerror?(
                NSError(
                    domain: "UnknownError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown error"]
                ))
        }
    }

    public func send(message: JSONRPCMessage) async throws {
        // Mock server response implementation - extend as necessary:
        switch message {
        case .request(let request):
            try await handleRequest(request)
        default:
            // Ignore other message types (notifications, responses, errors)
            break
        }
    }

    public func close() async throws {
        onclose?()
    }

    // MARK: - Private Methods

    private func handleRequest(_ request: JSONRPCRequest) async throws {
        switch request.method {
        case "initialize":
            try await delay(10)
            let result =
                initializeResult
                ?? .object([
                    "protocolVersion": .string("2025-06-18"),
                    "serverInfo": .object([
                        "name": .string("mock-mcp-server"),
                        "version": .string("1.0.0"),
                    ]),
                    "capabilities": .object(
                        tools.isEmpty ? [:] : ["tools": .object([:])]
                    ),
                ])
            onmessage?(.response(JSONRPCResponse(id: request.id, result: result)))

        case "tools/list":
            try await delay(10)
            if tools.isEmpty {
                onmessage?(
                    .error(
                        JSONRPCError(
                            id: request.id,
                            error: JSONRPCErrorObject(
                                code: -32000,
                                message: "Method not supported"
                            )
                        )))
                return
            }

            // Convert MCPTool array to JSONValue
            let toolsArray: [JSONValue] = tools.map { tool in
                var toolDict: [String: JSONValue] = [
                    "name": .string(tool.name),
                    "inputSchema": tool.inputSchema,
                ]
                if let description = tool.description {
                    toolDict["description"] = .string(description)
                }
                return .object(toolDict)
            }

            onmessage?(
                .response(
                    JSONRPCResponse(
                        id: request.id,
                        result: .object(["tools": .array(toolsArray)])
                    )))

        case "tools/call":
            try await delay(10)
            try await handleToolCall(request)

        default:
            // Unknown method - ignore
            break
        }
    }

    private func handleToolCall(_ request: JSONRPCRequest) async throws {
        // Extract tool name and arguments from request params
        // MCP spec: params should have 'name' and 'arguments' fields
        guard let params = request.params, case .object(let paramDict) = params else {
            return
        }

        // Extract name and arguments fields
        guard case .string(let toolName) = paramDict["name"] else {
            return
        }

        let arguments = paramDict["arguments"]
        try await handleToolCallWithName(toolName, request: request, arguments: arguments)
    }

    private func handleToolCallWithName(
        _ toolName: String, request: JSONRPCRequest, arguments: JSONValue?
    ) async throws {
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
                    )))
            return
        }

        if failOnInvalidToolParams {
            let argumentsStr: String
            if let args = arguments {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(args),
                    let str = String(data: data, encoding: .utf8)
                {
                    argumentsStr = str
                } else {
                    argumentsStr = "null"
                }
            } else {
                argumentsStr = "null"
            }

            onmessage?(
                .error(
                    JSONRPCError(
                        id: request.id,
                        error: JSONRPCErrorObject(
                            code: -32602,
                            message: "Invalid tool inputSchema: \(argumentsStr)",
                            data: .object([
                                "expectedSchema": tool.inputSchema,
                                "receivedArguments": arguments ?? .null,
                            ])
                        )
                    )))
            return
        }

        onmessage?(
            .response(
                JSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string("Mock tool call result"),
                            ])
                        ])
                    ])
                )))
    }
}

// MARK: - JSONValue Conversion Helper

extension JSONValue {
    init(_ value: Any) {
        if let dict = value as? [String: Any] {
            var result: [String: JSONValue] = [:]
            for (key, val) in dict {
                result[key] = JSONValue(val)
            }
            self = .object(result)
        } else if let array = value as? [Any] {
            self = .array(array.map { JSONValue($0) })
        } else if let string = value as? String {
            self = .string(string)
        } else if let int = value as? Int {
            self = .number(Double(int))
        } else if let double = value as? Double {
            self = .number(double)
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else {
            self = .null
        }
    }
}
