import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – deferred tool results")
struct StreamTextDeferredToolResultsTests {
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

    @Test("resolves deferred tool-error when tool-result arrives in a later step")
    func resolvesDeferredToolErrorLaterStep() async throws {
        let meta: ProviderMetadata = ["mock": ["k": .string("v")]]
        let tools: ToolSet = [
            "deferred_tool": deferredTool(),
        ]

        let step1Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-1",
                modelId: "mock-model-id",
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-1",
                toolName: "deferred_tool",
                input: #"{ "value": "test" }"#,
                providerExecuted: true
            )),
            .finish(
                finishReason: .toolCalls,
                usage: usage,
                providerMetadata: nil
            ),
        ]

        let step2Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-2",
                modelId: "mock-model-id",
                timestamp: Date(timeIntervalSince1970: 1)
            ),
            .toolResult(LanguageModelV3ToolResult(
                toolCallId: "call-1",
                toolName: "deferred_tool",
                result: .string("ERROR"),
                isError: true,
                providerExecuted: true,
                providerMetadata: meta
            )),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Final response", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: usage,
                providerMetadata: nil
            ),
        ]

        let model = MockLanguageModelV3(
            doStream: .array([
                LanguageModelV3StreamResult(stream: makeAsyncStream(from: step1Parts)),
                LanguageModelV3StreamResult(stream: makeAsyncStream(from: step2Parts)),
            ])
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test",
            tools: tools,
            stopWhen: [stepCountIs(3)]
        )

        let fullStream = try await convertReadableStreamToArray(result.fullStream)
        if let part = fullStream.first(where: { if case .toolError = $0 { return true } else { return false } }) {
            if case .toolError(let error) = part {
                #expect(error.providerMetadata == nil)
            }
        } else {
            Issue.record("Expected fullStream to contain a tool-error part.")
        }

        let steps = try await result.steps
        #expect(steps.count == 2)

        let content = try await result.content
        #expect(content.count == 2)

        if content.count >= 2 {
            if case .toolError(let error, let metadata) = content[0] {
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

            if case .text(let text, _) = content[1] {
                #expect(text == "Final response")
            } else {
                Issue.record("Expected text content part.")
            }
        }
    }

    @Test("does not start another step when deferred tool-error arrives in the same step")
    func noExtraStepWhenErrorInSameStep() async throws {
        let meta: ProviderMetadata = ["mock": ["k": .string("v")]]
        let tools: ToolSet = [
            "deferred_tool": deferredTool(),
        ]

        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-1",
                modelId: "mock-model-id",
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-1",
                toolName: "deferred_tool",
                input: #"{ "value": "test" }"#,
                providerExecuted: true
            )),
            .toolResult(LanguageModelV3ToolResult(
                toolCallId: "call-1",
                toolName: "deferred_tool",
                result: .string("ERROR"),
                isError: true,
                providerExecuted: true,
                providerMetadata: meta
            )),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Final response", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: usage,
                providerMetadata: nil
            ),
        ]

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: makeAsyncStream(from: parts)))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test",
            tools: tools,
            stopWhen: [stepCountIs(2)]
        )

        let fullStream = try await convertReadableStreamToArray(result.fullStream)
        if let part = fullStream.first(where: { if case .toolError = $0 { return true } else { return false } }) {
            if case .toolError(let error) = part {
                #expect(error.providerMetadata == nil)
            }
        } else {
            Issue.record("Expected fullStream to contain a tool-error part.")
        }

        let steps = try await result.steps
        #expect(steps.count == 1)

        let content = try await result.content
        #expect(content.count == 3)

        if content.count >= 3 {
            if case .toolCall(let call, _) = content[0] {
                #expect(call.toolCallId == "call-1")
                #expect(call.toolName == "deferred_tool")
                #expect(call.providerExecuted == true)
            } else {
                Issue.record("Expected tool-call content part.")
            }

            if case .toolError(let error, let metadata) = content[1] {
                #expect(error.toolCallId == "call-1")
                #expect(error.toolName == "deferred_tool")
                #expect(error.providerExecuted == true)
                #expect(error.isDynamic == false)
                #expect(error.providerMetadata == nil)
                #expect(metadata == nil)
            } else {
                Issue.record("Expected tool-error content part.")
            }

            if case .text(let text, _) = content[2] {
                #expect(text == "Final response")
            } else {
                Issue.record("Expected text content part.")
            }
        }
    }
}
