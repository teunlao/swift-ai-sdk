import Testing
import Foundation
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("GenerateTextResult Tests")
struct GenerateTextResultTests {
    private func makeStep(
        identifier: String,
        finishReason: FinishReason = .stop,
        usage: LanguageModelUsage = LanguageModelUsage(
            inputTokens: 3,
            outputTokens: 7,
            totalTokens: 10
        )
    ) -> StepResult {
        let toolCall = StaticToolCall(
            toolCallId: "call-\(identifier)",
            toolName: "tool-\(identifier)",
            input: .object(["value": .string(identifier)])
        )

        let toolResult = StaticToolResult(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: toolCall.input,
            output: .string("result-\(identifier)")
        )

        let content: [ContentPart] = [
            .text(text: "text-\(identifier)", providerMetadata: nil),
            .reasoning(ReasoningOutput(text: "why-\(identifier)")),
            .source(
                type: "doc",
                source: LanguageModelV3Source.url(
                    id: "s-\(identifier)",
                    url: "https://example.com/\(identifier)",
                    title: nil,
                    providerMetadata: nil
                )
            ),
            .toolCall(.static(toolCall), providerMetadata: nil),
            .toolResult(.static(toolResult), providerMetadata: nil)
        ]

        let responseMetadata = LanguageModelResponseMetadata(
            id: "resp-\(identifier)",
            timestamp: Date(timeIntervalSince1970: 1000),
            modelId: "model-\(identifier)",
            headers: ["X-Test": "header"]
        )

        let response = StepResultResponse(
            from: responseMetadata,
            messages: [
                .assistant(AssistantModelMessage(content: .text("assistant-\(identifier)")))
            ],
            body: .string("body-\(identifier)")
        )

        return DefaultStepResult(
            content: content,
            finishReason: finishReason,
            usage: usage,
            warnings: nil,
            request: LanguageModelRequestMetadata(body: .string("request-\(identifier)")),
            response: response,
            providerMetadata: nil
        )
    }

    @Test("returns final step values")
    func finalStepAccessors() throws {
        let steps: [StepResult] = [
            makeStep(identifier: "one"),
            makeStep(identifier: "two")
        ]

        let totalUsage = LanguageModelUsage(
            inputTokens: 6,
            outputTokens: 14,
            totalTokens: 20
        )

        let result = DefaultGenerateTextResult<String>(
            steps: steps,
            totalUsage: totalUsage,
            resolvedOutput: "structured-output"
        )

        #expect(result.text == "text-two")
        #expect(result.content.count == 5)
        #expect(result.files.isEmpty)
        #expect(result.sources.count == 1)
        #expect(result.toolCalls.map(\.toolName) == ["tool-two"])
        #expect(result.toolResults.count == 1)
        #expect(result.finishReason == .stop)
        #expect(result.usage.totalTokens == 10)
        #expect(result.totalUsage == totalUsage)
        #expect(result.steps.count == 2)
        #expect(result.response.messages.count == 1)
        #expect(result.request.body == .string("request-two"))
        #expect(try result.experimentalOutput == "structured-output")
    }

    @Test("throws when experimental output missing")
    func experimentalOutputMissing() {
        let steps: [StepResult] = [makeStep(identifier: "solo")]

        let result = DefaultGenerateTextResult<String>(
            steps: steps,
            totalUsage: steps[0].usage,
            resolvedOutput: nil
        )

        #expect(throws: NoOutputSpecifiedError.self) {
            _ = try result.experimentalOutput
        }
    }
}
