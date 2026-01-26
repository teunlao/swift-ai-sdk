/**
 Tests for Tool, tool(), and dynamicTool() functions.

 Port of `@ai-sdk/provider-utils/types/tool.ts` functionality tests.

 Note: Upstream does not have explicit tests for tool() and dynamicTool() helper functions,
 as they are simple wrappers. These tests verify the Swift implementation matches the expected behavior.
 */

import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("Tool Helper Functions")
struct ToolTests {

    // MARK: - tool() function tests

    @Test("tool() creates a Tool with correct properties")
    func toolFunction() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object([
            "type": .string("object"),
            "properties": .object([
                "message": .object(["type": .string("string")])
            ])
        ])))

        let createdTool = tool(
            description: "A test tool",
            inputSchema: schema
        )

        #expect(createdTool.description == "A test tool")
        #expect(createdTool.type == nil) // nil means 'function' type
        #expect(createdTool.execute == nil)
    }

    @Test("tool() with execute function")
    func toolWithExecute() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object(["type": .string("object")])))

        let executeFn: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { input, _ in
            return .value(JSONValue.string("result"))
        }

        let createdTool = tool(
            description: "Tool with execute",
            inputSchema: schema,
            execute: executeFn
        )

        #expect(createdTool.execute != nil)

        // Test execute
        let options = ToolCallOptions(
            toolCallId: "test-id",
            messages: []
        )
        let executionResult = try await createdTool.execute?(JSONValue.object([:]), options)
        let result = try await executionResult?.resolve()
        #expect(result == JSONValue.string("result"))
    }

    @Test("tool() with provider options")
    func toolWithProviderOptions() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object(["type": .string("object")])))

        let providerOpts: [String: JSONValue] = [
            "custom": JSONValue.string("value")
        ]

        let createdTool = tool(
            providerOptions: providerOpts,
            inputSchema: schema
        )

        #expect(createdTool.providerOptions?["custom"] == JSONValue.string("value"))
    }

    @Test("tool() with needsApproval always")
    func toolWithNeedsApprovalAlways() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object(["type": .string("object")])))

        let createdTool = tool(
            inputSchema: schema,
            needsApproval: .always
        )

        if case .always = createdTool.needsApproval {
            // Success
        } else {
            Issue.record("Expected needsApproval to be .always")
        }
    }

    @Test("tool() with callbacks")
    func toolWithCallbacks() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object(["type": .string("object")])))

        let createdTool = tool(
            inputSchema: schema,
            onInputStart: { _ in
                // Callback exists
            },
            onInputDelta: { _ in
                // Callback exists
            },
            onInputAvailable: { _ in
                // Callback exists
            }
        )

        #expect(createdTool.onInputStart != nil)
        #expect(createdTool.onInputDelta != nil)
        #expect(createdTool.onInputAvailable != nil)

        // Verify callbacks can be called without error
        let options = ToolCallOptions(toolCallId: "test", messages: [])
        try await createdTool.onInputStart?(options)

        let deltaOptions = ToolCallDeltaOptions(
            inputTextDelta: "delta",
            toolCallId: "test",
            messages: []
        )
        try await createdTool.onInputDelta?(deltaOptions)

        let inputOptions = ToolCallInputOptions(
            input: JSONValue.object([:]),
            toolCallId: "test",
            messages: []
        )
        try await createdTool.onInputAvailable?(inputOptions)
    }

    // MARK: - dynamicTool() function tests

    @Test("dynamicTool() creates a dynamic Tool")
    func dynamicToolFunction() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object(["type": .string("object")])))

        let executeFn: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { _, _ in
            return .value(JSONValue.string("dynamic result"))
        }

        let createdTool = dynamicTool(
            description: "A dynamic tool",
            inputSchema: schema,
            execute: executeFn
        )

        #expect(createdTool.description == "A dynamic tool")
        #expect(createdTool.type == ToolType.dynamic)
        #expect(createdTool.execute != nil)
    }

    @Test("dynamicTool() requires execute function")
    func dynamicToolWithExecute() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")])
            ])
        ])))

        let executeFn: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { input, options in
            // Dynamic tools process input at runtime
            return .value(JSONValue.object([
                "toolCallId": JSONValue.string(options.toolCallId),
                "processed": JSONValue.bool(true)
            ]))
        }

        let createdTool = dynamicTool(
            description: "MCP tool",
            inputSchema: schema,
            execute: executeFn
        )

        let options = ToolCallOptions(
            toolCallId: "mcp-call-1",
            messages: []
        )

        let executionResult = try await createdTool.execute?(JSONValue.object(["query": JSONValue.string("test")]), options)
        let result = try await executionResult?.resolve()

        #expect(result == JSONValue.object([
            "toolCallId": JSONValue.string("mcp-call-1"),
            "processed": JSONValue.bool(true)
        ]))
    }

    @Test("dynamicTool() with toModelOutput")
    func dynamicToolWithToModelOutput() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object(["type": .string("object")])))

        let executeFn: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { _, _ in
            return .value(JSONValue.string("result"))
        }

        let toModelOutputFn: @Sendable (JSONValue) -> LanguageModelV3ToolResultOutput = { output in
            return .text(value: "Formatted: \(output)")
        }

        let createdTool = dynamicTool(
            inputSchema: schema,
            execute: executeFn,
            toModelOutput: toModelOutputFn
        )

        #expect(createdTool.toModelOutput != nil)

        let output = createdTool.toModelOutput?(JSONValue.string("test"))
        if case .text(value: let text, providerOptions: _) = output {
            #expect(text == "Formatted: string(\"test\")")
        } else {
            Issue.record("Expected text output")
        }
    }

    @Test("dynamicTool() with provider options")
    func dynamicToolWithProviderOptions() async throws {
        let schema = FlexibleSchema<JSONValue>(jsonSchema(.object(["type": .string("object")])))

        let executeFn: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { _, _ in
            return .value(JSONValue.null)
        }

        let providerOpts: [String: JSONValue] = [
            "mcp": JSONValue.object([
                "server": JSONValue.string("local")
            ])
        ]

        let createdTool = dynamicTool(
            description: "MCP tool with options",
            providerOptions: providerOpts,
            inputSchema: schema,
            execute: executeFn
        )

        #expect(createdTool.providerOptions?["mcp"] == JSONValue.object([
            "server": JSONValue.string("local")
        ]))
        #expect(createdTool.type == ToolType.dynamic)
    }

    // MARK: - Tool type verification

    @Test("Tool type enum values match upstream")
    func toolTypeValues() throws {
        #expect(ToolType.function.rawValue == "function")
        #expect(ToolType.dynamic.rawValue == "dynamic")
        #expect(ToolType.providerDefined.rawValue == "provider-defined")
    }

    @Test("NeedsApproval enum cases")
    func needsApprovalCases() throws {
        let always = NeedsApproval.always
        let never = NeedsApproval.never

        // Verify cases exist
        if case .always = always {
            // Success
        } else {
            Issue.record("Expected .always case")
        }

        if case .never = never {
            // Success
        } else {
            Issue.record("Expected .never case")
        }
    }

    @Test("NeedsApproval conditional case")
    func needsApprovalConditional() async throws {
        let conditionalFn: @Sendable (JSONValue, ToolCallApprovalOptions) async throws -> Bool = { input, _ in
            // Approve if input contains "safe"
            if case .object(let obj) = input,
               case .string(let action) = obj["action"] {
                return action.contains("safe")
            }
            return false
        }

        let approval = NeedsApproval.conditional(conditionalFn)

        if case .conditional(let fn) = approval {
            let options = ToolCallApprovalOptions(
                toolCallId: "test",
                messages: []
            )

            let safeInput = JSONValue.object(["action": .string("safe-operation")])
            let unsafeInput = JSONValue.object(["action": .string("dangerous-operation")])

            let shouldApproveSafe = try await fn(safeInput, options)
            let shouldApproveUnsafe = try await fn(unsafeInput, options)

            #expect(shouldApproveSafe == true)
            #expect(shouldApproveUnsafe == false)
        } else {
            Issue.record("Expected .conditional case")
        }
    }
}
