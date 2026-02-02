import Foundation
import Testing
@testable import AISDKProvider
@testable import GoogleProvider

@Suite("prepareGoogleTools")
struct GooglePrepareToolsTests {
    @Test("should return undefined tools and tool_choice when tools are empty")
    func emptyTools() throws {
        let prepared = prepareGoogleTools(
            tools: [],
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )
        #expect(prepared.tools == nil)
        #expect(prepared.toolConfig == nil)
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("should correctly prepare function tools")
    func prepareFunctionTools() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
            description: "A test function"
        ))

        let prepared = prepareGoogleTools(
            tools: [functionTool],
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        guard case let .array(toolsArray)? = prepared.tools else {
            Issue.record("Expected tools array")
            return
        }
        guard toolsArray.count == 1,
              case let .object(toolsObject) = toolsArray[0] else {
            Issue.record("Expected single tools entry object")
            return
        }

        guard let functionDeclarationsValue = toolsObject["functionDeclarations"],
              case let .array(functionDeclarations) = functionDeclarationsValue else {
            Issue.record("Expected function declarations array")
            return
        }
        #expect(functionDeclarations.count == 1)

        if case let .object(decl) = functionDeclarations[0] {
            #expect(decl["name"] == JSONValue.string("testFunction"))
            #expect(decl["description"] == JSONValue.string("A test function"))
            #expect(decl["parameters"] == nil) // Empty schema becomes nil
        } else {
            Issue.record("Expected function declaration object")
        }

        #expect(prepared.toolConfig == nil)
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("should correctly prepare provider-defined tools as array")
    func prepareProviderDefinedToolsAsArray() throws {
        let tool1 = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
            id: "google.google_search",
            name: "google_search",
            args: [:]
        ))
        let tool2 = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
            id: "google.url_context",
            name: "url_context",
            args: [:]
        ))

        let prepared = prepareGoogleTools(
            tools: [tool1, tool2],
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        guard case let .array(toolsArray)? = prepared.tools else {
            Issue.record("Expected tools array")
            return
        }

        #expect(toolsArray.count == 2)

        if case let .object(obj1) = toolsArray[0] {
            #expect(obj1["googleSearch"] != nil)
        } else {
            Issue.record("Expected first tool to be googleSearch")
        }

        if case let .object(obj2) = toolsArray[1] {
            #expect(obj2["urlContext"] != nil)
        } else {
            Issue.record("Expected second tool to be urlContext")
        }

        #expect(prepared.toolConfig == nil)
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("should correctly prepare single provider-defined tool")
    func prepareSingleProviderDefinedTool() throws {
        let tool = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
            id: "google.google_search",
            name: "google_search",
            args: [:]
        ))

        let prepared = prepareGoogleTools(
            tools: [tool],
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        guard case let .array(toolsArray)? = prepared.tools else {
            Issue.record("Expected tools array")
            return
        }

        #expect(toolsArray.count == 1)

        if case let .object(obj) = toolsArray[0] {
            #expect(obj["googleSearch"] != nil)
        } else {
            Issue.record("Expected googleSearch tool")
        }

        #expect(prepared.toolConfig == nil)
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("should add warnings for unsupported tools")
    func addWarningsForUnsupportedTools() throws {
        let tool = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
            id: "unsupported.tool",
            name: "unsupported_tool",
            args: [:]
        ))

        let prepared = prepareGoogleTools(
            tools: [tool],
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        // When no valid tools, returns nil (which may serialize as .null for JSONValue)
        #expect(prepared.tools == nil || prepared.tools == JSONValue.null)
        #expect(prepared.toolConfig == nil)
        #expect(prepared.toolWarnings.count == 1)

        if case let .unsupportedTool(unsupportedTool, _) = prepared.toolWarnings[0],
           case let .providerDefined(providerTool) = unsupportedTool {
            #expect(providerTool.id == "unsupported.tool")
            #expect(providerTool.name == "unsupported_tool")
        } else {
            Issue.record("Expected unsupported-tool warning")
        }
    }

    @Test("should handle tool choice \"auto\"")
    func handleToolChoiceAuto() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object([:]),
            description: "Test"
        ))

        let prepared = prepareGoogleTools(
            tools: [functionTool],
            toolChoice: .auto,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        guard case let .object(toolConfig)? = prepared.toolConfig,
              case let .object(functionConfig)? = toolConfig["functionCallingConfig"] else {
            Issue.record("Expected functionCallingConfig")
            return
        }

        #expect(functionConfig["mode"] == .string("AUTO"))
    }

    @Test("should handle tool choice \"required\"")
    func handleToolChoiceRequired() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object([:]),
            description: "Test"
        ))

        let prepared = prepareGoogleTools(
            tools: [functionTool],
            toolChoice: .required,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        guard case let .object(toolConfig)? = prepared.toolConfig,
              case let .object(functionConfig)? = toolConfig["functionCallingConfig"] else {
            Issue.record("Expected functionCallingConfig")
            return
        }

        #expect(functionConfig["mode"] == .string("ANY"))
    }

    @Test("should handle tool choice \"none\"")
    func handleToolChoiceNone() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object([:]),
            description: "Test"
        ))

        let prepared = prepareGoogleTools(
            tools: [functionTool],
            toolChoice: LanguageModelV3ToolChoice.none,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        guard case let .array(toolsArray)? = prepared.tools else {
            Issue.record("Expected tools array")
            return
        }
        guard toolsArray.count == 1,
              case let .object(toolsObject) = toolsArray[0] else {
            Issue.record("Expected single tools entry object")
            return
        }
        guard case let .array(functionDeclarations)? = toolsObject["functionDeclarations"] else {
            Issue.record("Expected function declarations")
            return
        }

        #expect(functionDeclarations.count == 1)

        if case let .object(decl) = functionDeclarations[0] {
            #expect(decl["name"] == .string("testFunction"))
            #expect(decl["description"] == .string("Test"))
            // parameters should be the schema
            #expect(decl["parameters"] != nil)
        } else {
            Issue.record("Expected function declaration")
        }

        guard case let .object(toolConfig)? = prepared.toolConfig,
              case let .object(functionConfig)? = toolConfig["functionCallingConfig"] else {
            Issue.record("Expected functionCallingConfig")
            return
        }

        #expect(functionConfig["mode"] == .string("NONE"))
    }

    @Test("should handle tool choice \"tool\"")
    func handleToolChoiceTool() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object([:]),
            description: "Test"
        ))

        let prepared = prepareGoogleTools(
            tools: [functionTool],
            toolChoice: .tool(toolName: "testFunction"),
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        guard case let .object(toolConfig)? = prepared.toolConfig,
              case let .object(functionConfig)? = toolConfig["functionCallingConfig"] else {
            Issue.record("Expected functionCallingConfig")
            return
        }

        #expect(functionConfig["mode"] == JSONValue.string("ANY"))

        if let allowedValue = functionConfig["allowedFunctionNames"],
           case let .array(allowed) = allowedValue {
            #expect(allowed == [JSONValue.string("testFunction")])
        } else {
            Issue.record("Expected allowedFunctionNames array")
        }
    }

    @Test("should handle tool choice with mixed tools (provider-defined tools only)")
    func handleToolChoiceWithMixedTools() throws {
        let functionTool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "testFunction",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
            description: "A test function"
        ))
        let providerTool = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
            id: "google.google_search",
            name: "google_search",
            args: [:]
        ))

        let prepared = prepareGoogleTools(
            tools: [functionTool, providerTool],
            toolChoice: .auto,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-2.5-flash")
        )

        // Should only include provider-defined tools as array
        guard case let .array(toolsArray)? = prepared.tools else {
            Issue.record("Expected tools array")
            return
        }

        #expect(toolsArray.count == 1)
        if case let .object(obj) = toolsArray[0] {
            #expect(obj["googleSearch"] != nil)
        } else {
            Issue.record("Expected googleSearch tool")
        }

        // Should apply tool choice to provider-defined tools (undefined for provider tools)
        #expect(prepared.toolConfig == nil)

        // Should have warning about mixed tool types
        #expect(prepared.toolWarnings.count == 1)
        if case let .unsupportedTool(unsupportedTool, details) = prepared.toolWarnings[0],
           case .function = unsupportedTool {
            #expect(details == "Cannot mix function tools with provider-defined tools in the same request. Please use either function tools or provider-defined tools, but not both.")
        } else {
            Issue.record("Expected unsupported-tool warning for function tool")
        }
    }

    @Test("should handle latest modelId for provider-defined tools correctly")
    func handleLatestModelIdForProviderDefinedTools() throws {
        let tool = LanguageModelV3Tool.providerDefined(LanguageModelV3ProviderDefinedTool(
            id: "google.google_search",
            name: "google_search",
            args: [:]
        ))

        let prepared = prepareGoogleTools(
            tools: [tool],
            toolChoice: nil,
            modelId: GoogleGenerativeAIModelId(rawValue: "gemini-flash-latest")
        )

        guard case let .array(toolsArray)? = prepared.tools else {
            Issue.record("Expected tools array")
            return
        }

        #expect(toolsArray.count == 1)
        if case let .object(obj) = toolsArray[0] {
            #expect(obj["googleSearch"] != nil)
        } else {
            Issue.record("Expected googleSearch tool")
        }

        #expect(prepared.toolConfig == nil)
        #expect(prepared.toolWarnings.isEmpty)
    }

    @Test("returns empty payload when tools absent")
    func noTools() throws {
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
    func mixedTools() throws {
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
    func providerDefinedGoogleSearch() throws {
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
    func functionTools() throws {
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

        guard case let .array(toolsArray)? = prepared.tools else {
            Issue.record("Expected tools array")
            return
        }
        guard toolsArray.count == 1,
              case let .object(toolsObject) = toolsArray[0] else {
            Issue.record("Expected single tools entry object")
            return
        }
        guard let functionDeclarationsValue = toolsObject["functionDeclarations"],
              case let .array(functionDeclarations) = functionDeclarationsValue else {
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
