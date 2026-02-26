import Foundation
import Testing
import AISDKProvider
@testable import AmazonBedrockProvider

@Suite("BedrockPrepareTools")
struct BedrockPrepareToolsTests {
    @Test("maps toolChoice for function tools (auto/required/tool/none)")
    func mapsToolChoiceForFunctionTools() async throws {
        let tool = LanguageModelV3Tool.function(.init(
            name: "test-tool",
            inputSchema: .object(["type": .string("object")])
        ))

        let modelId = "meta.llama3-1-8b-instruct-v1:0"

        let auto = try await prepareBedrockTools(tools: [tool], toolChoice: .auto, modelId: modelId)
        #expect(auto.toolConfig["toolChoice"] == JSONValue.object(["auto": .object([:])]))

        let required = try await prepareBedrockTools(tools: [tool], toolChoice: .required, modelId: modelId)
        #expect(required.toolConfig["toolChoice"] == JSONValue.object(["any": .object([:])]))

        let named = try await prepareBedrockTools(tools: [tool], toolChoice: .tool(toolName: "test-tool"), modelId: modelId)
        #expect(named.toolConfig["toolChoice"] == JSONValue.object(["tool": .object(["name": .string("test-tool")])]))

        let none = try await prepareBedrockTools(tools: [tool], toolChoice: LanguageModelV3ToolChoice.none, modelId: modelId)
        #expect(none.toolConfig["tools"] == nil)
        #expect(none.toolConfig["toolChoice"] == nil)
    }

    @Test("omits blank descriptions for function tools")
    func omitsBlankDescriptions() async throws {
        let tool = LanguageModelV3Tool.function(.init(
            name: "test-tool",
            inputSchema: .object(["type": .string("object")]),
            description: "   \n  "
        ))

        let prepared = try await prepareBedrockTools(tools: [tool], toolChoice: .auto, modelId: "meta.llama3-1-8b-instruct-v1:0")
        guard case .array(let toolsArray) = prepared.toolConfig["tools"] else {
            Issue.record("Expected tools array")
            return
        }

        #expect(toolsArray.count == 1)
        guard case .object(let wrapper) = toolsArray[0],
              let toolSpecValue = wrapper["toolSpec"],
              case .object(let toolSpec) = toolSpecValue
        else {
            Issue.record("Expected toolSpec wrapper")
            return
        }

        #expect(toolSpec["name"] == JSONValue.string("test-tool"))
        #expect(toolSpec["description"] == nil)
    }

    @Test("allows mixing Anthropic provider tools and function tools for Anthropic models")
    func allowsMixingAnthropicProviderAndFunctionTools() async throws {
        let providerTool = LanguageModelV3Tool.provider(.init(
            id: "anthropic.bash_20241022",
            name: "bash",
            args: [:]
        ))

        let functionTool = LanguageModelV3Tool.function(.init(
            name: "fn",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false),
            ])
        ))

        let prepared = try await prepareBedrockTools(
            tools: [providerTool, functionTool],
            toolChoice: .auto,
            modelId: "anthropic.claude-3-haiku-20240307-v1:0"
        )

        guard case .array(let toolsArray) = prepared.toolConfig["tools"] else {
            Issue.record("Expected tools array")
            return
        }

        // Provider tool + function tool
        #expect(toolsArray.count == 2)

        // Anthropic tool choice is forwarded via additional model request fields.
        #expect(prepared.additionalTools?["tool_choice"] != nil)
        #expect(prepared.toolConfig["toolChoice"] == nil)
    }
}
