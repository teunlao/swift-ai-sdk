/**
 Tests for provider-defined tool factory helpers.

 Port of `@ai-sdk/provider-utils/src/provider-defined-tool-factory.ts`.
 */

import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

private actor BoolFlag {
    private var value = false

    func setTrue() {
        value = true
    }

    func isTrue() -> Bool {
        value
    }
}

private struct CustomProviderOptions: ProviderDefinedToolFactoryOptionsConvertible {
    var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)?
    var outputSchema: FlexibleSchema<JSONValue>?
    var needsApproval: NeedsApproval?
    var toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)?
    var onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)?
    var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?
    var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?

    /// Provider-specific fields exposed at the top level.
    var maxUses: Int?
    var allowedDomains: [String]?

    init(
        execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)? = nil,
        outputSchema: FlexibleSchema<JSONValue>? = nil,
        needsApproval: NeedsApproval? = nil,
        toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)? = nil,
        onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
        onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
        onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
        maxUses: Int? = nil,
        allowedDomains: [String]? = nil
    ) {
        self.execute = execute
        self.outputSchema = outputSchema
        self.needsApproval = needsApproval
        self.toModelOutput = toModelOutput
        self.onInputStart = onInputStart
        self.onInputDelta = onInputDelta
        self.onInputAvailable = onInputAvailable
        self.maxUses = maxUses
        self.allowedDomains = allowedDomains
    }

    var args: [String: JSONValue] {
        var result: [String: JSONValue] = [:]

        if let maxUses {
            result["maxUses"] = .number(Double(maxUses))
        }

        if let allowedDomains {
            result["allowedDomains"] = .array(allowedDomains.map { .string($0) })
        }

        return result
    }
}

@Suite("Provider-defined tool factory")
struct ProviderDefinedToolFactoryTests {

