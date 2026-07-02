import Testing
@testable import AISDKProvider
@testable import SwiftAISDK

@Suite("LanguageModelUsage")
struct LanguageModelUsageTests {
    @Test("converts V4 provider usage to AI-level usage")
    func convertsV4Usage() {
        let usage = asLanguageModelUsage(
            LanguageModelV4Usage(
                inputTokens: .init(
                    total: 10,
                    noCache: 7,
                    cacheRead: 2,
                    cacheWrite: 1
                ),
                outputTokens: .init(
                    total: 6,
                    text: 4,
                    reasoning: 2
                ),
                raw: .object(["provider": .string("raw")])
            )
        )

        #expect(usage.inputTokens == 10)
        #expect(usage.inputTokenDetails.noCacheTokens == 7)
        #expect(usage.inputTokenDetails.cacheReadTokens == 2)
        #expect(usage.inputTokenDetails.cacheWriteTokens == 1)
        #expect(usage.outputTokens == 6)
        #expect(usage.outputTokenDetails.textTokens == 4)
        #expect(usage.outputTokenDetails.reasoningTokens == 2)
        #expect(usage.totalTokens == 16)
        #expect(usage.raw == ["provider": .string("raw")])
    }

    @Test("keeps total tokens nil when V4 input and output totals are both absent")
    func keepsV4TotalTokensNilWhenTotalsAreAbsent() {
        let usage = asLanguageModelUsage(LanguageModelV4Usage())

        #expect(usage.inputTokens == nil)
        #expect(usage.outputTokens == nil)
        #expect(usage.totalTokens == nil)
    }
}
