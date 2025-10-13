import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

/**
 Tests for prepareToolsAndToolChoice function.

 Port of `@ai-sdk/ai/src/prompt/prepare-tools-and-tool-choice.test.ts`.
 */
struct PrepareToolsAndToolChoiceTests {

    // MARK: - Test 1: Undefined tools

    @Test("should return undefined for both tools and toolChoice when tools is not provided")
    func testReturnsUndefinedWhenToolsNotProvided() async throws {
        let result = try await prepareToolsAndToolChoice(
            tools: nil,
            toolChoice: nil,
            activeTools: nil
        )

        #expect(result.tools == nil)
        #expect(result.toolChoice == nil)
    }

    // MARK: - Test 2: All tools without activeTools

    @Test("should return all tools when activeTools is not provided")
    func testReturnsAllToolsWhenActiveToolsNotProvided() async throws {
        let mockTools = createMockTools()

        let result = try await prepareToolsAndToolChoice(
            tools: mockTools,
            toolChoice: nil,
            activeTools: nil
        )

        #expect(result.tools?.count == 2)
        #expect(result.toolChoice == .auto)

        // Verify tool1
        if case .function(let tool1) = result.tools?[0] {
            #expect(tool1.name == "tool1")
            #expect(tool1.description == "Tool 1 description")

            // Check JSON Schema structure
            if case .object(let schema) = tool1.inputSchema {
                // Check type field
                if case .string(let typeValue) = schema["type"] {
                    #expect(typeValue == "object")
                }
                if case .object(let properties) = schema["properties"] {
                    #expect(properties.isEmpty)
                }
            }
        } else {
            Issue.record("Expected function tool for tool1")
        }

        // Verify tool2
        if case .function(let tool2) = result.tools?[1] {
            #expect(tool2.name == "tool2")
            #expect(tool2.description == "Tool 2 description")

            // Check JSON Schema includes 'city' property
            if case .object(let schema) = tool2.inputSchema {
                if case .object(let properties) = schema["properties"] {
                    #expect(properties["city"] != nil)
                }
            }
        } else {
            Issue.record("Expected function tool for tool2")
        }
    }

    // MARK: - Test 3: Filter by activeTools

    @Test("should filter tools based on activeTools")
    func testFiltersToolsBasedOnActiveTools() async throws {
        let mockTools = createMockTools()

        let result = try await prepareToolsAndToolChoice(
            tools: mockTools,
            toolChoice: nil,
            activeTools: ["tool1"]
        )

        #expect(result.tools?.count == 1)
        #expect(result.toolChoice == .auto)

        if case .function(let tool) = result.tools?[0] {
            #expect(tool.name == "tool1")
        } else {
            Issue.record("Expected function tool for tool1")
        }
    }

    // MARK: - Test 4: String toolChoice

    @Test("should handle string toolChoice")
    func testHandlesStringToolChoice() async throws {
        let mockTools = createMockTools()

        let result = try await prepareToolsAndToolChoice(
            tools: mockTools,
            toolChoice: ToolChoice.none,
            activeTools: nil
        )

        #expect(result.tools?.count == 2)
        #expect(result.toolChoice == LanguageModelV3ToolChoice.none)
    }

    // MARK: - Test 5: Object toolChoice

    @Test("should handle object toolChoice")
    func testHandlesObjectToolChoice() async throws {
        let mockTools = createMockTools()

        let result = try await prepareToolsAndToolChoice(
            tools: mockTools,
            toolChoice: .tool(toolName: "tool2"),
            activeTools: nil
        )

        #expect(result.tools?.count == 2)
        #expect(result.toolChoice == .tool(toolName: "tool2"))
    }

    // MARK: - Test 6: Tool properties mapping

    @Test("should correctly map tool properties")
    func testCorrectlyMapsToolProperties() async throws {
        let mockTools = createMockTools()

        let result = try await prepareToolsAndToolChoice(
            tools: mockTools,
            toolChoice: nil,
            activeTools: nil
        )

        #expect(result.tools?.count == 2)
        #expect(result.toolChoice == .auto)

        // Detailed verification of tool1 structure
        if case .function(let tool1) = result.tools?[0] {
            #expect(tool1.name == "tool1")
            #expect(tool1.description == "Tool 1 description")
            #expect(tool1.providerOptions == nil)
        }
    }

