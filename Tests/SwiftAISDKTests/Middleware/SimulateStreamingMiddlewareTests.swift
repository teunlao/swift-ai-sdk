import Foundation
import Testing
import AISDKProvider
import SwiftAISDK

@Suite("simulateStreamingMiddleware")
struct SimulateStreamingMiddlewareTests {
    private func simulate(_ result: LanguageModelV4GenerateResult) async throws -> (LanguageModelV4StreamResult, [LanguageModelV4StreamPart]) {
        let model = MockLanguageModelV4(doGenerate: .singleValue(result))
        let streamResult = try await wrapLanguageModel(model: model, middleware: simulateStreamingMiddleware())
            .doStream(options: LanguageModelV4CallOptions(prompt: middlewareTestPrompt))
        return (streamResult, try await collectStream(streamResult.stream))
    }

    @Test("replays generated content as stream parts in order")
    func replaysContent() async throws {
        let textMetadata: SharedV4ProviderMetadata = ["testProvider": ["signature": .string("text")]]
        let reasoningMetadata: SharedV4ProviderMetadata = ["testProvider": ["signature": .string("reasoning")]]
        let toolCall = LanguageModelV4ToolCall(toolCallId: "call-1", toolName: "weather", input: "{}")
        let warning = SharedV4Warning.other(message: "Test warning")
        let timestamp = Date(timeIntervalSince1970: 0)

        let (streamResult, parts) = try await simulate(LanguageModelV4GenerateResult(
            content: [
                .reasoning(LanguageModelV4Reasoning(text: "thinking", providerMetadata: reasoningMetadata)),
                .text(LanguageModelV4Text(text: "Hello", providerMetadata: textMetadata)),
                .text(LanguageModelV4Text(text: "")),
                .toolCall(toolCall),
                .text(LanguageModelV4Text(text: "Done")),
            ],
            finishReason: .init(unified: .toolCalls, raw: "tool_calls"),
            usage: middlewareTestUsage,
            providerMetadata: ["custom": ["key": .string("value")]],
            response: LanguageModelV4ResponseInfo(
                id: "id-1",
                timestamp: timestamp,
                modelId: "mock-model-id",
                headers: ["x-test": "1"]
            ),
            warnings: [warning]
        ))

        #expect(parts == [
            .streamStart(warnings: [warning]),
            .responseMetadata(id: "id-1", modelId: "mock-model-id", timestamp: timestamp),
            .reasoningStart(id: "0", providerMetadata: reasoningMetadata),
            .reasoningDelta(id: "0", delta: "thinking", providerMetadata: nil),
            .reasoningEnd(id: "0", providerMetadata: nil),
            .textStart(id: "1", providerMetadata: textMetadata),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .toolCall(toolCall),
            .textStart(id: "2", providerMetadata: nil),
            .textDelta(id: "2", delta: "Done", providerMetadata: nil),
            .textEnd(id: "2", providerMetadata: nil),
            .finish(
                finishReason: .init(unified: .toolCalls, raw: "tool_calls"),
                usage: middlewareTestUsage,
                providerMetadata: ["custom": ["key": .string("value")]]
            ),
        ])
        #expect(streamResult.response?.headers == ["x-test": "1"])
    }

    @Test("emits response metadata without a response and replays an empty text with citations")
    func emptyTextWithCitations() async throws {
        let citation = LanguageModelV4Citation(
            source: .url(id: "source-1", url: "https://example.com", title: nil, providerMetadata: nil)
        )

        let (_, parts) = try await simulate(LanguageModelV4GenerateResult(
            content: [.text(LanguageModelV4Text(text: "", citations: [citation]))],
            finishReason: .init(unified: .stop),
            usage: middlewareTestUsage
        ))

        #expect(parts == [
            .streamStart(warnings: []),
            .responseMetadata(id: nil, modelId: nil, timestamp: nil),
            .textStart(id: "0", providerMetadata: nil),
            .textDelta(id: "0", delta: "", providerMetadata: nil),
            .textEnd(id: "0", providerMetadata: nil, citations: [citation]),
            .finish(finishReason: .init(unified: .stop), usage: middlewareTestUsage, providerMetadata: nil),
        ])
    }
}
