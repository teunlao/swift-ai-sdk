/**
 Tests for MCPClient.
 
 Port of `packages/mcp/src/tool/mcp-client.test.ts`.
 */

import Foundation
import Testing

@testable import SwiftAISDK
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("MCPClient")
struct MCPClientTests {

    @Test("should return AI SDK compatible tool set")
    func toolSetDynamicTools() async throws {
        let transport = MockMCPTransport()
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        #expect(tools["mock-tool"] != nil)

        let tool = try #require(tools["mock-tool"])
        #expect(tool.type == .dynamic)

        let jsonSchema = try await tool.inputSchema.resolve().jsonSchema()
        #expect(
            jsonSchema == .object([
                "type": .string("object"),
                "properties": .object([
                    "foo": .object(["type": .string("string")]),
                ]),
                "additionalProperties": .bool(false),
            ])
        )

        let output = try await tool.execute!(
            .object(["foo": .string("bar")]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        #expect(
            output == .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Mock tool call result"),
                    ]),
                ]),
                "isError": .bool(false),
            ])
        )
    }

    @Test("should support zero-argument tools")
    func zeroArgumentTools() async throws {
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(MockMCPTransport()))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        let tool = try #require(tools["mock-tool-no-args"])

        let jsonSchema = try await tool.inputSchema.resolve().jsonSchema()
        #expect(
            jsonSchema == .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false),
            ])
        )

        let output = try await tool.execute!(
            .object([:]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        #expect(
            output == .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Mock tool call result"),
                    ]),
                ]),
                "isError": .bool(false),
            ])
        )
    }

    @Test("should convert MCP image content to AI SDK format via toModelOutput")
    func toModelOutputImage() async throws {
        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "get-image",
                    description: "Returns an image",
                    inputSchema: .object(["type": .string("object")])
                ),
            ],
            toolCallResults: [
                "get-image": .content(
                    content: [
                        .image(.init(
                            data: "base64data",
                            mimeType: "image/png"
                        )),
                    ],
                    structuredContent: nil,
                    isError: false,
                    meta: nil
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        let tool = try #require(tools["get-image"])

        let output = try await tool.execute!(
            .object([:]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        let modelOutput = tool.toModelOutput?(output)
        #expect(modelOutput == .content(value: [
            .media(data: "base64data", mediaType: "image/png"),
        ]))
    }

    @Test("should convert MCP text content to AI SDK format via toModelOutput")
    func toModelOutputText() async throws {
        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "get-text",
                    description: "Returns text",
                    inputSchema: .object(["type": .string("object")])
                ),
            ],
            toolCallResults: [
                "get-text": .content(
                    content: [
                        .text(.init(text: "Hello world")),
                    ],
                    structuredContent: nil,
                    isError: false,
                    meta: nil
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        let tool = try #require(tools["get-text"])

        let output = try await tool.execute!(
            .object([:]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        let modelOutput = tool.toModelOutput?(output)
        #expect(modelOutput == .content(value: [
            .text(text: "Hello world"),
        ]))
    }

    @Test("should convert mixed MCP content to AI SDK format via toModelOutput")
    func toModelOutputMixed() async throws {
        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "get-mixed",
                    description: "Returns mixed content",
                    inputSchema: .object(["type": .string("object")])
                ),
            ],
            toolCallResults: [
                "get-mixed": .content(
                    content: [
                        .text(.init(text: "Here is an image:")),
                        .image(.init(data: "base64data", mimeType: "image/png")),
                    ],
                    structuredContent: nil,
                    isError: false,
                    meta: nil
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        let tool = try #require(tools["get-mixed"])

        let output = try await tool.execute!(
            .object([:]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        let modelOutput = tool.toModelOutput?(output)
        #expect(modelOutput == .content(value: [
            .text(text: "Here is an image:"),
            .media(data: "base64data", mediaType: "image/png"),
        ]))
    }

    @Test("should fallback to JSON for unknown content types via toModelOutput")
    func toModelOutputUnknownContentPart() async throws {
        let unknownPart: ToolContent = .unknown(
            .object([
                "type": .string("custom"),
                "data": .object([
                    "foo": .string("bar"),
                ]),
            ])
        )

        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "get-unknown",
                    description: "Returns unknown content",
                    inputSchema: .object(["type": .string("object")])
                ),
            ],
            toolCallResults: [
                "get-unknown": .content(
                    content: [unknownPart],
                    structuredContent: nil,
                    isError: false,
                    meta: nil
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        let tool = try #require(tools["get-unknown"])

        let output = try await tool.execute!(
            .object([:]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        let modelOutput = tool.toModelOutput?(output)

        guard let modelOutput, case .content(let parts, _) = modelOutput else {
            Issue.record("Expected content output")
            return
        }

        #expect(parts.count == 1)
        if case .text(let text) = parts[0] {
            // Ensure it is a JSON string representation of the part.
            #expect(text.contains("\"type\""))
            #expect(text.contains("\"custom\""))
            #expect(text.contains("\"foo\""))
            #expect(text.contains("\"bar\""))
        } else {
            Issue.record("Expected text fallback for unknown content type")
        }
    }

    @Test("should fallback to JSON when result has no content array via toModelOutput")
    func toModelOutputRawResult() async throws {
        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "get-raw",
                    description: "Returns raw result",
                    inputSchema: .object(["type": .string("object")])
                ),
            ],
            toolCallResults: [
                "get-raw": .raw(
                    .object([
                        "value": .number(42),
                        "isError": .bool(false),
                    ])
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        let tool = try #require(tools["get-raw"])

        let output = try await tool.execute!(
            .object([:]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        let modelOutput = tool.toModelOutput?(output)
        #expect(modelOutput == .json(value: output))
    }

    @Test("should expose _meta field from MCP tool definition")
    func toolMeta() async throws {
        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "tool-with-meta",
                    description: "A tool with metadata",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "input": .object(["type": .string("string")]),
                        ]),
                    ]),
                    meta: [
                        "openai/outputTemplate": .string("{{result}}"),
                    ]
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        let tool = try #require(tools["tool-with-meta"])

        #expect(tool._meta?["openai/outputTemplate"] == .string("{{result}}"))
    }

    @Test("should list resources from the server")
    func listResources() async throws {
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(MockMCPTransport()))
        )
        defer { Task { try? await client.close() } }

        let resources = try await client.listResources(options: nil)
        #expect(resources.resources.count == 1)
        #expect(resources.resources[0].uri == "file:///mock/resource.txt")
        #expect(resources.resources[0].name == "resource.txt")
        #expect(resources.resources[0].description == "Mock resource")
        #expect(resources.resources[0].mimeType == "text/plain")
    }

    @Test("should read resource contents")
    func readResource() async throws {
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(MockMCPTransport()))
        )
        defer { Task { try? await client.close() } }

        let result = try await client.readResource(
            args: MCPReadResourceArgs(uri: "file:///mock/resource.txt")
        )
        #expect(result.contents.count == 1)
        if case .text(let uri, _, _, let mimeType, let text) = result.contents[0] {
            #expect(uri == "file:///mock/resource.txt")
            #expect(mimeType == "text/plain")
            #expect(text == "Mock resource content")
        } else {
            Issue.record("Expected text resource content")
        }
    }

    @Test("should list resource templates")
    func listResourceTemplates() async throws {
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(MockMCPTransport()))
        )
        defer { Task { try? await client.close() } }

        let templates = try await client.listResourceTemplates(options: nil)
        #expect(templates.resourceTemplates.count == 1)
        #expect(templates.resourceTemplates[0].uriTemplate == "file:///{path}")
        #expect(templates.resourceTemplates[0].name == "mock-template")
        #expect(templates.resourceTemplates[0].description == "Mock template")
    }

    @Test("should list prompts from the server")
    func listPrompts() async throws {
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(MockMCPTransport()))
        )
        defer { Task { try? await client.close() } }

        let prompts = try await client.experimental_listPrompts(options: nil)
        #expect(prompts.prompts.count == 1)
        #expect(prompts.prompts[0].name == "code_review")
        #expect(prompts.prompts[0].title == "Request Code Review")
        #expect(prompts.prompts[0].description != nil)
        #expect(prompts.prompts[0].arguments?.count == 1)
    }

    @Test("should get a prompt by name")
    func getPrompt() async throws {
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(MockMCPTransport()))
        )
        defer { Task { try? await client.close() } }

        let prompt = try await client.experimental_getPrompt(
            args: MCPGetPromptArgs(name: "code_review", arguments: ["code": .string("print(42)")])
        )

        #expect(prompt.description == "Code review prompt")
        #expect(prompt.messages.count == 1)
        #expect(prompt.messages[0].role == .user)
        if case .text(let text) = prompt.messages[0].content {
            #expect(text.text.contains("Please review this code:"))
        } else {
            Issue.record("Expected text prompt message")
        }
    }

    @Test("should throw if the server does not support prompts")
    func promptsCapabilityCheck() async throws {
        let transport = MockMCPTransport(resources: [], prompts: [])
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        await #expect(throws: MCPClientError.self) {
            _ = try await client.experimental_listPrompts(options: nil)
        }
        await #expect(throws: MCPClientError.self) {
            _ = try await client.experimental_getPrompt(args: MCPGetPromptArgs(name: "code_review"))
        }
    }

    @Test("should not return user-defined tool if it is nonexistent")
    func nonexistentSchemaToolFiltered() async throws {
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(MockMCPTransport()))
        )
        defer { Task { try? await client.close() } }

        let schemas: ToolSchemas = .schemas([
            "nonexistent-tool": ToolSchemaDefinition(
                inputSchema: FlexibleSchema(
                    jsonSchema(.object([
                        "type": .string("object"),
                        "properties": .object([
                            "bar": .object(["type": .string("string")]),
                        ]),
                        "additionalProperties": .bool(false),
                    ]))
                )
            ),
        ])

        let tools = try await client.tools(options: MCPToolsOptions(schemas: schemas))
        #expect(tools["nonexistent-tool"] == nil)
    }

    @Test("should error when calling tool with misconfigured parameters")
    func invalidToolParamsError() async throws {
        let transport = MockMCPTransport(failOnInvalidToolParams: true)
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let schemas: ToolSchemas = .schemas([
            "mock-tool": ToolSchemaDefinition(
                inputSchema: FlexibleSchema(
                    jsonSchema(.object([
                        "type": .string("object"),
                        "properties": .object([
                            "bar": .object(["type": .string("string")]),
                        ]),
                        "additionalProperties": .bool(false),
                    ]))
                )
            ),
        ])

        let tools = try await client.tools(options: MCPToolsOptions(schemas: schemas))
        let tool = try #require(tools["mock-tool"])

        await #expect(throws: MCPClientError.self) {
            _ = try await tool.execute!(
                .object(["bar": .string("bar")]),
                ToolCallOptions(toolCallId: "1", messages: [])
            )
        }
    }

    @Test("should include JSON-RPC error data in MCPClientError")
    func jsonRpcErrorDataIncluded() async throws {
        let transport = MockMCPTransport(failOnInvalidToolParams: true)
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let schemas: ToolSchemas = .schemas([
            "mock-tool": ToolSchemaDefinition(
                inputSchema: FlexibleSchema(
                    jsonSchema(.object([
                        "type": .string("object"),
                        "properties": .object([
                            "bar": .object(["type": .string("string")]),
                        ]),
                        "additionalProperties": .bool(false),
                    ]))
                )
            ),
        ])

        let tools = try await client.tools(options: MCPToolsOptions(schemas: schemas))
        let tool = try #require(tools["mock-tool"])

        do {
            _ = try await tool.execute!(
                .object(["bar": .string("bar")]),
                ToolCallOptions(toolCallId: "1", messages: [])
            )
            Issue.record("Expected error to be thrown")
        } catch let error as MCPClientError {
            #expect(error.code == -32602)
            let data = error.data as? JSONValue
            #expect(data != nil)
            if let data, case .object(let obj) = data {
                #expect(obj["expectedSchema"] != nil)
                #expect(obj["receivedArguments"] == .object(["bar": .string("bar")]))
            }
        }
    }

    @Test("should throw Abort Error if tool call request is aborted")
    func abortSignal() async throws {
        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(MockMCPTransport()))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        let tool = try #require(tools["mock-tool"])

        await #expect(throws: AbortError.self) {
            _ = try await tool.execute!(
                .object(["foo": .string("bar")]),
                ToolCallOptions(toolCallId: "1", messages: [], abortSignal: { true })
            )
        }
    }

    @Test("should use custom client version when provided")
    func customClientVersion() async throws {
        let transport = MockMCPTransport()
        var capturedVersion: String?

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport), version: "2.5.0")
        )
        defer { Task { try? await client.close() } }

        for message in transport.sentMessages {
            guard case .request(let request) = message else { continue }
            guard request.method == "initialize" else { continue }
            guard let params = request.params, case .object(let obj) = params else { continue }
            guard case .object(let clientInfo) = obj["clientInfo"] else { continue }
            if case .string(let v) = clientInfo["version"] {
                capturedVersion = v
            }
        }

        #expect(capturedVersion == "2.5.0")
    }

    @Test("elicitation support: should handle elicitation requests from the server")
    func elicitationSupport() async throws {
        let transport = MockMCPTransport()
        let client = try await createMCPClient(
            config: MCPClientConfig(
                transport: .custom(transport),
                capabilities: ClientCapabilities(elicitation: ElicitationCapability())
            )
        )
        defer { Task { try? await client.close() } }

        try client.onElicitationRequest(schema: ElicitationRequestSchema.self) { request in
            #expect(request.params.message.contains("GitHub"))
            return ElicitResult(action: .accept, content: ["name": .string("octocat")])
        }

        // Simulate server -> client request:
        let serverRequest = JSONRPCRequest(
            id: .int(42),
            method: "elicitation/create",
            params: .object([
                "message": .string("Please provide your GitHub username"),
                "requestedSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("name")]),
                ]),
            ])
        )

        transport.onmessage?(.request(serverRequest))

        // Give the async handler time to run.
        try await Task.sleep(nanoseconds: 50_000_000)

        let sentResponseMessage = transport.sentMessages.first { message in
            if case .response(let response) = message, response.id == .int(42) {
                return true
            }
            return false
        }

        guard case .response(let response) = sentResponseMessage else {
            Issue.record("Expected elicitation response to be sent")
            return
        }

        if case .object(let obj) = response.result {
            #expect(obj["action"] == .string("accept"))
            if case .object(let content) = obj["content"] {
                #expect(content["name"] == .string("octocat"))
            } else {
                Issue.record("Expected content object")
            }
        } else {
            Issue.record("Expected object result")
        }
    }

    @Test("outputSchema support: should return typed output when structuredContent is provided")
    func outputSchemaStructuredContent() async throws {
        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "weather-tool",
                    description: "Get weather data",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "location": .object(["type": .string("string")]),
                        ]),
                    ]),
                    outputSchema: .object([:])
                ),
            ],
            toolCallResults: [
                "weather-tool": .content(
                    content: [
                        .text(.init(text: "{\"temperature\": 22.5, \"conditions\": \"Sunny\"}")),
                    ],
                    structuredContent: .object([
                        "temperature": .number(22.5),
                        "conditions": .string("Sunny"),
                    ]),
                    isError: false,
                    meta: nil
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let outputSchema = FlexibleSchema(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([
                    "temperature": .object(["type": .string("number")]),
                    "conditions": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("temperature"), .string("conditions")]),
                "additionalProperties": .bool(false),
            ]))
        )

        let schemas: ToolSchemas = .schemas([
            "weather-tool": ToolSchemaDefinition(
                inputSchema: FlexibleSchema(
                    jsonSchema(.object([
                        "type": .string("object"),
                        "properties": .object([
                            "location": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("location")]),
                        "additionalProperties": .bool(false),
                    ]))
                ),
                outputSchema: outputSchema
            ),
        ])

        let tools = try await client.tools(options: MCPToolsOptions(schemas: schemas))
        let tool = try #require(tools["weather-tool"])

        let result = try await tool.execute!(
            .object(["location": .string("New York")]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        #expect(result == .object([
            "temperature": .number(22.5),
            "conditions": .string("Sunny"),
        ]))
    }

    @Test("outputSchema support: should fallback to parsing text content when structuredContent is not present")
    func outputSchemaFallbackParse() async throws {
        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "json-tool",
                    description: "Returns JSON data",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                    ])
                ),
            ],
            toolCallResults: [
                "json-tool": .content(
                    content: [
                        .text(.init(text: "{\"value\": 42, \"name\": \"test\"}")),
                    ],
                    structuredContent: nil,
                    isError: false,
                    meta: nil
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let outputSchema = FlexibleSchema(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("number")]),
                    "name": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("value"), .string("name")]),
                "additionalProperties": .bool(false),
            ]))
        )

        let schemas: ToolSchemas = .schemas([
            "json-tool": ToolSchemaDefinition(
                inputSchema: FlexibleSchema(
                    jsonSchema(.object([
                        "type": .string("object"),
                        "properties": .object([:]),
                        "additionalProperties": .bool(false),
                    ]))
                ),
                outputSchema: outputSchema
            ),
        ])

        let tools = try await client.tools(options: MCPToolsOptions(schemas: schemas))
        let tool = try #require(tools["json-tool"])

        let result = try await tool.execute!(
            .object([:]),
            ToolCallOptions(toolCallId: "1", messages: [])
        ).resolve()

        #expect(result == .object([
            "value": .number(42),
            "name": .string("test"),
        ]))
    }

    @Test("tool title support: should prefer top-level title and fallback to annotations.title")
    func toolTitleSupport() async throws {
        let transport = MockMCPTransport(
            overrideTools: [
                MCPTool(
                    name: "titled-tool",
                    title: "My Tool Title",
                    description: "A tool with a title",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                    ])
                ),
                MCPTool(
                    name: "annotated-tool",
                    title: nil,
                    description: "A tool with title in annotations",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                    ]),
                    annotations: MCPToolAnnotations(title: "Annotation Title")
                ),
                MCPTool(
                    name: "dual-title-tool",
                    title: "Top Level Title",
                    description: "A tool with both titles",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:]),
                    ]),
                    annotations: MCPToolAnnotations(title: "Ignored Annotation Title")
                ),
            ]
        )

        let client = try await createMCPClient(
            config: MCPClientConfig(transport: .custom(transport))
        )
        defer { Task { try? await client.close() } }

        let tools = try await client.tools(options: nil)
        #expect(try #require(tools["titled-tool"]).title == "My Tool Title")
        #expect(try #require(tools["annotated-tool"]).title == "Annotation Title")
        #expect(try #require(tools["dual-title-tool"]).title == "Top Level Title")
    }
}