    @Test("createProviderDefinedToolFactory builds provider-defined Tool")
    func createFactoryProducesTool() async throws {
        let inputSchema = FlexibleSchema(
            jsonSchema(
                JSONValue.object([
                    "type": .string("object"),
                    "properties": .object([
                        "prompt": .object(["type": .string("string")])
                    ])
                ])
            )
        )

        let outputSchema = FlexibleSchema(
            jsonSchema(
                JSONValue.object([
                    "type": .string("object"),
                    "properties": .object([
                        "result": .object(["type": .string("string")])
                    ])
                ])
            )
        )

        let factory = createProviderDefinedToolFactory(
            id: "provider.tool",
            name: "provider-tool",
            inputSchema: inputSchema
        )

        let execute: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { input, _ in
            #expect(input == JSONValue.object([
                "prompt": .string("hello")
            ]))
            return .value(JSONValue.object(["result": .string("ok")]))
        }

        let onInputStartCalled = BoolFlag()
        let onInputDeltaCalled = BoolFlag()
        let onInputAvailableCalled = BoolFlag()

        let tool = factory(
            ProviderDefinedToolFactoryOptions(
                execute: execute,
                outputSchema: outputSchema,
                needsApproval: .always,
                toModelOutput: { output in
                    #expect(output == JSONValue.object(["result": .string("ok")]))
                    return .json(value: output)
                },
                onInputStart: { _ in await onInputStartCalled.setTrue() },
                onInputDelta: { _ in await onInputDeltaCalled.setTrue() },
                onInputAvailable: { _ in await onInputAvailableCalled.setTrue() },
                args: [
                    "mode": .string("debug"),
                    "version": .string("v1")
                ]
            )
        )

        #expect(tool.type == .providerDefined)
        #expect(tool.id == "provider.tool")
        #expect(tool.name == "provider-tool")
        #expect(tool.args?["mode"] == .string("debug"))
        #expect(tool.args?["version"] == .string("v1"))
        #expect(tool.needsApproval != nil)
        #expect(tool.onInputStart != nil)
        #expect(tool.onInputDelta != nil)
        #expect(tool.onInputAvailable != nil)
        #expect(tool.execute != nil)
        #expect(tool.outputSchema != nil)
        #expect(tool.toModelOutput != nil)

        // Verify callbacks execute without throwing.
        let callOptions = ToolCallOptions(toolCallId: "call-1", messages: [])
        try await tool.onInputStart?(callOptions)

        let deltaOptions = ToolCallDeltaOptions(
            inputTextDelta: "prompt partial",
            toolCallId: "call-1",
            messages: []
        )
        try await tool.onInputDelta?(deltaOptions)

        let inputOptions = ToolCallInputOptions(
            input: JSONValue.object(["prompt": .string("hello")]),
            toolCallId: "call-1",
            messages: []
        )
        try await tool.onInputAvailable?(inputOptions)

        // Execute the tool and check the result propagates through ToolExecutionResult.
        if let executeFn = tool.execute {
            let result = try await executeFn(
                JSONValue.object(["prompt": .string("hello")]),
                callOptions
            )
            if case .value(let value) = result {
                #expect(value == JSONValue.object(["result": .string("ok")]))
            } else {
                Issue.record("Expected tool execution to return .value result")
            }
        } else {
            Issue.record("Expected execute function to be set")
        }

        #expect(await onInputStartCalled.isTrue())
        #expect(await onInputDeltaCalled.isTrue())
        #expect(await onInputAvailableCalled.isTrue())

        // Ensure schemas were assigned by comparing resolved JSON schema shapes.
        let inputSchemaJSON = try await tool.inputSchema.resolve().jsonSchema()
        let outputSchemaJSON = try await tool.outputSchema?.resolve().jsonSchema()

        #expect(inputSchemaJSON == JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "prompt": .object(["type": .string("string")])
            ])
        ]))
        #expect(outputSchemaJSON == JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "result": .object(["type": .string("string")])
            ])
        ]))
    }

    @Test("factory defaults omit optional components")
    func factoryDefaults() async throws {
        let inputSchema = FlexibleSchema(
            jsonSchema(JSONValue.object(["type": .string("string")]))
        )

        let factory = createProviderDefinedToolFactory(
            id: "provider.simple",
            name: "simple",
            inputSchema: inputSchema
        )

        let tool = factory(ProviderDefinedToolFactoryOptions())

        #expect(tool.type == .providerDefined)
        #expect(tool.id == "provider.simple")
        #expect(tool.name == "simple")
        #expect(tool.execute == nil)
        #expect(tool.outputSchema == nil)
        #expect(tool.onInputStart == nil)
        #expect(tool.onInputDelta == nil)
        #expect(tool.onInputAvailable == nil)
        #expect(tool.args == [:])
        #expect(tool.toModelOutput == nil)
    }

    @Test("custom options support provider-specific top-level fields")
    func customOptionsExposeProviderArgs() async throws {
        let inputSchema = FlexibleSchema(
            jsonSchema(JSONValue.object(["type": .string("string")]))
        )
        let outputSchema = FlexibleSchema(
            jsonSchema(JSONValue.object(["type": .string("string")]))
        )

        let factory = createProviderDefinedToolFactory(
            id: "provider.custom",
            name: "custom-tool",
            inputSchema: inputSchema,
            optionsType: CustomProviderOptions.self
        )

        let tool = factory(
            CustomProviderOptions(
                outputSchema: outputSchema,
                needsApproval: .always,
                maxUses: 5,
                allowedDomains: ["example.com", "vercel.com"]
            )
        )

        #expect(tool.id == "provider.custom")
        #expect(tool.name == "custom-tool")
        #expect(tool.args?["maxUses"] == .number(5))
        #expect(tool.args?["allowedDomains"] == .array([.string("example.com"), .string("vercel.com")]))
        #expect(tool.outputSchema != nil)
        #expect(tool.needsApproval != nil)
    }
}
