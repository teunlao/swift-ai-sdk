import Testing
import AISDKProvider
import AlibabaProvider

@Suite("Alibaba cache boundary")
struct GetCacheControlTests {
    @Test("a fifth cache marker warns without deleting the request markers")
    func breakpointLimit() async throws {
        let endpoint = AlibabaTestEndpoint()
        let cache: SharedV4ProviderOptions = ["alibaba": ["cacheControl": ["type": "ephemeral"]]]
        let prompt = Array(repeating: LanguageModelV4Message.system(content: "cached", providerOptions: cache), count: 5)
        let result = try await alibabaTestModel(endpoint).doGenerate(options: .init(prompt: prompt))
        guard case .array(let messages) = try await endpoint.body()["messages"] else { Issue.record("Missing messages"); return }
        #expect(messages.count == 5)
        #expect(messages.allSatisfy { value in
            guard case .object(let message) = value, case .array(let parts) = message["content"], case .object(let part) = parts.first else { return false }
            return part["cache_control"] == ["type": "ephemeral"]
        })
        #expect(result.warnings.count == 1)
        #expect(result.warnings.contains { if case .other = $0 { true } else { false } })
    }

    @Test("nullish cacheControl falls back to cache_control while falsy markers are ignored")
    func nullishAndFalsy() async throws {
        let endpoint = AlibabaTestEndpoint()
        let prompt: LanguageModelV4Prompt = [
            .system(content: "fallback", providerOptions: ["alibaba": ["cacheControl": .null, "cache_control": ["type": "ephemeral"]]]),
            .system(content: "uncached", providerOptions: ["alibaba": ["cacheControl": false]])
        ]
        let result = try await alibabaTestModel(endpoint).doGenerate(options: .init(prompt: prompt))
        #expect(try await endpoint.body()["messages"] == [
            ["role": "system", "content": [["type": "text", "text": "fallback", "cache_control": ["type": "ephemeral"]]]],
            ["role": "system", "content": "uncached"]
        ])
        #expect(result.warnings.isEmpty)
    }
}
