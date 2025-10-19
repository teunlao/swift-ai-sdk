import Foundation
import Testing
@testable import AISDKProvider
@testable import GroqProvider

@Suite("prepareGroqTools")
struct GroqPrepareToolsTests {
    @Test("returns nil when tools absent")
    func noTools() {
        let prepared = prepareGroqTools(tools: nil, toolChoice: nil, modelId: GroqChatModelId(rawValue: "gemini-2"))
        #expect(prepared.tools == nil)
        #expect(prepared.toolChoice == nil)
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("warns when mixing function and provider-defined tools")
    func mixedTools() {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "weather",
            inputSchema: .object(["type": .string("object")]),
            description: "Weather"
        ))
        let providerTool = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
            id: "groq.browser_search",
            name: "browser_search",
            args: [:]
        ))

        let prepared = prepareGroqTools(
            tools: [functionTool, providerTool],
            toolChoice: nil,
            modelId: GroqChatModelId(rawValue: "other-model")
        )

        #expect(prepared.toolWarnings.contains { warning in
            if case .unsupportedTool = warning { return true }
            return false
        })
    }

    @Test("browser search supported models map to provider tool")
    func browserSearchSupported() {
        let tool = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
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
    func functionTools() {
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
}
