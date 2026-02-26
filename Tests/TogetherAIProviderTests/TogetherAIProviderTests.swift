import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import TogetherAIProvider

@Suite("TogetherAIProvider")
struct TogetherAIProviderTests {
    @Test("creates chat/completion/embedding/image/reranking models")
    func createsModels() throws {
        let provider = createTogetherAIProvider(settings: TogetherAIProviderSettings(apiKey: "test-key"))

        let chat = try provider.languageModel(modelId: "meta-llama/Llama-3.3-70B-Instruct-Turbo")
        #expect(chat.provider == "togetherai.chat")
        #expect(provider.chat("meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo").provider == "togetherai.chat")

        let completion = try provider.completionModel(modelId: "mistralai/Mistral-7B-v0.1")
        #expect(completion.provider == "togetherai.completion")
        #expect(provider.completion("mistralai/Mistral-7B-v0.1").provider == "togetherai.completion")

        let embedding = try provider.textEmbeddingModel(modelId: "BAAI/bge-base-en-v1.5")
        #expect(embedding.provider == "togetherai.embedding")
        #expect(provider.embedding("BAAI/bge-base-en-v1.5").provider == "togetherai.embedding")

        let image = try provider.imageModel(modelId: "stabilityai/stable-diffusion-xl-base-1.0")
        #expect(image.provider == "togetherai.image")
        #expect(type(of: image) == TogetherAIImageModel.self)
        #expect(provider.image("stabilityai/stable-diffusion-xl-base-1.0").provider == "togetherai.image")

        let reranking = try provider.rerankingModel(modelId: "Salesforce/Llama-Rank-v1")
        #expect(reranking != nil)
        #expect(reranking?.provider == "togetherai.reranking")
        #expect(provider.reranking("Salesforce/Llama-Rank-v1").provider == "togetherai.reranking")
    }

    @Test("supports upstream naming createTogetherAI")
    func supportsUpstreamNamingAlias() throws {
        let provider = createTogetherAI(settings: TogetherAIProviderSettings(apiKey: "test-key"))
        let chat = try provider.languageModel(modelId: "meta-llama/Llama-3.3-70B-Instruct-Turbo")
        #expect(chat.provider == "togetherai.chat")
    }

    @Suite("auth behavior", .serialized)
    struct AuthBehaviorTests {
        actor RequestCapture {
            private(set) var request: URLRequest?

            func store(_ request: URLRequest) {
                self.request = request
            }

            func current() -> URLRequest? {
                request
            }
        }

        private func makeEmbeddingResponseData() throws -> Data {
            let payload: [String: Any] = [
                "data": [
                    ["embedding": [0.1, 0.2]]
                ],
                "usage": ["prompt_tokens": 2]
            ]
            return try JSONSerialization.data(withJSONObject: payload)
        }

        private func makeFetch(capture: RequestCapture) throws -> FetchFunction {
            let responseData = try makeEmbeddingResponseData()
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://api.together.xyz/v1/embeddings")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            return { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
            }
        }

        @Test("missing API key throws LoadAPIKeyError at request time")
        func missingAPIKeyThrowsAtRequestTime() async throws {
            let original = getenv("TOGETHER_AI_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("TOGETHER_AI_API_KEY", original, 1)
                } else {
                    unsetenv("TOGETHER_AI_API_KEY")
                }
            }

            unsetenv("TOGETHER_AI_API_KEY")
            let capture = RequestCapture()
            let provider = createTogetherAIProvider(
                settings: TogetherAIProviderSettings(fetch: try makeFetch(capture: capture))
            )

            do {
                _ = try await provider.textEmbeddingModel(modelId: "BAAI/bge-base-en-v1.5").doEmbed(
                    options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
                )
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("TogetherAI API key is missing"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.current() == nil)
        }

        @Test("injects Authorization header using apiKey at request time")
        func injectsAuthorizationHeaderAtRequestTime() async throws {
            let capture = RequestCapture()
            let provider = createTogetherAIProvider(
                settings: TogetherAIProviderSettings(
                    apiKey: "test-key",
                    fetch: try makeFetch(capture: capture)
                )
            )

            _ = try await provider.textEmbeddingModel(modelId: "BAAI/bge-base-en-v1.5").doEmbed(
                options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
            )

            guard let request = await capture.current() else {
                Issue.record("Expected request capture")
                return
            }

            let headerFields = request.allHTTPHeaderFields ?? [:]
            let headers = headerFields.reduce(into: [String: String]()) { result, entry in
                result[entry.key.lowercased()] = entry.value
            }
            #expect(headers["authorization"] == "Bearer test-key")
        }
    }
}
