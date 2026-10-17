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

    @Test("Provider dimensions require representable integers", arguments: [1536.5, 1e20])
    func providerDimensions(_ dimensions: Double) async throws {
        let provider = try createOpenAI(settings: .init(apiKey: "key"))
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await provider.embedding("text-embedding-3-small").doEmbed(options: .init(values: ["hello"], providerOptions: ["openai": ["dimensions": .number(dimensions)]]))
        }
    }

    @Test("Request token and call limits require integers", arguments: ["chat", "completion", "responses", "maxCompletionTokens", "maxToolCalls"])
    func integerRequestLimits(_ kind: String) async throws {
        let provider = try createOpenAI(settings: .init(apiKey: "key"))
        let options: JSONObject = [(kind == "maxCompletionTokens" || kind == "maxToolCalls") ? kind : "logprobs": .number(1.5)]
        await #expect(throws: InvalidArgumentError.self) {
            let call = LanguageModelV4CallOptions(prompt: [], providerOptions: ["openai": options])
            switch kind {
            case "chat", "maxCompletionTokens": _ = try await provider.chat("gpt-4o").doGenerate(options: call)
            case "completion": _ = try await provider.completion("gpt-3.5-turbo-instruct").doGenerate(options: call)
            default: _ = try await provider.responses("gpt-6-sol").doGenerate(options: call)
            }
        }
    }
}
