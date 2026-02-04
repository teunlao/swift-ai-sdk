import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("GenerateText – deferred tool results")
struct GenerateTextDeferredToolResultsTests {
    private let usage = LanguageModelV3Usage(
        inputTokens: .init(total: 1),
        outputTokens: .init(total: 1)
    )

    private func deferredTool() -> Tool {
        let inputSchema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false),
            ])
        ))

        let outputSchema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false),
            ])
        ))

        let factory = createProviderToolFactoryWithOutputSchema(
            id: "test.deferred_tool",
            name: "deferred_tool",
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            supportsDeferredResults: true
        )

        return factory(ProviderToolFactoryWithOutputSchemaOptions(args: [:]))
    }

    @Test("continues when provider tool result is deferred to a later step")
    func continuesWhenProviderToolResultDeferred() async throws {
        let meta: ProviderMetadata = ["mock": ["k": .string("v")]]
        let tools: ToolSet = [
            "deferred_tool": deferredTool(),
        ]

        let step1 = LanguageModelV3GenerateResult(
            content: [
                .toolCall(LanguageModelV3ToolCall(
                    toolCallId: "call-1",
                    toolName: "deferred_tool",
                    input: #"{ "value": "test" }"#,
                    providerExecuted: true
                ))
            ],
            finishReason: .toolCalls,
            usage: usage
        )

        let step2 = LanguageModelV3GenerateResult(
            content: [
                .toolResult(LanguageModelV3ToolResult(
                    toolCallId: "call-1",
                    toolName: "deferred_tool",
                    result: .string("ERROR"),
                    isError: true,
                    providerExecuted: true,
                    providerMetadata: meta
                )),
                .text(LanguageModelV3Text(text: "Final response")),
            ],
            finishReason: .stop,
            usage: usage
        )

        let model = MockLanguageModelV3(
            doGenerate: .array([step1, step2])
        )

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test",
            stopWhen: [stepCountIs(3)]
        )

        #expect(result.steps.count == 2)
        #expect(model.doGenerateCalls.count == 2)

        #expect(result.content.count == 2)

        if result.content.count >= 2 {
            if case .toolError(let error, let metadata) = result.content[0] {
                #expect(error.toolCallId == "call-1")
                #expect(error.toolName == "deferred_tool")
                #expect(error.input == .null)
                #expect(error.providerExecuted == true)
                #expect(error.isDynamic == false)
                #expect(error.providerMetadata == nil)
                #expect(metadata == nil)
            } else {
                Issue.record("Expected tool-error content part.")
            }

            if case .text(let text, _) = result.content[1] {
                #expect(text == "Final response")
            } else {
                Issue.record("Expected text content part.")
            }
        }
    }
}
