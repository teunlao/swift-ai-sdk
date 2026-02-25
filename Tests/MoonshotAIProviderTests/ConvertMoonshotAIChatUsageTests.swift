import Testing
@testable import MoonshotAIProvider
import AISDKProvider

@Suite("convertMoonshotAIChatUsage")
struct ConvertMoonshotAIChatUsageTests {
    @Test("nil usage returns empty usage object")
    func nilUsage() throws {
        let result = convertMoonshotAIChatUsage(nil)
        #expect(result.inputTokens.total == nil)
        #expect(result.outputTokens.total == nil)
        #expect(result.raw == nil)
    }

    @Test("uses cached_tokens when present")
    func usesCachedTokensTopLevel() throws {
        let usage: JSONValue = .object([
            "prompt_tokens": .number(20),
            "completion_tokens": .number(30),
            "cached_tokens": .number(7),
            "completion_tokens_details": .object([
                "reasoning_tokens": .number(10),
            ]),
        ])

        let result = convertMoonshotAIChatUsage(usage)
        #expect(result.inputTokens.total == 20)
        #expect(result.inputTokens.cacheRead == 7)
        #expect(result.inputTokens.noCache == 13)
        #expect(result.outputTokens.total == 30)
        #expect(result.outputTokens.reasoning == 10)
        #expect(result.outputTokens.text == 20)
    }

    @Test("falls back to prompt_tokens_details.cached_tokens")
    func fallsBackToPromptTokensDetails() throws {
        let usage: JSONValue = .object([
            "prompt_tokens": .number(20),
            "completion_tokens": .number(30),
            "prompt_tokens_details": .object([
                "cached_tokens": .number(5),
            ]),
        ])

        let result = convertMoonshotAIChatUsage(usage)
        #expect(result.inputTokens.total == 20)
        #expect(result.inputTokens.cacheRead == 5)
        #expect(result.inputTokens.noCache == 15)
    }
}

