import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import PerplexityProvider

@Suite("PerplexityProvider")
struct PerplexityProviderTests {
    @Test("default Agent endpoint sends the integration header and lazy provider authentication")
    func agentRequest() async throws {
        let response = #"{"id":"agent-1","created_at":1700000000,"model":"perplexity/sonar","object":"response","output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}],"status":"completed"}"#
        let provider = createPerplexity(settings: .init(apiKey: "key", headers: ["X-Provider": "provider"], fetch: { request in
            #expect(request.url?.absoluteString == "https://api.perplexity.ai/v1/agent")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "X-Pplx-Integration") == "vercel-ai-sdk")
            #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
            #expect(request.value(forHTTPHeaderField: "X-Call") == "call")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-perplexity/") == true)
            return FetchResponse(body: .data(Data(response.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Response": "response"])!)
        }))
        let result = try await provider.languageModel(.perplexitySonar).doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)], headers: ["X-Call": "call"]
        ))
        #expect(result.content == [.text(.init(text: "ok"))])
        #expect(result.response?.id == "agent-1")
        #expect(result.response?.headers?["x-response"] == "response")
    }

    @Suite("auth behavior", .serialized)
    struct AuthBehaviorTests {
        @Test("missing credentials fail only when a model operation is invoked")
        func missingCredentials() async throws {
            let original = getenv("PERPLEXITY_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original { setenv("PERPLEXITY_API_KEY", original, 1) }
                else { unsetenv("PERPLEXITY_API_KEY") }
            }
            unsetenv("PERPLEXITY_API_KEY")
            let provider = createPerplexity()
            let language = provider.languageModel(.fast)
            let embedding = provider.embedding(.pplxEmbedV106b)
            await #expect(throws: LoadAPIKeyError.self) {
                try await language.doGenerate(options: .init(prompt: [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)]))
            }
            await #expect(throws: LoadAPIKeyError.self) { try await embedding.doEmbed(options: .init(values: ["hello"])) }
        }
    }
}
