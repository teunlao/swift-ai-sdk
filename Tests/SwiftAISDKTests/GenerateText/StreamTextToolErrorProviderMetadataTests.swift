import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – tool-error providerMetadata")
struct StreamTextToolErrorProviderMetadataTests {
    private let usage = LanguageModelV3Usage(
        inputTokens: .init(total: 1),
        outputTokens: .init(total: 1)
    )

    private let schema = FlexibleSchema(jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "q": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("q")]),
            "additionalProperties": .bool(false),
        ])
    ))

    @Test("tool errors preserve providerMetadata from tool call")
    func toolErrorsPreserveProviderMetadataFromToolCall() async throws {
        let meta: ProviderMetadata = ["prov": ["tag": .string("m")]]
        let tool = Tool(
            description: "Demo",
            inputSchema: schema,
            execute: { _, _ in
                throw NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
            }
        )

        let tools: ToolSet = ["demo": tool]

        let step1Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-1",
                modelId: "mock-model-id",
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-1",
                toolName: "demo",
                input: #"{ "q": "hi" }"#,
                providerExecuted: false,
                providerMetadata: meta
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
                #expect(error.providerMetadata == meta)
            }
        } else {
            Issue.record("Expected fullStream to contain a tool-error part.")
        }

        let content = try await result.content
        if let part = content.first(where: { if case .toolError = $0 { return true } else { return false } }) {
            if case .toolError(let error, let providerMetadata) = part {
                #expect(error.providerMetadata == meta)
                #expect(providerMetadata == meta)
            }
        } else {
            Issue.record("Expected content to contain a tool-error part.")
        }
    }
}