    // MARK: - Test 7: Provider-defined tool

    @Test("should handle provider-defined tool type")
    func testHandlesProviderDefinedToolType() async throws {
        let mockToolsWithProviderDefined = createMockToolsWithProviderDefined()

        let result = try await prepareToolsAndToolChoice(
            tools: mockToolsWithProviderDefined,
            toolChoice: nil,
            activeTools: nil
        )

        #expect(result.tools?.count == 3)
        #expect(result.toolChoice == .auto)

        // Verify provider-defined tool (find by type, not index, since sorting may differ)
        let providerDefinedTool = result.tools?.first { tool in
            if case .providerDefined = tool {
                return true
            }
            return false
        }

        guard let providerDefinedTool else {
            Issue.record("Expected to find a provider-defined tool in results")
            return
        }

        if case .providerDefined(let providerTool) = providerDefinedTool {
            // Verify that dictionary key is used, not tool.name field
            #expect(providerTool.name == "providerTool", "Provider-defined tool should use dictionary key, not tool.name field")
            #expect(providerTool.id == "provider.tool-id")
            // args is [String: JSONValue], key should be "key"
            if case .string(let value) = providerTool.args["key"] {
                #expect(value == "value")
            } else {
                Issue.record("Expected string value in args")
            }
        }
    }

    // MARK: - Test 8: Provider options pass-through

    @Test("should pass through provider options")
    func testPassesThroughProviderOptions() async throws {
        let toolWithOptions: [String: Tool] = [
            "tool1": tool(
                description: "Tool 1 description",
                providerOptions: [
                    "aProvider": .object(["aSetting": .string("aValue")])
                ],
                inputSchema: FlexibleSchema(jsonSchema(
                    .object([
                        "$schema": .string("http://json-schema.org/draft-07/schema#"),
                        "type": .string("object"),
                        "properties": .object([:]),
                        "additionalProperties": .bool(false)
                    ])
                ))
            )
        ]

        let result = try await prepareToolsAndToolChoice(
            tools: toolWithOptions,
            toolChoice: nil,
            activeTools: nil
        )

        #expect(result.tools?.count == 1)
        #expect(result.toolChoice == .auto)

        if case .function(let tool) = result.tools?[0] {
            #expect(tool.providerOptions != nil)
            // Verify nested structure: SharedV3ProviderOptions is [String: [String: JSONValue]]
            // Tool.providerOptions values are already nested objects, extracted directly
            if let options = tool.providerOptions,
               let aProviderObj = options["aProvider"],
               case .string(let settingValue) = aProviderObj["aSetting"] {
                #expect(settingValue == "aValue", "Provider options should be passed through without extra wrapping")
            } else {
                Issue.record("Provider options structure mismatch")
            }
        }
    }

    // MARK: - Helper Functions

    private func createMockTools() -> [String: Tool] {
        [
            "tool1": tool(
                description: "Tool 1 description",
                inputSchema: FlexibleSchema(jsonSchema(
                    .object([
                        "$schema": .string("http://json-schema.org/draft-07/schema#"),
                        "type": .string("object"),
                        "properties": .object([:]),
                        "additionalProperties": .bool(false)
                    ])
                ))
            ),
            "tool2": tool(
                description: "Tool 2 description",
                inputSchema: FlexibleSchema(jsonSchema(
                    .object([
                        "$schema": .string("http://json-schema.org/draft-07/schema#"),
                        "type": .string("object"),
                        "properties": .object([
                            "city": .object([
                                "type": .string("string")
                            ])
                        ]),
                        "required": .array([.string("city")]),
                        "additionalProperties": .bool(false)
                    ])
                ))
            )
        ]
    }

    private func createMockToolsWithProviderDefined() -> [String: Tool] {
        var tools = createMockTools()

        // Provider-defined tool with different name than dictionary key
        // to test that dictionary key is used, not tool.name field
        tools["providerTool"] = Tool(
            providerOptions: nil,
            inputSchema: FlexibleSchema(jsonSchema(.object([
                "type": .string("object")
            ]))),
            type: .providerDefined,
            id: "provider.tool-id",
            name: "different-name",  // Different from dictionary key to test correct mapping
            args: ["key": .string("value")]
        )

        return tools
    }
}
