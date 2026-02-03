import Foundation
import Testing
@testable import AISDKProvider
@testable import GroqProvider

@Suite("prepareGroqTools")
struct GroqPrepareToolsTests {
    @Test("returns nil when tools absent")
    func noTools() throws {
        let prepared = prepareGroqTools(tools: nil, toolChoice: nil, modelId: GroqChatModelId(rawValue: "gemini-2"))
        #expect(prepared.tools == nil)
        #expect(prepared.toolChoice == nil)
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("should return undefined tools and toolChoice when tools are empty")
    func emptyTools() throws {
        let prepared = prepareGroqTools(tools: [], toolChoice: nil, modelId: GroqChatModelId(rawValue: "gemma2-9b-it"))
        #expect(prepared.tools == nil)
        #expect(prepared.toolChoice == nil)
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("should correctly prepare function tools")
    func prepareFunctionTools() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])] ),
            description: "A test function"
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool],
            toolChoice: nil,
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it")
        )

        #expect(prepared.tools != nil)
        #expect(prepared.tools?.count == 1)
        #expect(prepared.toolChoice == nil)
        #expect(prepared.toolWarnings.isEmpty)

        if let tools = prepared.tools,
           let first = tools.first,
           case let .object(toolObject) = first,
           let functionValue = toolObject["function"],
           case let .object(functionObject) = functionValue {
            #expect(toolObject["type"] == JSONValue.string("function"))
            #expect(functionObject["name"] == JSONValue.string("testFunction"))
            #expect(functionObject["description"] == JSONValue.string("A test function"))
        } else {
            Issue.record("Expected function tool structure")
        }
    }

    @Test("should add warnings for unsupported provider-defined tools")
    func unsupportedProviderTools() throws {
        let tool = LanguageModelV3Tool.provider(LanguageModelV3ProviderTool(
            id: "some.unsupported_tool",
            name: "unsupported_tool",
            args: [:]
        ))

        let prepared = prepareGroqTools(
            tools: [tool],
            toolChoice: nil,
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it")
        )

        #expect(prepared.tools?.isEmpty == true || prepared.tools == nil)
        #expect(prepared.toolChoice == nil)
        #expect(prepared.toolWarnings.count == 1)
        if let warning = prepared.toolWarnings.first,
           case let .unsupported(feature, details) = warning {
            #expect(feature == "provider-defined tool some.unsupported_tool")
            #expect(details == nil)
        } else {
            Issue.record("Expected unsupported warning")
        }
    }

    @Test("should handle tool choice \"auto\"")
    func toolChoiceAuto() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object([:]),
            description: "Test"
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool],
            toolChoice: .auto,
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it")
        )

        #expect(prepared.toolChoice == JSONValue.string("auto"))
    }

    @Test("should handle tool choice \"required\"")
    func toolChoiceRequired() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object([:]),
            description: "Test"
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool],
            toolChoice: .required,
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it")
        )

        #expect(prepared.toolChoice == JSONValue.string("required"))
    }

    @Test("should handle tool choice \"none\"")
    func toolChoiceNone() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object([:]),
            description: "Test"
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool],
            toolChoice: LanguageModelV3ToolChoice.none,
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it")
        )

        #expect(prepared.toolChoice == JSONValue.string("none"))
    }

    @Test("should handle tool choice \"tool\"")
    func toolChoiceTool() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object([:]),
            description: "Test"
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool],
            toolChoice: .tool(toolName: "testFunction"),
            modelId: GroqChatModelId(rawValue: "gemma2-9b-it")
        )

        guard case let .object(choice)? = prepared.toolChoice,
              let functionValue = choice["function"],
              case let .object(functionObj) = functionValue else {
            Issue.record("Expected tool choice object with function")
            return
        }

        #expect(choice["type"] == .string("function"))
        #expect(functionObj["name"] == .string("testFunction"))
    }

    @Test("warns when mixing function and provider-defined tools")
    func mixedTools() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "weather",
            inputSchema: .object(["type": .string("object")]),
            description: "Weather"
        ))
        let providerTool = LanguageModelV3Tool.provider(LanguageModelV3ProviderTool(
            id: "groq.browser_search",
            name: "browser_search",
            args: [:]
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool, providerTool],
            toolChoice: nil,
            modelId: GroqChatModelId(rawValue: "other-model")
        )

        #expect(prepared.toolWarnings.contains(where: { warning in
            if case let .unsupported(feature, _) = warning {
                return feature == "provider-defined tool groq.browser_search"
            }
            return false
        }))
    }

    @Test("browser search supported models map to provider tool")
    func browserSearchSupported() throws {
        let tool = LanguageModelV3Tool.provider(LanguageModelV3ProviderTool(
            id: "groq.browser_search",
            name: "browser_search",
            args: [:]
        ))

        let prepared = prepareGroqTools(
            tools: [tool],
            toolChoice: nil,
            modelId: GroqChatModelId(rawValue: "openai/gpt-oss-20b")
        )

        guard let tools = prepared.tools,
              let first = tools.first,
              case let .object(toolObject) = first else {
            Issue.record("Expected provider tool entry")
            return
        }

        #expect(toolObject["type"] == .string("browser_search"))
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("function tools convert to groq payload and tool choice")
    func functionTools() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "lookup",
            inputSchema: .object(["type": .string("object")]),
            description: "Lookup"
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool],
            toolChoice: .tool(toolName: "lookup"),
            modelId: GroqChatModelId(rawValue: "gemma")
        )

        guard let tools = prepared.tools,
              let first = tools.first,
              case let .object(toolObject) = first,
              let functionValue = toolObject["function"],
              case let .object(functionObject) = functionValue else {
            Issue.record("Expected function tool payload")
            return
        }

        #expect(functionObject["name"] == .string("lookup"))
        if case let .object(choice)? = prepared.toolChoice {
            #expect(choice["type"] == .string("function"))
        } else {
            Issue.record("Expected tool choice object")
        }
    }

    @Test("should handle mixed tools with model validation")
    func mixedToolsWithValidation() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "test-tool",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
            description: "A test tool"
        ))
        let browserTool = LanguageModelV3Tool.provider(LanguageModelV3ProviderTool(
            id: "groq.browser_search",
            name: "browser_search",
            args: [:]
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool, browserTool],
            toolChoice: nil,
            modelId: GroqChatModelId(rawValue: "openai/gpt-oss-20b")
        )

        #expect(prepared.tools?.count == 2)
        #expect(prepared.toolWarnings.isEmpty)

        // Verify both tools are present
        if let tools = prepared.tools {
            let hasFunction = tools.contains(where: { tool in
                if case let .object(obj) = tool,
                   obj["type"] == .string("function") {
                    return true
                }
                return false
            })
            let hasBrowserSearch = tools.contains(where: { tool in
                if case let .object(obj) = tool,
                   obj["type"] == .string("browser_search") {
                    return true
                }
                return false
            })
            #expect(hasFunction)
            #expect(hasBrowserSearch)
        }
    }

    @Test("should validate all browser search supported models")
    func validateAllSupportedModels() throws {
        let supportedModels = ["openai/gpt-oss-20b", "openai/gpt-oss-120b"]

        for modelId in supportedModels {
            let tool = LanguageModelV3Tool.provider(LanguageModelV3ProviderTool(
                id: "groq.browser_search",
                name: "browser_search",
                args: [:]
            ))

            let prepared = prepareGroqTools(
                tools: [tool],
                toolChoice: nil,
                modelId: GroqChatModelId(rawValue: modelId)
            )

            #expect(prepared.tools?.count == 1, "Model \(modelId) should support browser search")
            #expect(prepared.toolWarnings.isEmpty, "Model \(modelId) should not have warnings")

            if let tools = prepared.tools,
               let first = tools.first,
               case let .object(obj) = first {
                #expect(obj["type"] == .string("browser_search"), "Model \(modelId) should have browser_search type")
            }
        }
    }

    @Test("should handle browser search with tool choice")
    func browserSearchWithToolChoice() throws {
        let tool = LanguageModelV3Tool.provider(LanguageModelV3ProviderTool(
            id: "groq.browser_search",
            name: "browser_search",
            args: [:]
        ))

        let prepared = prepareGroqTools(
            tools: [tool],
            toolChoice: .required,
            modelId: GroqChatModelId(rawValue: "openai/gpt-oss-120b")
        )

        #expect(prepared.tools?.count == 1)
        #expect(prepared.toolChoice == JSONValue.string("required"))
        #expect(prepared.toolWarnings.isEmpty)

        if let tools = prepared.tools,
           let first = tools.first,
           case let .object(obj) = first {
            #expect(obj["type"] == .string("browser_search"))
        }
    }
}
