import Foundation
import Testing
@testable import AISDKProvider
@testable import GoogleProvider

@Suite("prepareGoogleTools")
struct GooglePrepareToolsTests {
    @Test("returns empty payload when tools absent")
    func noTools() {
        let prepared = prepareGoogleTools(
            tools: nil,
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro")
        )
        #expect(prepared.tools == nil)
        #expect(prepared.toolConfig == nil)
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
            id: "google.google_search",
            name: "google_search",
            args: [:]
        ))

        let prepared = prepareGoogleTools(
            tools: [functionTool, providerTool],
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro")
        )

        #expect(prepared.toolWarnings.contains { warning in
            if case .unsupportedTool = warning { return true }
            return false
        })
    }

    @Test("maps provider-defined google search with dynamic retrieval")
    func providerDefinedGoogleSearch() {
        let tool = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
            id: "google.google_search",
            name: "google_search",
            args: [
                "mode": .string("MODE_DYNAMIC"),
                "dynamicThreshold": .number(0.25)
            ]
        ))

        let prepared = prepareGoogleTools(
            tools: [tool],
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-1.5-flash")
        )

        guard case let .array(toolsArray)? = prepared.tools else {
            Issue.record("Expected tools array")
            return
        }

        #expect(toolsArray.count == 1)

        guard case let .object(toolObject) = toolsArray.first else {
            Issue.record("Expected tool object entry")
            return
        }

        #expect(toolObject["googleSearchRetrieval"] != nil)
        let retrieval = toolObject["googleSearchRetrieval"]
        guard case let .object(config)? = retrieval,
              case let .object(dynamicConfig)? = config["dynamicRetrievalConfig"] else {
            Issue.record("Expected dynamic retrieval config")
            return
        }
        #expect(dynamicConfig["mode"] == .string("MODE_DYNAMIC"))
        #expect(dynamicConfig["dynamicThreshold"] == .number(0.25))
    }

    @Test("maps function tools and tool choice")
    func functionTools() {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "lookup",
            inputSchema: .object(["type": .string("object")]),
            description: "Lookup"
        ))

        let prepared = prepareGoogleTools(
            tools: [functionTool],
            toolChoice: .tool(toolName: "lookup"),
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-pro")
        )

        guard case let .object(toolsObject)? = prepared.tools else {
            Issue.record("Expected tools object")
            return
        }
        guard case let .array(functionDeclarations)? = toolsObject["functionDeclarations"] else {
            Issue.record("Expected function declarations array")
            return
        }
        #expect(functionDeclarations.count == 1)

        guard case let .object(toolConfig)? = prepared.toolConfig,
              case let .object(functionConfig)? = toolConfig["functionCallingConfig"] else {
            Issue.record("Expected functionCallingConfig")
            return
        }
        #expect(functionConfig["mode"] == .string("ANY"))
        guard case let .array(allowed)? = functionConfig["allowedFunctionNames"] else {
            Issue.record("Expected allowed function names")
            return
        }
        #expect(allowed == [.string("lookup")])
    }
}
