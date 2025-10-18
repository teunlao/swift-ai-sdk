import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("OpenAIResponsesPrepareTools")
struct OpenAIResponsesPrepareToolsTests {
    private func providerTool(id: String, name: String? = nil, args: [String: JSONValue] = [:]) -> LanguageModelV3Tool {
        .providerDefined(
            LanguageModelV3ProviderDefinedTool(
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
            toolChoice: nil,
            strictJsonSchema: false
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
            toolChoice: nil,
            strictJsonSchema: false
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
            toolChoice: nil,
            strictJsonSchema: false
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
            toolChoice: .tool(toolName: "code_interpreter"),
            strictJsonSchema: false
        )

        #expect(result.toolChoice == JSONValue.object(["type": .string("code_interpreter")]))
    }

    @Test("function tool respects strict json schema flag")
    func functionToolRespectsStrictJsonSchema() async throws {
        let functionTool = LanguageModelV3Tool.function(
            LanguageModelV3FunctionTool(
                name: "testFunction",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "input": .object(["type": .string("string")])
                    ])
                ]),
                description: "A test function"
            )
        )
        let codeInterpreter = providerTool(
            id: "openai.code_interpreter",
            name: "code_interpreter",
            args: ["container": .string("my-container")]
        )

        let result = try await prepareOpenAIResponsesTools(
            tools: [functionTool, codeInterpreter],
            toolChoice: nil,
            strictJsonSchema: true
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
            toolChoice: nil,
            strictJsonSchema: false
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
            toolChoice: .tool(toolName: "image_generation"),
            strictJsonSchema: false
        )

        #expect(result.toolChoice == JSONValue.object(["type": .string("image_generation")]))
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
            toolChoice: nil,
            strictJsonSchema: false
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
            toolChoice: .tool(toolName: "web_search"),
            strictJsonSchema: false
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
            toolChoice: nil,
            strictJsonSchema: false
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
            toolChoice: nil,
            strictJsonSchema: false
        )

        guard let tools = result.tools,
              case .object(let toolObject) = tools.first else {
            Issue.record("Expected local_shell tool object")
            return
        }
        #expect(toolObject.keys.count == 1)
        #expect(toolObject["type"] == JSONValue.string("local_shell"))
    }

    @Test("unsupported provider tool produces warning")
    func unsupportedProviderToolProducesWarning() async throws {
        let tool = providerTool(id: "openai.unsupported", name: "unsupported", args: [:])
        let result = try await prepareOpenAIResponsesTools(
            tools: [tool],
            toolChoice: nil,
            strictJsonSchema: false
        )

        #expect(result.tools == nil)
        #expect(result.warnings.count == 1)
        if let warning = result.warnings.first {
            if case .unsupportedTool(let returnedTool, _) = warning {
                #expect(returnedTool == tool)
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
            toolChoice: .tool(toolName: "custom_tool"),
            strictJsonSchema: false
        )

        #expect(result.toolChoice == JSONValue.object([
            "type": .string("function"),
            "name": .string("custom_tool")
        ]))
    }
}
