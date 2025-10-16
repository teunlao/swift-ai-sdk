/**
 Tests for provider-defined tool factory helpers.

 Port of `@ai-sdk/provider-utils/src/provider-defined-tool-factory.ts`.
 */

import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

private actor Flag {
    private var value = false

    func set() {
        value = true
    }

    func isSet() -> Bool {
        value
    }
}

private struct CustomProviderOptions: Sendable {
    var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)?
    var outputSchema: FlexibleSchema<JSONValue>?
    var needsApproval: NeedsApproval?
    var maxUses: Int?
    var allowedDomains: [String]?
}

private func mapCustomOptions(
    _ options: CustomProviderOptions
) -> ProviderDefinedToolFactoryOptions {
    var args: [String: JSONValue] = [:]
    if let maxUses = options.maxUses {
        args["maxUses"] = JSONValue.number(Double(maxUses))
    }
    if let domains = options.allowedDomains {
        args["allowedDomains"] = JSONValue.array(domains.map { JSONValue.string($0) })
    }

    return ProviderDefinedToolFactoryOptions(
        execute: options.execute,
        outputSchema: options.outputSchema,
        needsApproval: options.needsApproval,
        args: args
    )
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

        let onStart = Flag()
        let onDelta = Flag()
        let onAvailable = Flag()

        let execute: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { input, _ in
            #expect(input == JSONValue.object(["prompt": JSONValue.string("hello")]))
            return .value(JSONValue.object(["result": JSONValue.string("ok")]))
        }

        let tool = factory(
            ProviderDefinedToolFactoryOptions(
                execute: execute,
                outputSchema: outputSchema,
                needsApproval: .always,
                toModelOutput: { value in
                    #expect(value == JSONValue.object(["result": JSONValue.string("ok")]))
                    return .json(value: value)
                },
                onInputStart: { _ in await onStart.set() },
                onInputDelta: { _ in await onDelta.set() },
                onInputAvailable: { _ in await onAvailable.set() },
                args: [
                    "mode": JSONValue.string("debug"),
                    "version": JSONValue.string("v1")
                ]
            )
        )

        #expect(tool.type == ToolType.providerDefined)
        #expect(tool.id == "provider.tool")
        #expect(tool.name == "provider-tool")
        #expect(tool.args?["mode"] == JSONValue.string("debug"))
        #expect(tool.args?["version"] == JSONValue.string("v1"))
        #expect(tool.needsApproval != nil)
        #expect(tool.onInputStart != nil)
        #expect(tool.onInputDelta != nil)
        #expect(tool.onInputAvailable != nil)
        #expect(tool.execute != nil)
        #expect(tool.outputSchema != nil)
        #expect(tool.toModelOutput != nil)

        let callOptions = ToolCallOptions(toolCallId: "call-1", messages: [])
        try await tool.onInputStart?(callOptions)
        try await tool.onInputDelta?(ToolCallDeltaOptions(inputTextDelta: "partial", toolCallId: "call-1", messages: []))
        try await tool.onInputAvailable?(ToolCallInputOptions(input: JSONValue.object(["prompt": JSONValue.string("hello")]), toolCallId: "call-1", messages: []))

        if let executeFn = tool.execute {
            let result = try await executeFn(JSONValue.object(["prompt": JSONValue.string("hello")]), callOptions)
            if case .value(let value) = result {
                #expect(value == JSONValue.object(["result": JSONValue.string("ok")]))
            } else {
                Issue.record("Expected .value result")
            }
        } else {
            Issue.record("Expected execute function")
        }

        #expect(await onStart.isSet())
        #expect(await onDelta.isSet())
        #expect(await onAvailable.isSet())

        let resolvedInput = try await tool.inputSchema.resolve().jsonSchema()
        let resolvedOutput = try await tool.outputSchema?.resolve().jsonSchema()

        #expect(resolvedInput == JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "prompt": .object(["type": .string("string")])
            ])
        ]))
        #expect(resolvedOutput == JSONValue.object([
            "type": .string("object"),
            "properties": .object([
                "result": .object(["type": .string("string")])
            ])
        ]))
    }

    @Test("factory defaults omit optional components")
    func factoryDefaults() {
        let inputSchema = FlexibleSchema(jsonSchema(JSONValue.object(["type": .string("string")])))

        let factory = createProviderDefinedToolFactory(
            id: "provider.simple",
            name: "simple",
            inputSchema: inputSchema
        )

        let tool = factory(ProviderDefinedToolFactoryOptions())

        #expect(tool.type == ToolType.providerDefined)
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
        let inputSchema = FlexibleSchema(jsonSchema(JSONValue.object(["type": .string("string")])))
        let outputSchema = FlexibleSchema(jsonSchema(JSONValue.object(["type": .string("string")])))

        let factory = createProviderDefinedToolFactory(
            id: "provider.custom",
            name: "custom-tool",
            inputSchema: inputSchema,
            mapOptions: mapCustomOptions
        )

        let tool = factory(
            CustomProviderOptions(
                execute: nil,
                outputSchema: outputSchema,
                needsApproval: .always,
                maxUses: 5,
                allowedDomains: ["example.com", "vercel.com"]
            )
        )

        #expect(tool.id == "provider.custom")
        #expect(tool.name == "custom-tool")
        switch tool.needsApproval {
        case .always?:
            break
        default:
            Issue.record("Expected needsApproval to be .always")
        }
        #expect(tool.args?["maxUses"] == JSONValue.number(5))
        #expect(tool.args?["allowedDomains"] == JSONValue.array([JSONValue.string("example.com"), JSONValue.string("vercel.com")]))
        let resolved = try await tool.outputSchema?.resolve().jsonSchema()
        let expected = try await outputSchema.resolve().jsonSchema()
        #expect(resolved == expected)
    }

    @Test("factory with predefined output schema ignores overrides")
    func factoryWithOutputSchemaEnforcesSchema() async throws {
        let inputSchema = FlexibleSchema(jsonSchema(JSONValue.object(["type": .string("string")])))
        let outputSchema = FlexibleSchema(jsonSchema(JSONValue.object(["type": .string("string")])))

        let factory = createProviderDefinedToolFactoryWithOutputSchema(
            id: "provider.output",
            name: "output-tool",
            inputSchema: inputSchema,
            outputSchema: outputSchema
        )

        let tool = factory(
            ProviderDefinedToolFactoryWithOutputSchemaOptions(
                args: ["mode": JSONValue.string("strict")]
            )
        )

        #expect(tool.id == "provider.output")
        #expect(tool.name == "output-tool")
        #expect(tool.args?["mode"] == JSONValue.string("strict"))
        let resolved = try await tool.outputSchema?.resolve().jsonSchema()
        let expected = try await outputSchema.resolve().jsonSchema()
        #expect(resolved == expected)
    }

    @Test("custom mapping for predefined output schema")
    func customMappingWithOutputSchema() async throws {
        struct CustomOutputOptions: Sendable {
            var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)?
            var args: [String: JSONValue]
        }

        let inputSchema = FlexibleSchema(jsonSchema(JSONValue.object(["type": .string("string")])))
        let outputSchema = FlexibleSchema(jsonSchema(JSONValue.object(["type": .string("string")])))

        let factory = createProviderDefinedToolFactoryWithOutputSchema(
            id: "provider.custom-output",
            name: "custom-output-tool",
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            mapOptions: { (options: CustomOutputOptions) in
                ProviderDefinedToolFactoryWithOutputSchemaOptions(
                    execute: options.execute,
                    args: options.args
                )
            }
        )

        let tool = factory(
            CustomOutputOptions(
                execute: { input, _ in
                    #expect(input == JSONValue.string("data"))
                    return .value(JSONValue.string("ok"))
                },
                args: ["mode": JSONValue.string("test")]
            )
        )

        #expect(tool.type == ToolType.providerDefined)
        #expect(tool.id == "provider.custom-output")
        #expect(tool.args?["mode"] == JSONValue.string("test"))
        let resolved = try await tool.outputSchema?.resolve().jsonSchema()
        let expected = try await outputSchema.resolve().jsonSchema()
        #expect(resolved == expected)
    }
}
