import Foundation
import Testing
@testable import SwiftAISDK

/**
 * Tests for LanguageModelV3 Tool types
 *
 * Tests ToolCall, ToolResult, ToolChoice, FunctionTool, ProviderDefinedTool
 */

@Suite("LanguageModelV3 Tool Types")
struct LanguageModelV3ToolTests {

    // MARK: - ToolCall

    @Test("ToolCall: encode/decode with all fields")
    func v3_toolCall_fullFields() throws {
        let pm: SharedV3ProviderMetadata = ["provider": ["cached": .bool(true)]]
        let toolCall = LanguageModelV3ToolCall(
            toolCallId: "call_abc123",
            toolName: "getWeather",
            input: "{\"city\":\"London\",\"units\":\"metric\"}",
            providerExecuted: true,
            providerMetadata: pm
        )

        let encoded = try JSONEncoder().encode(toolCall)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolCall.self, from: encoded)

        #expect(decoded.toolCallId == "call_abc123")
        #expect(decoded.toolName == "getWeather")
        #expect(decoded.input == "{\"city\":\"London\",\"units\":\"metric\"}")
        #expect(decoded.providerExecuted == true)
        #expect(decoded.providerMetadata == pm)
    }

    @Test("ToolCall: encode without optional fields")
    func v3_toolCall_minimalFields() throws {
        let toolCall = LanguageModelV3ToolCall(
            toolCallId: "call_xyz",
            toolName: "calculate",
            input: "{}",
            providerExecuted: nil,
            providerMetadata: nil
        )

        let encoded = try JSONEncoder().encode(toolCall)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolCall.self, from: encoded)

        #expect(decoded.toolCallId == "call_xyz")
        #expect(decoded.toolName == "calculate")
        #expect(decoded.providerExecuted == nil)
        #expect(decoded.providerMetadata == nil)
    }

    // MARK: - ToolChoice

    @Test("ToolChoice: auto variant")
    func v3_toolChoice_auto() throws {
        let choice = LanguageModelV3ToolChoice.auto

        let encoded = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolChoice.self, from: encoded)

        #expect(decoded == .auto)
    }

    @Test("ToolChoice: none variant")
    func v3_toolChoice_none() throws {
        let choice = LanguageModelV3ToolChoice.none

        let encoded = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolChoice.self, from: encoded)

        #expect(decoded == .none)
    }

    @Test("ToolChoice: required variant")
    func v3_toolChoice_required() throws {
        let choice = LanguageModelV3ToolChoice.required

        let encoded = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolChoice.self, from: encoded)

        #expect(decoded == .required)
    }

    @Test("ToolChoice: tool variant with name")
    func v3_toolChoice_specificTool() throws {
        let choice = LanguageModelV3ToolChoice.tool(toolName: "calculator")

        let encoded = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(LanguageModelV3ToolChoice.self, from: encoded)

        guard case .tool(let toolName) = decoded else {
            #expect(Bool(false), "Expected tool variant")
            return
        }
        #expect(toolName == "calculator")
    }

    // MARK: - FunctionTool

    @Test("FunctionTool: encode/decode with full schema")
    func v3_functionTool_fullSchema() throws {
        let schema: JSONValue = [
            "type": .string("object"),
            "properties": [
                "location": [
                    "type": .string("string"),
                    "description": .string("City name")
                ],
                "units": [
                    "type": .string("string"),
                    "enum": .array([.string("celsius"), .string("fahrenheit")])
                ]
            ],
            "required": .array([.string("location")])
        ]

        let tool = LanguageModelV3FunctionTool(
            name: "getWeather",
            inputSchema: schema,
            description: "Get current weather for a location"
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(LanguageModelV3FunctionTool.self, from: encoded)

        #expect(decoded.name == "getWeather")
        #expect(decoded.description == "Get current weather for a location")
        #expect(decoded.inputSchema == schema)
    }

    @Test("FunctionTool: encode without description")
    func v3_functionTool_noDescription() throws {
        let schema: JSONValue = ["type": .string("object")]

        let tool = LanguageModelV3FunctionTool(
            name: "simpleFunction",
            inputSchema: schema,
            description: nil
        )

        let encoded = try JSONEncoder().encode(tool)
        let json = String(data: encoded, encoding: .utf8)!

        #expect(!json.contains("description"))

        let decoded = try JSONDecoder().decode(LanguageModelV3FunctionTool.self, from: encoded)
        #expect(decoded.name == "simpleFunction")
        #expect(decoded.description == nil)
    }

    // MARK: - ProviderDefinedTool

    @Test("ProviderDefinedTool: encode/decode")
    func v3_providerDefinedTool_roundTrip() throws {
        let tool = LanguageModelV3ProviderDefinedTool(
            id: "openai.search",
            name: "webSearch",
            args: [
                "maxResults": .number(10),
                "includeImages": .bool(true)
            ]
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(LanguageModelV3ProviderDefinedTool.self, from: encoded)

        #expect(decoded.id == "openai.search")
        #expect(decoded.name == "webSearch")
        #expect(decoded.args["maxResults"] == .number(10))
        #expect(decoded.args["includeImages"] == .bool(true))
    }

    @Test("ProviderDefinedTool: encode with empty args")
    func v3_providerDefinedTool_emptyArgs() throws {
        let tool = LanguageModelV3ProviderDefinedTool(
            id: "provider.simple",
            name: "simpleTool",
            args: [:]
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(LanguageModelV3ProviderDefinedTool.self, from: encoded)

        #expect(decoded.id == "provider.simple")
        #expect(decoded.name == "simpleTool")
        #expect(decoded.args.isEmpty)
    }
}
