import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAIResponsesPrepareTools")
struct OpenAIResponsesPrepareToolsTests {
    private func providerTool(id: String, name: String? = nil, args: [String: JSONValue] = [:]) -> LanguageModelV3Tool {
        .provider(
            LanguageModelV3ProviderTool(
                id: id,
                name: name ?? id,
                args: args
            )
        )
    }

    @Test("code interpreter defaults to auto container")
    func codeInterpreterDefaultsToAutoContainer() async throws {
        let result = try await prepareOpenAIResponsesTools(
            tools: [providerTool(id: "openai.code_interpreter", name: "code_interpreter")],
            toolChoice: nil
        )

        #expect(result.warnings.isEmpty)
        guard let tools = result.tools, tools.count == 1 else {
            Issue.record("Expected single tool")
            return
        }
        guard case .object(let toolObject) = tools[0] else {
            Issue.record("Expected JSON object tool")
            return
        }
        #expect(toolObject["type"] == JSONValue.string("code_interpreter"))
        if case .object(let container)? = toolObject["container"] {
            #expect(container["type"] == JSONValue.string("auto"))
            #expect(container["file_ids"] == nil)
        } else {
            Issue.record("Expected container object")
        }
        #expect(result.toolChoice == nil)
    }

    @Test("code interpreter with string container")
    func codeInterpreterWithStringContainer() async throws {
        let tool = providerTool(
            id: "openai.code_interpreter",
            name: "code_interpreter",
            args: ["container": .string("container-123")]
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        guard let tools = result.tools, case .object(let toolObject) = tools.first else {
            Issue.record("Expected tool object")
            return
        }
        #expect(toolObject["container"] == JSONValue.string("container-123"))
    }

    @Test("code interpreter with file ids container")
    func codeInterpreterWithFileIds() async throws {
        let tool = providerTool(
            id: "openai.code_interpreter",
            name: "code_interpreter",
            args: [
                "container": .object([
                    "fileIds": .array([
                        .string("file-1"),
                        .string("file-2"),
                        .string("file-3")
                    ])
                ])
            ]
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first,
              case .object(let container)? = toolObject["container"],
              case .array(let fileIds)? = container["file_ids"] else {
            Issue.record("Expected container file_ids array")
            return
        }

        #expect(fileIds == [.string("file-1"), .string("file-2"), .string("file-3")])
    }

    @Test("code interpreter tool choice maps to provider type")
    func codeInterpreterToolChoiceMapping() async throws {
        let result = try await prepareOpenAIResponsesTools(
            tools: [providerTool(id: "openai.code_interpreter", name: "code_interpreter")],
            toolChoice: .tool(toolName: "code_interpreter")
        )

        #expect(result.toolChoice == JSONValue.object(["type": .string("code_interpreter")]))
    }

    @Test("function tool passes through strict")
    func functionToolPassesThroughStrict() async throws {
        let functionTool = LanguageModelV3Tool.function(
            LanguageModelV3FunctionTool(
                name: "testFunction",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "input": .object(["type": .string("string")])
                    ])
                ]),
                description: "A test function",
                strict: true
            )
        )
        let codeInterpreter = providerTool(
            id: "openai.code_interpreter",
            name: "code_interpreter",
            args: ["container": .string("my-container")]
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [functionTool, codeInterpreter],
            toolChoice: nil
        )

        guard let tools = result.tools, tools.count == 2 else {
            Issue.record("Expected two tools")
            return
        }
        guard case .object(let functionObject) = tools[0] else {
            Issue.record("Expected function tool object")
            return
        }
        #expect(functionObject["type"] == JSONValue.string("function"))
        #expect(functionObject["strict"] == JSONValue.bool(true))
        guard case .object(let interpreterObject) = tools[1] else {
            Issue.record("Expected code interpreter object")
            return
        }
        #expect(interpreterObject["container"] == JSONValue.string("my-container"))
    }

    @Test("image generation tool maps args")
    func imageGenerationToolMapsArgs() async throws {
        let tool = providerTool(
            id: "openai.image_generation",
            name: "image_generation",
            args: [
                "background": .string("opaque"),
                "size": .string("1536x1024"),
                "quality": .string("high"),
                "moderation": .string("auto"),
                "outputFormat": .string("png"),
                "outputCompression": .number(100),
                "inputFidelity": .string("high"),
                "partialImages": .number(2),
                "model": .string("gpt-image-1")
            ]
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected image_generation tool object")
            return
        }
        #expect(toolObject["type"] == JSONValue.string("image_generation"))
        #expect(toolObject["background"] == JSONValue.string("opaque"))
        #expect(toolObject["output_format"] == JSONValue.string("png"))
        #expect(toolObject["partial_images"] == JSONValue.number(2))
        #expect(toolObject["model"] == JSONValue.string("gpt-image-1"))
    }

    @Test("image generation tool choice mapping")
    func imageGenerationToolChoiceMapping() async throws {
        let tool = providerTool(id: "openai.image_generation", name: "image_generation")
        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: .tool(toolName: "image_generation")
        )

        #expect(result.toolChoice == JSONValue.object(["type": .string("image_generation")]))
    }

    @Test("mcp tool defaults require_approval to never")
    func mcpToolDefaultsRequireApprovalToNever() async throws {
        let tool = providerTool(
            id: "openai.mcp",
            name: "mcp",
            args: [
                "serverLabel": .string("My MCP"),
                "serverUrl": .string("https://mcp.example.com")
            ]
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: .tool(toolName: "mcp")
        )

        #expect(result.warnings.isEmpty)
        #expect(result.toolChoice == JSONValue.object(["type": .string("mcp")]))
        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected mcp tool object")
            return
        }
        #expect(toolObject["type"] == JSONValue.string("mcp"))
        #expect(toolObject["server_label"] == JSONValue.string("My MCP"))
        #expect(toolObject["server_url"] == JSONValue.string("https://mcp.example.com"))
        #expect(toolObject["require_approval"] == JSONValue.string("never"))
        #expect(toolObject["allowed_tools"] == nil)
    }

    @Test("mcp tool maps allowed_tools array")
    func mcpToolMapsAllowedToolsArray() async throws {
        let tool = providerTool(
            id: "openai.mcp",
            name: "mcp",
            args: [
                "serverLabel": .string("My MCP"),
                "serverUrl": .string("https://mcp.example.com"),
                "allowedTools": .array([.string("one"), .string("two")])
            ]
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected mcp tool object")
            return
        }

        #expect(toolObject["allowed_tools"] == JSONValue.array([.string("one"), .string("two")]))
    }

    @Test("mcp tool maps filter allowed_tools and conditional require_approval")
    func mcpToolMapsFilterAllowedToolsAndConditionalRequireApproval() async throws {
        let tool = providerTool(
            id: "openai.mcp",
            name: "mcp",
            args: [
                "serverLabel": .string("My MCP"),
                "connectorId": .string("connector-123"),
                "allowedTools": .object([
                    "readOnly": .bool(true),
                    "toolNames": .array([.string("alpha"), .string("beta")])
                ]),
                "requireApproval": .object([
                    "never": .object([
                        "toolNames": .array([.string("alpha")])
                    ])
                ])
            ]
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected mcp tool object")
            return
        }

        guard case .object(let allowedTools)? = toolObject["allowed_tools"] else {
            Issue.record("Expected allowed_tools object")
            return
        }
        #expect(allowedTools["read_only"] == JSONValue.bool(true))
        #expect(allowedTools["tool_names"] == JSONValue.array([.string("alpha"), .string("beta")]))

        guard case .object(let requireApproval)? = toolObject["require_approval"],
              case .object(let neverObject)? = requireApproval["never"] else {
            Issue.record("Expected require_approval.never object")
            return
        }
        #expect(neverObject["tool_names"] == JSONValue.array([.string("alpha")]))
    }

    @Test("web search preview tool maps args")
    func webSearchPreviewToolMapsArgs() async throws {
        let args: [String: JSONValue] = [
            "searchContextSize": .string("low"),
            "userLocation": .object([
                "country": .string("DE"),
                "city": .string("Berlin"),
                "region": .string("BE"),
                "timezone": .string("Europe/Berlin")
            ])
        ]
        let tool = providerTool(
            id: "openai.web_search_preview",
            name: "web_search_preview",
            args: args
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first,
              case .object(let location)? = toolObject["user_location"] else {
            Issue.record("Expected user_location object")
            return
        }
        #expect(toolObject["type"] == JSONValue.string("web_search_preview"))
        #expect(location["country"] == JSONValue.string("DE"))
        #expect(location["type"] == JSONValue.string("approximate"))
    }

    @Test("web search tool maps filters")
    func webSearchToolMapsFilters() async throws {
        let args: [String: JSONValue] = [
            "filters": .object([
                "allowedDomains": .array([.string("example.com"), .string("test.com")])
            ]),
            "searchContextSize": .string("medium")
        ]
        let tool = providerTool(
            id: "openai.web_search",
            name: "web_search",
            args: args
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: .tool(toolName: "web_search")
        )

        #expect(result.toolChoice == JSONValue.object(["type": .string("web_search")]))
        guard let tools = result.tools,
              case .object(let toolObject) = tools.first,
              case .object(let filters)? = toolObject["filters"] else {
            Issue.record("Expected filters object")
            return
        }
        #expect(filters["allowed_domains"] == JSONValue.array([.string("example.com"), .string("test.com")]))
    }

    @Test("web search tool maps external web access")
    func webSearchToolMapsExternalWebAccess() async throws {
        let args: [String: JSONValue] = [
            "externalWebAccess": .bool(false)
        ]
        let tool = providerTool(
            id: "openai.web_search",
            name: "web_search",
            args: args
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected web_search tool object")
            return
        }

        #expect(toolObject["type"] == JSONValue.string("web_search"))
        #expect(toolObject["external_web_access"] == JSONValue.bool(false))
    }

    @Test("file search tool maps ranking options")
    func fileSearchToolMapsRanking() async throws {
        let args: [String: JSONValue] = [
            "vectorStoreIds": .array([.string("vs_1"), .string("vs_2")]),
            "maxNumResults": .number(5),
            "ranking": .object([
                "ranker": .string("default"),
                "scoreThreshold": .number(0.5)
            ]),
            "filters": .object([
                "type": .string("eq"),
                "key": .string("category"),
                "value": .string("news")
            ])
        ]
        let tool = providerTool(
            id: "openai.file_search",
            name: "file_search",
            args: args
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected file_search tool object")
            return
        }
        #expect(toolObject["type"] == JSONValue.string("file_search"))
        #expect(toolObject["vector_store_ids"] == JSONValue.array([.string("vs_1"), .string("vs_2")]))
        #expect(toolObject["max_num_results"] == JSONValue.number(5))
        if case .object(let ranking)? = toolObject["ranking_options"] {
            #expect(ranking["ranker"] == JSONValue.string("default"))
            #expect(ranking["score_threshold"] == JSONValue.number(0.5))
        } else {
            Issue.record("Expected ranking options")
        }
    }

    @Test("local shell tool mapped without args")
    func localShellToolMapped() async throws {
        let result = try await prepareOpenAIResponsesTools(
            tools: [providerTool(id: "openai.local_shell", name: "local_shell")],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected local_shell tool object")
            return
        }
        #expect(toolObject.keys.count == 1)
        #expect(toolObject["type"] == JSONValue.string("local_shell"))
    }

    @Test("shell tool mapped without args")
    func shellToolMapped() async throws {
        let result = try await prepareOpenAIResponsesTools(
            tools: [providerTool(id: "openai.shell", name: "shell")],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected shell tool object")
            return
        }
        #expect(toolObject.keys.count == 1)
        #expect(toolObject["type"] == JSONValue.string("shell"))
    }

    @Test("apply patch tool choice mapping")
    func applyPatchToolChoiceMapping() async throws {
        let tool = providerTool(id: "openai.apply_patch", name: "apply_patch")
        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: .tool(toolName: "apply_patch")
        )

        #expect(result.toolChoice == JSONValue.object(["type": .string("apply_patch")]))
    }

    @Test("apply patch tool mapped without args")
    func applyPatchToolMapped() async throws {
        let result = try await prepareOpenAIResponsesTools(
            tools: [providerTool(id: "openai.apply_patch", name: "apply_patch")],
            toolChoice: nil
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected apply_patch tool object")
            return
        }
        #expect(toolObject.keys.count == 1)
        #expect(toolObject["type"] == JSONValue.string("apply_patch"))
    }

    @Test("unsupported provider tool produces warning")
    func unsupportedProviderToolProducesWarning() async throws {
        let tool = providerTool(id: "openai.unsupported", name: "unsupported", args: [:])
        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil
        )

        #expect(result.tools?.isEmpty == true)
        #expect(result.warnings.count == 1)
        if let warning = result.warnings.first {
            if case let .unsupported(feature, details) = warning {
                #expect(feature == "provider-defined tool openai.unsupported")
                #expect(details == nil)
            } else {
                Issue.record("Unexpected warning type: \(warning)")
            }
        }
    }

    @Test("tool choice for function tool maps to function type")
    func functionToolChoiceMapping() async throws {
        let functionTool = LanguageModelV3Tool.function(
            LanguageModelV3FunctionTool(
                name: "custom_tool",
                inputSchema: .object(["type": .string("object")])
            )
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [functionTool],
            toolChoice: .tool(toolName: "custom_tool")
        )

        #expect(result.toolChoice == JSONValue.object([
            "type": .string("function"),
            "name": .string("custom_tool")
        ]))
    }
}
