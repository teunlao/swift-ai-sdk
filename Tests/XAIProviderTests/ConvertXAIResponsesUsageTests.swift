import Foundation
import Testing
@testable import AISDKProvider
@testable import XAIProvider

/**
 Tests for convertXaiResponsesUsage.

 Port of `@ai-sdk/xai/src/responses/convert-xai-responses-usage.test.ts`.
 */
@Suite("convertXaiResponsesUsage")
struct ConvertXAIResponsesUsageTests {
    @Test("converts basic usage without caching or reasoning")
    func convertsBasicUsage() throws {
        let usage = XAIResponsesUsage(
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: nil,
            inputTokensDetails: nil,
            outputTokensDetails: nil,
            numSourcesUsed: nil,
            numServerSideToolsUsed: nil
        )

        let result = convertXaiResponsesUsage(usage)

        #expect(result.inputTokens.total == 100)
        #expect(result.inputTokens.noCache == 100)
        #expect(result.inputTokens.cacheRead == 0)
        #expect(result.inputTokens.cacheWrite == nil)

        #expect(result.outputTokens.total == 50)
        #expect(result.outputTokens.text == 50)
        #expect(result.outputTokens.reasoning == 0)

        #expect(result.raw == .object([
            "input_tokens": .number(100),
            "output_tokens": .number(50)
        ]))
    }

    @Test("converts usage with reasoning tokens")
    func convertsReasoningTokens() throws {
        let usage = XAIResponsesUsage(
            inputTokens: 1941,
            outputTokens: 583,
            totalTokens: 2524,
            inputTokensDetails: nil,
            outputTokensDetails: .init(reasoningTokens: 380),
            numSourcesUsed: nil,
            numServerSideToolsUsed: nil
        )

        let result = convertXaiResponsesUsage(usage)

        #expect(result.outputTokens.total == 583)
        #expect(result.outputTokens.reasoning == 380)
        #expect(result.outputTokens.text == 203)
    }

    @Test("converts usage with cached input tokens")
    func convertsCachedInputTokens() throws {
        let usage = XAIResponsesUsage(
            inputTokens: 200,
            outputTokens: 50,
            totalTokens: nil,
            inputTokensDetails: .init(cachedTokens: 150),
            outputTokensDetails: nil,
            numSourcesUsed: nil,
            numServerSideToolsUsed: nil
        )

        let result = convertXaiResponsesUsage(usage)

        #expect(result.inputTokens.total == 200)
        #expect(result.inputTokens.noCache == 50)
        #expect(result.inputTokens.cacheRead == 150)
        #expect(result.inputTokens.cacheWrite == nil)
    }

    @Test("handles cached_tokens exceeding input_tokens (non-inclusive reporting)")
    func cachedTokensNonInclusiveReporting() throws {
        let usage = XAIResponsesUsage(
            inputTokens: 4142,
            outputTokens: 254,
            totalTokens: nil,
            inputTokensDetails: .init(cachedTokens: 4328),
            outputTokensDetails: nil,
            numSourcesUsed: nil,
            numServerSideToolsUsed: nil
        )

        let result = convertXaiResponsesUsage(usage)

        #expect(result.inputTokens.cacheRead == 4328)
        #expect(result.inputTokens.noCache == 4142)
        #expect(result.inputTokens.total == 8470)
    }

    @Test("converts usage with both cached input and reasoning")
    func cachedInputAndReasoning() throws {
        let usage = XAIResponsesUsage(
            inputTokens: 200,
            outputTokens: 583,
            totalTokens: nil,
            inputTokensDetails: .init(cachedTokens: 150),
            outputTokensDetails: .init(reasoningTokens: 380),
            numSourcesUsed: nil,
            numServerSideToolsUsed: nil
        )

        let result = convertXaiResponsesUsage(usage)

        #expect(result.inputTokens.total == 200)
        #expect(result.inputTokens.noCache == 50)
        #expect(result.inputTokens.cacheRead == 150)

        #expect(result.outputTokens.total == 583)
        #expect(result.outputTokens.reasoning == 380)
        #expect(result.outputTokens.text == 203)

        #expect(result.raw == .object([
            "input_tokens": .number(200),
            "input_tokens_details": .object([
                "cached_tokens": .number(150)
            ]),
            "output_tokens": .number(583),
            "output_tokens_details": .object([
                "reasoning_tokens": .number(380)
            ])
        ]))
    }

    @Test("preserves raw usage data")
    func preservesRawUsageData() throws {
        let rawUsage = XAIResponsesUsage(
            inputTokens: 12,
            outputTokens: 319,
            totalTokens: 331,
            inputTokensDetails: .init(cachedTokens: 2),
            outputTokensDetails: .init(reasoningTokens: 317),
            numSourcesUsed: nil,
            numServerSideToolsUsed: nil
        )

        let result = convertXaiResponsesUsage(rawUsage)
        #expect(result.raw == .object([
            "input_tokens": .number(12),
            "output_tokens": .number(319),
            "total_tokens": .number(331),
            "input_tokens_details": .object([
                "cached_tokens": .number(2)
            ]),
            "output_tokens_details": .object([
                "reasoning_tokens": .number(317)
            ])
        ]))
    }
}

