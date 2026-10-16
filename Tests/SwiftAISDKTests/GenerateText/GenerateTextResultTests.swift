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
            .text(text: "text-\(identifier)", citations: nil, providerMetadata: nil),
            .reasoning(ReasoningOutput(text: "why-\(identifier)")),
            .source(
                type: "doc",
                source: Source.url(
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

    @Test("aggregates content of all steps and reads text, finish reason and request from the final step")
    func aggregatesStepsAndReadsFinalStep() throws {
        let steps: [StepResult] = [
            makeStep(identifier: "one", finishReason: .toolCalls),
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
        #expect(result.content.count == 10)
        #expect(result.sources.count == 2)
        #expect(result.toolCalls.map(\.toolName) == ["tool-one", "tool-two"])
        #expect(result.toolResults.count == 2)
        #expect(result.finishReason == .stop)
        #expect(result.usage == totalUsage)
        #expect(result.responseMessages.count == 2)
        #expect(result.request.body == .string("request-two"))
        #expect(try result.output == "structured-output")
    }

    @Test("output throws NoOutputGeneratedError when no output was parsed")
    func outputMissing() throws {
        let steps: [StepResult] = [makeStep(identifier: "solo")]

        let result = DefaultGenerateTextResult<String>(
            steps: steps,
            totalUsage: steps[0].usage,
            resolvedOutput: nil
        )

        #expect(throws: NoOutputGeneratedError.self) {
            _ = try result.output
        }
    }
}
