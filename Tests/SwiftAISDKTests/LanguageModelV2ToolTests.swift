import Foundation
import Testing
@testable import SwiftAISDK

/**
 * Tests for LanguageModelV2 Tool types
 *
 * Tests ToolCall, ToolResult, ToolChoice, FunctionTool, ProviderDefinedTool
 */

@Suite("LanguageModelV2 Tool Types")
struct LanguageModelV2ToolTests {

    // MARK: - ToolCall

    @Test("ToolCall: encode/decode with all fields")
    func toolCall_fullFields() throws {
        let pm: SharedV2ProviderMetadata = ["provider": ["cached": .bool(true)]]
        let toolCall = LanguageModelV2ToolCall(
            toolCallId: "call_abc123",
            toolName: "getWeather",
            input: "{\"city\":\"London\",\"units\":\"metric\"}",
            providerExecuted: true,
            providerMetadata: pm
        )

        let encoded = try JSONEncoder().encode(toolCall)
        let decoded = try JSONDecoder().decode(LanguageModelV2ToolCall.self, from: encoded)

        #expect(decoded.toolCallId == "call_abc123")
        #expect(decoded.toolName == "getWeather")
        #expect(decoded.input == "{\"city\":\"London\",\"units\":\"metric\"}")
        #expect(decoded.providerExecuted == true)
        #expect(decoded.providerMetadata == pm)
    }

    @Test("ToolCall: encode without optional fields")
    func toolCall_minimalFields() throws {
        let toolCall = LanguageModelV2ToolCall(
            toolCallId: "call_xyz",
            toolName: "calculate",
            input: "{}",
            providerExecuted: nil,
            providerMetadata: nil
        )

        let encoded = try JSONEncoder().encode(toolCall)
        let decoded = try JSONDecoder().decode(LanguageModelV2ToolCall.self, from: encoded)

        #expect(decoded.toolCallId == "call_xyz")
        #expect(decoded.toolName == "calculate")
        #expect(decoded.providerExecuted == nil)
        #expect(decoded.providerMetadata == nil)
    }

    // MARK: - ToolResult

    @Test("ToolResult: encode/decode with success result")
    func toolResult_success() throws {
        let result: JSONValue = [
            "temperature": .number(22),
            "condition": .string("sunny"),
            "humidity": .number(65)
        ]

        let toolResult = LanguageModelV2ToolResult(
            toolCallId: "call_abc123",
            toolName: "getWeather",
            result: result,
            isError: false,
            providerExecuted: true,
            providerMetadata: ["meta": ["source": .string("cache")]]
        )

        let encoded = try JSONEncoder().encode(toolResult)
        let decoded = try JSONDecoder().decode(LanguageModelV2ToolResult.self, from: encoded)

        #expect(decoded.toolCallId == "call_abc123")
        #expect(decoded.toolName == "getWeather")
        #expect(decoded.result == result)
        #expect(decoded.isError == false)
    }

    @Test("ToolResult: encode/decode with error result")
    func toolResult_error() throws {
        let errorResult: JSONValue = [
            "error": .string("API rate limit exceeded"),
            "code": .number(429)
        ]

        let toolResult = LanguageModelV2ToolResult(
            toolCallId: "call_fail",
            toolName: "expensiveAPI",
            result: errorResult,
            isError: true,
            providerExecuted: nil,
            providerMetadata: nil
        )

        let encoded = try JSONEncoder().encode(toolResult)
        let decoded = try JSONDecoder().decode(LanguageModelV2ToolResult.self, from: encoded)

        #expect(decoded.isError == true)
        #expect(decoded.result == errorResult)
    }

    // MARK: - ToolChoice

    @Test("ToolChoice: auto variant")
    func toolChoice_auto() throws {
        let choice = LanguageModelV2ToolChoice.auto

        let encoded = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(LanguageModelV2ToolChoice.self, from: encoded)

        #expect(decoded == .auto)
    }

    @Test("ToolChoice: none variant")
    func toolChoice_none() throws {
        let choice = LanguageModelV2ToolChoice.none

        let encoded = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(LanguageModelV2ToolChoice.self, from: encoded)

        #expect(decoded == .none)
    }

    @Test("ToolChoice: required variant")
    func toolChoice_required() throws {
        let choice = LanguageModelV2ToolChoice.required

        let encoded = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(LanguageModelV2ToolChoice.self, from: encoded)

        #expect(decoded == .required)
    }

    @Test("ToolChoice: tool variant with name")
    func toolChoice_specificTool() throws {
        let choice = LanguageModelV2ToolChoice.tool(toolName: "calculator")

        let encoded = try JSONEncoder().encode(choice)
        let decoded = try JSONDecoder().decode(LanguageModelV2ToolChoice.self, from: encoded)

        guard case .tool(let toolName) = decoded else {
            #expect(Bool(false), "Expected tool variant")
            return
        }
        #expect(toolName == "calculator")
    }

    // MARK: - FunctionTool

    @Test("FunctionTool: encode/decode with full schema")
    func functionTool_fullSchema() throws {
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

        let tool = LanguageModelV2FunctionTool(
            name: "getWeather",
            inputSchema: schema,
            description: "Get current weather for a location"
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(LanguageModelV2FunctionTool.self, from: encoded)

        #expect(decoded.name == "getWeather")
        #expect(decoded.description == "Get current weather for a location")
        #expect(decoded.inputSchema == schema)
    }

    @Test("FunctionTool: encode without description")
    func functionTool_noDescription() throws {
        let schema: JSONValue = ["type": .string("object")]

        let tool = LanguageModelV2FunctionTool(
            name: "simpleFunction",
            inputSchema: schema,
            description: nil
        )

        let encoded = try JSONEncoder().encode(tool)
        let json = String(data: encoded, encoding: .utf8)!

        #expect(!json.contains("description"))

        let decoded = try JSONDecoder().decode(LanguageModelV2FunctionTool.self, from: encoded)
        #expect(decoded.name == "simpleFunction")
        #expect(decoded.description == nil)
    }

    // MARK: - ProviderDefinedTool

    @Test("ProviderDefinedTool: encode/decode")
    func providerDefinedTool_roundTrip() throws {
        let tool = LanguageModelV2ProviderDefinedTool(
            id: "openai.search",
            name: "webSearch",
            args: [
                "maxResults": .number(10),
                "includeImages": .bool(true)
            ]
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(LanguageModelV2ProviderDefinedTool.self, from: encoded)

        #expect(decoded.id == "openai.search")
        #expect(decoded.name == "webSearch")
        #expect(decoded.args["maxResults"] == .number(10))
        #expect(decoded.args["includeImages"] == .bool(true))
    }

    @Test("ProviderDefinedTool: encode with empty args")
    func providerDefinedTool_emptyArgs() throws {
        let tool = LanguageModelV2ProviderDefinedTool(
            id: "provider.simple",
            name: "simpleTool",
            args: [:]
        )

        let encoded = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(LanguageModelV2ProviderDefinedTool.self, from: encoded)

        #expect(decoded.id == "provider.simple")
        #expect(decoded.name == "simpleTool")
        #expect(decoded.args.isEmpty)
    }
}
