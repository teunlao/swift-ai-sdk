import Testing
import AISDKProvider
import AlibabaProvider

@Suite("Alibaba usage HTTP boundary")
struct ConvertAlibabaUsageTests {
    @Test("fractional and huge counts retain success raw and independent projections", arguments: [false, true])
    func numericUsage(huge: Bool) async throws {
        let value = huge ? 1e100 : 1.5
        let cached = huge ? 1e100 : 0.5
        let usage: JSONValue = ["prompt_tokens": .number(value), "completion_tokens": 1.5, "total_tokens": .number(1e100),
                                "prompt_tokens_details": ["cached_tokens": .number(cached), "cache_type": "explicit", "extra": true],
                                "completion_tokens_details": ["reasoning_tokens": 0.5], "future": 1.5]
        var response = alibabaTestResponse
        response["usage"] = usage
        let result = try await alibabaTestModel(AlibabaTestEndpoint(.object(response))).doGenerate(options: .init(prompt: alibabaTestPrompt))
        #expect(result.content == [.text(.init(text: "Answer"))])
        #expect(result.usage.inputTokens.total == nil)
        #expect(result.usage.inputTokens.cacheRead == nil)
        #expect(result.usage.inputTokens.noCache == (huge ? 0 : 1))
        #expect(result.usage.inputTokens.cacheWrite == 0)
        #expect(result.usage.outputTokens.total == nil)
        #expect(result.usage.outputTokens.text == 1)
        #expect(result.usage.outputTokens.reasoning == nil)
        #expect(result.usage.raw == usage)
    }
}
