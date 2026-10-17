import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("OpenAI public option contracts")
struct OpenAIOptionsContractTests {
    @Test("Chat rejects a null logprobs option through its public operation")
    func nullChatLogprobs() async throws {
        let provider = try createOpenAI(settings: .init(apiKey: "key", fetch: { _ in throw URLError(.cannotConnectToHost) }))
        let error = await #expect(throws: InvalidArgumentError.self) {
            try await provider.chat("gpt-4o").doGenerate(options: .init(prompt: [], providerOptions: ["openai": ["logprobs": .null]]))
        }
        #expect(error?.argument == "providerOptions")
    }

    @Test("Provider dimensions retain their Source number contract in an embedding request")
    func providerDimensions() async throws {
        let provider = try createOpenAI(settings: .init(apiKey: "key", fetch: { request in
            let body = try JSONDecoder().decode(JSONObject.self, from: #require(request.httpBody))
            #expect(body["dimensions"] == 1536.5)
            return FetchResponse(body: .data(Data(#"{"data":[{"embedding":[1]}]}"#.utf8)), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }))
        let result = try await provider.embedding("text-embedding-3-small").doEmbed(options: .init(values: ["hello"], providerOptions: ["openai": ["dimensions": 1536.5]]))
        #expect(result.embeddings == [[1]])
    }
}
