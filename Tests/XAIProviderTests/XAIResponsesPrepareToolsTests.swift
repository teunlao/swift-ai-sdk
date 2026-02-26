import Foundation
import Testing
@testable import AISDKProvider
@testable import XAIProvider

/**
 Tests for prepareXAIResponsesTools.

 Port of `@ai-sdk/xai/src/responses/xai-responses-prepare-tools.test.ts`.
 */
@Suite("prepareXAIResponsesTools")
struct XAIResponsesPrepareToolsTests {
    private func providerTool(id: String, name: String, args: [String: JSONValue] = [:]) -> LanguageModelV3Tool {
        .provider(.init(id: id, name: name, args: args))
    }

    private func functionTool(
        name: String,
        description: String? = nil,
        inputSchema: JSONValue = .object(["type": .string("object"), "properties": .object([:])])
    ) -> LanguageModelV3Tool {
        .function(.init(name: name, inputSchema: inputSchema, description: description))
    }

    @Test("prepares web_search tool with no args")
    func preparesWebSearchNoArgs() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [providerTool(id: "xai.web_search", name: "web_search")],
            toolChoice: nil
        )

        #expect(result.warnings.isEmpty)
        #expect(result.toolChoice == nil)
        #expect(result.tools == [
            .object(["type": .string("web_search")])
        ])
    }

    @Test("prepares web_search tool with allowed domains")
    func preparesWebSearchAllowedDomains() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.web_search",
                    name: "web_search",
                    args: ["allowedDomains": .array([.string("wikipedia.org"), .string("example.com")])]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("web_search"),
                "allowed_domains": .array([.string("wikipedia.org"), .string("example.com")])
            ])
        ])
    }

    @Test("prepares web_search tool with excluded domains")
    func preparesWebSearchExcludedDomains() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.web_search",
                    name: "web_search",
                    args: ["excludedDomains": .array([.string("spam.com")])]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("web_search"),
                "excluded_domains": .array([.string("spam.com")])
            ])
        ])
    }

    @Test("prepares web_search tool with image understanding")
    func preparesWebSearchImageUnderstanding() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.web_search",
                    name: "web_search",
                    args: ["enableImageUnderstanding": .bool(true)]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("web_search"),
                "enable_image_understanding": .bool(true)
            ])
        ])
    }

    @Test("prepares x_search tool with no args")
    func preparesXSearchNoArgs() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [providerTool(id: "xai.x_search", name: "x_search")],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object(["type": .string("x_search")])
        ])
    }

    @Test("prepares x_search tool with allowed handles")
    func preparesXSearchAllowedHandles() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.x_search",
                    name: "x_search",
                    args: ["allowedXHandles": .array([.string("elonmusk"), .string("xai")])]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("x_search"),
                "allowed_x_handles": .array([.string("elonmusk"), .string("xai")])
            ])
        ])
    }

    @Test("prepares x_search tool with date range")
    func preparesXSearchDateRange() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.x_search",
                    name: "x_search",
                    args: [
                        "fromDate": .string("2025-01-01"),
                        "toDate": .string("2025-12-31")
                    ]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("x_search"),
                "from_date": .string("2025-01-01"),
                "to_date": .string("2025-12-31")
            ])
        ])
    }

    @Test("prepares x_search tool with video understanding")
    func preparesXSearchVideoUnderstanding() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.x_search",
                    name: "x_search",
                    args: [
                        "enableVideoUnderstanding": .bool(true),
                        "enableImageUnderstanding": .bool(true)
                    ]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("x_search"),
                "enable_image_understanding": .bool(true),
                "enable_video_understanding": .bool(true)
            ])
        ])
    }

    @Test("prepares code_execution tool as code_interpreter")
    func preparesCodeExecutionTool() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [providerTool(id: "xai.code_execution", name: "code_execution")],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object(["type": .string("code_interpreter")])
        ])
    }

    @Test("prepares view_image tool")
    func preparesViewImageTool() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [providerTool(id: "xai.view_image", name: "view_image")],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object(["type": .string("view_image")])
        ])
    }

    @Test("prepares view_x_video tool")
    func preparesViewXVideoTool() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [providerTool(id: "xai.view_x_video", name: "view_x_video")],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object(["type": .string("view_x_video")])
        ])
    }

    @Test("prepares file_search tool with vector store IDs")
    func preparesFileSearchVectorStoreIds() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.file_search",
                    name: "file_search",
                    args: [
                        "vectorStoreIds": .array([.string("collection_1"), .string("collection_2")])
                    ]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("file_search"),
                "vector_store_ids": .array([.string("collection_1"), .string("collection_2")])
            ])
        ])
    }

    @Test("prepares file_search tool with max num results")
    func preparesFileSearchMaxNumResults() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.file_search",
                    name: "file_search",
                    args: [
                        "vectorStoreIds": .array([.string("collection_1")]),
                        "maxNumResults": .number(10)
                    ]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("file_search"),
                "vector_store_ids": .array([.string("collection_1")]),
                "max_num_results": .number(10)
            ])
        ])
    }

    @Test("handles multiple tools including file_search")
    func handlesMultipleToolsIncludingFileSearch() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(id: "xai.web_search", name: "web_search"),
                providerTool(
                    id: "xai.file_search",
                    name: "file_search",
                    args: ["vectorStoreIds": .array([.string("collection_1")])]
                ),
                functionTool(name: "calculator", description: "calculate numbers")
            ],
            toolChoice: nil
        )

        guard let tools = result.tools else {
            Issue.record("Expected tools to be present")
            return
        }

        #expect(tools.count == 3)
        if case .object(let dict0) = tools[0] {
            #expect(dict0["type"] == .string("web_search"))
        } else {
            Issue.record("Expected tools[0] to be an object")
        }
        if case .object(let dict1) = tools[1] {
            #expect(dict1["type"] == .string("file_search"))
        } else {
            Issue.record("Expected tools[1] to be an object")
        }
        if case .object(let dict2) = tools[2] {
            #expect(dict2["type"] == .string("function"))
        } else {
            Issue.record("Expected tools[2] to be an object")
        }
    }

    @Test("prepares function tools")
    func preparesFunctionTools() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "location": .object(["type": .string("string")])
            ]),
            "required": .array([.string("location")])
        ])

        let result = try await prepareXAIResponsesTools(
            tools: [
                functionTool(name: "weather", description: "get weather information", inputSchema: schema)
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("function"),
                "name": .string("weather"),
                "description": .string("get weather information"),
                "parameters": schema
            ])
        ])
    }

    @Test("handles tool choice auto/required/none")
    func handlesToolChoiceSimpleCases() async throws {
        let tools = [providerTool(id: "xai.web_search", name: "web_search")]

        let auto = try await prepareXAIResponsesTools(tools: tools, toolChoice: .auto)
        #expect(auto.toolChoice == .string("auto"))

        let required = try await prepareXAIResponsesTools(tools: tools, toolChoice: .required)
        #expect(required.toolChoice == .string("required"))

        let none = try await prepareXAIResponsesTools(tools: tools, toolChoice: LanguageModelV3ToolChoice.none)
        #expect(none.toolChoice == .string("none"))
    }

    @Test("handles specific tool choice for function tools")
    func handlesSpecificToolChoiceFunction() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                functionTool(name: "weather", description: "get weather")
            ],
            toolChoice: .tool(toolName: "weather")
        )

        #expect(result.toolChoice == .object([
            "type": .string("function"),
            "name": .string("weather")
        ]))
    }

    @Test("warns when trying to force server-side tool via toolChoice")
    func warnsWhenForcingServerSideToolViaToolChoice() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [providerTool(id: "xai.web_search", name: "web_search")],
            toolChoice: .tool(toolName: "web_search")
        )

        #expect(result.toolChoice == nil)
        #expect(result.warnings.contains(.unsupported(feature: "toolChoice for server-side tool \"web_search\"", details: nil)))
    }

    @Test("handles empty tools")
    func handlesEmptyTools() async throws {
        let empty = try await prepareXAIResponsesTools(tools: [], toolChoice: nil)
        #expect(empty.tools == nil)
        #expect(empty.toolChoice == nil)

        let nilTools = try await prepareXAIResponsesTools(tools: nil, toolChoice: nil)
        #expect(nilTools.tools == nil)
        #expect(nilTools.toolChoice == nil)
    }

    @Test("warns about unsupported provider-defined tools")
    func warnsUnsupportedProviderTools() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [providerTool(id: "unsupported.tool", name: "unsupported")],
            toolChoice: nil
        )

        #expect(result.warnings == [
            .unsupported(feature: "provider-defined tool unsupported", details: nil)
        ])
    }

    @Test("prepares mcp tool with required args only")
    func preparesMCPRequiredArgsOnly() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.mcp",
                    name: "mcp",
                    args: [
                        "serverUrl": .string("https://example.com/mcp"),
                        "serverLabel": .string("test-server")
                    ]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("mcp"),
                "server_url": .string("https://example.com/mcp"),
                "server_label": .string("test-server")
            ])
        ])
    }

    @Test("prepares mcp tool with all optional args")
    func preparesMCPAllOptionalArgs() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.mcp",
                    name: "mcp",
                    args: [
                        "serverUrl": .string("https://example.com/mcp"),
                        "serverLabel": .string("test-server"),
                        "serverDescription": .string("A test MCP server"),
                        "allowedTools": .array([.string("tool1"), .string("tool2")]),
                        "headers": .object(["X-Custom": .string("value")]),
                        "authorization": .string("Bearer token123")
                    ]
                )
            ],
            toolChoice: nil
        )

        #expect(result.tools == [
            .object([
                "type": .string("mcp"),
                "server_url": .string("https://example.com/mcp"),
                "server_label": .string("test-server"),
                "server_description": .string("A test MCP server"),
                "allowed_tools": .array([.string("tool1"), .string("tool2")]),
                "headers": .object(["X-Custom": .string("value")]),
                "authorization": .string("Bearer token123")
            ])
        ])
    }

    @Test("warns when trying to force mcp tool via toolChoice")
    func warnsWhenForcingMCPToolViaToolChoice() async throws {
        let result = try await prepareXAIResponsesTools(
            tools: [
                providerTool(
                    id: "xai.mcp",
                    name: "mcp",
                    args: [
                        "serverUrl": .string("https://example.com/mcp"),
                        "serverLabel": .string("test-server")
                    ]
                )
            ],
            toolChoice: .tool(toolName: "mcp")
        )

        #expect(result.toolChoice == nil)
        #expect(result.warnings.contains(.unsupported(feature: "toolChoice for server-side tool \"mcp\"", details: nil)))
    }
}
