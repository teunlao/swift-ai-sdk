import Testing
@testable import AlibabaProvider

@Suite("convertAlibabaUsage")
struct ConvertAlibabaUsageTests {
    @Test("calculates token distribution with cache tokens")
    func calculatesCacheTokens() {
        let result = convertAlibabaUsage(AlibabaUsage(
            promptTokens: 200,
            completionTokens: 75,
            promptTokensDetails: .init(
                cachedTokens: 120,
                cacheCreationInputTokens: 50
            ),
            completionTokensDetails: .init(reasoningTokens: 25)
        ))

        #expect(result.inputTokens.total == 200)
        #expect(result.inputTokens.cacheRead == 120)
        #expect(result.inputTokens.cacheWrite == 50)
        #expect(result.inputTokens.noCache == 30)
    }
}

