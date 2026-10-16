import Testing
import AISDKProvider
import AISDKProviderUtils

@Suite("Provider tool factory")
struct ProviderToolFactoryTests {
    @Test("provider-defined tools execute and map client results", arguments: [false, true])
    func definedToolsExecuteClientResults(predefinedOutput: Bool) async throws {
        let inputSchema = FlexibleSchema(jsonSchema(.object(["type": .string("string")])))
        let outputSchema = FlexibleSchema(jsonSchema(.object(["type": .string("number")])))
        let execute: @Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue> = { input, _ in
            #expect(input == .string("run"))
            return .value(.number(7))
        }
        let approval = NeedsApproval.conditional { input, _ in
            input == .string("run")
        }
        let toModelOutput: @Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput = { options in
            .json(value: .object(["result": options.output]))
        }

        let tool: Tool
        if predefinedOutput {
            let factory = createProviderDefinedToolFactoryWithOutputSchema(
                id: "provider.client",
                name: "client",
                inputSchema: inputSchema,
                outputSchema: outputSchema
            )
            tool = factory(.init(
                execute: execute,
                needsApproval: approval,
                toModelOutput: toModelOutput
            ))
        } else {
            let factory = createProviderDefinedToolFactory(
                id: "provider.client",
                name: "client",
                inputSchema: inputSchema
            )
            tool = factory(.init(
                execute: execute,
                outputSchema: outputSchema,
                needsApproval: approval,
                toModelOutput: toModelOutput
            ))
        }

        #expect(tool.isProviderExecuted == false)
        let input = JSONValue.string("run")
        guard case .conditional(let requiresApproval)? = tool.needsApproval else {
            Issue.record("Expected conditional client approval")
            return
        }
        #expect(try await requiresApproval(input, ToolCallApprovalOptions(toolCallId: "call-1", messages: [])))
        let executeFn = try #require(tool.execute)
        let output = try await executeFn(input, ToolExecutionOptions(toolCallId: "call-1", messages: [])).resolve()
        #expect(output == .number(7))
        let mapper = try #require(tool.toModelOutput)
        let modelOutput = try await mapper(.init(toolCallId: "call-1", input: input, output: output))
        #expect(modelOutput == .json(value: .object(["result": .number(7)])))
    }

    @Test("custom provider-defined options keep fixed output validation and execution")
    func customDefinedOptions() async throws {
        struct Options: Sendable {
            let result: JSONValue
        }

        let schema = FlexibleSchema(jsonSchema(.object(["type": .string("string")])))
        let factory = createProviderDefinedToolFactoryWithOutputSchema(
            id: "provider.custom",
            name: "custom",
            inputSchema: schema,
            outputSchema: schema,
            mapOptions: { (options: Options) in
                ProviderDefinedToolFactoryWithOutputSchemaOptions(execute: { _, _ in
                    .value(options.result)
                })
            }
        )
        let tool = factory(Options(result: .string("done")))
        let execute = try #require(tool.execute)
        let result = try await execute(.string("run"), ToolExecutionOptions(toolCallId: "call-1", messages: [])).resolve()
        #expect(result == .string("done"))
        let outputSchema = try #require(tool.outputSchema)
        let resolved = try await outputSchema.resolve()
        guard case .success(let validated) = await resolved.validate(result) else {
            Issue.record("Expected valid client tool result")
            return
        }
        #expect(validated == .string("done"))
        guard case .failure = await resolved.validate(JSONValue.number(7)) else {
            Issue.record("Expected output schema to reject a numeric result")
            return
        }
    }

    @Test("provider-executed tools keep deferred classification and validate provider results", arguments: [false, true])
    func executedToolsValidateProviderResults(deferred: Bool) async throws {
        let inputSchema = FlexibleSchema(jsonSchema(.object(["type": .string("object")])))
        let outputSchema = FlexibleSchema(jsonSchema(.object([
            "type": .string("object"),
            "properties": .object(["result": .object(["type": .string("string")])]),
            "required": .array([.string("result")]),
            "additionalProperties": .bool(false),
        ])))
        let factory = createProviderExecutedToolFactory(
            id: "provider.server",
            name: "server",
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            supportsDeferredResults: deferred
        )
        let tool = factory(.init())
        #expect(tool.isProviderExecuted == true)
        #expect(tool.supportsDeferredResults == deferred)
        let resultSchema = try #require(tool.outputSchema)
        let resolved = try await resultSchema.resolve()
        let result = JSONValue.object(["result": .string("done")])
        guard case .success(let validated) = await resolved.validate(result) else {
            Issue.record("Expected valid provider tool result")
            return
        }
        #expect(validated == result)
        guard case .failure = await resolved.validate(JSONValue.object([:])) else {
            Issue.record("Expected output schema to reject an incomplete provider result")
            return
        }
    }
}
