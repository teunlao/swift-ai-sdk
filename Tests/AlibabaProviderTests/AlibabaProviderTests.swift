import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AlibabaProvider

@Suite("Alibaba provider API boundaries")
struct AlibabaProviderTests {
    @Test("stream usage setting is resolved by the provider factory", arguments: [false, true])
    func includeUsage(enabled: Bool) async throws {
        let endpoint = AlibabaTestEndpoint(events: [["choices": [], "usage": ["prompt_tokens": 1, "completion_tokens": 2, "total_tokens": 3]]])
        let result = try await alibabaTestModel(endpoint, includeUsage: enabled).doStream(options: .init(prompt: alibabaTestPrompt))
        let parts = try await collectAlibaba(result.stream)
        let body = try await endpoint.body()
        #expect(body["stream"] == true)
        #expect(body["stream_options"] == (enabled ? ["include_usage": true] : Optional<JSONValue>.none))
        guard case .finish(_, let usage, _) = parts.last else { Issue.record("Missing finish"); return }
        #expect(usage.inputTokens.total == 1)
    }

    @Test("custom chat endpoint keeps API authentication custom overrides and provider UA")
    func headersAndURL() async throws {
        let endpoint = AlibabaTestEndpoint()
        let provider = createAlibaba(settings: .init(baseURL: "https://proxy.example/v1/", apiKey: "key", headers: ["authorization": "Bearer custom"], fetch: { request in try await endpoint.fetch(request) }))
        let result = try await provider.chatModel(.qwenPlus).doGenerate(options: .init(prompt: alibabaTestPrompt, headers: ["X-Call": "call"]))
        let request = try await endpoint.request()
        #expect(request.url?.absoluteString == "https://proxy.example/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer custom")
        #expect(request.value(forHTTPHeaderField: "X-Call") == "call")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-alibaba/") == true)
        #expect(result.content == [.text(.init(text: "Answer"))])
    }

    @Suite("lazy credentials", .serialized)
    struct AuthTests {
        @Test("provider and models construct before a request loads a missing key")
        func missingKey() async throws {
            let original = getenv("ALIBABA_API_KEY").flatMap { String(validatingCString: $0) }
            defer { if let original { setenv("ALIBABA_API_KEY", original, 1) } else { unsetenv("ALIBABA_API_KEY") } }
            unsetenv("ALIBABA_API_KEY")
            let provider = createAlibaba()
            let chat = provider.languageModel(.qwenPlus)
            let embedding = provider.embedding(.textEmbeddingV4)
            await #expect(throws: LoadAPIKeyError.self) { try await chat.doGenerate(options: .init(prompt: alibabaTestPrompt)) }
            await #expect(throws: LoadAPIKeyError.self) { try await embedding.doEmbed(options: .init(values: ["text"])) }
        }
    }
}
