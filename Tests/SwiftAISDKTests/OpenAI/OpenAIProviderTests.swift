import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private func makeEmbeddingResponseData() -> Data {
    let json: [String: Any] = [
        "object": "list",
        "data": [
            [
                "object": "embedding",
                "index": 0,
                "embedding": [0.1, 0.2]
            ]
        ],
        "model": "text-embedding-3-small",
        "usage": ["prompt_tokens": 1, "total_tokens": 1]
    ]
    return try! JSONSerialization.data(withJSONObject: json)
}

@Suite("OpenAIProvider")
struct OpenAIProviderTests {
    actor URLCapture {
        private(set) var url: String?
        func store(_ url: String?) { self.url = url }
        func current() -> String? { url }
    }

    private func makeFetch(capture: URLCapture) -> FetchFunction {
        let data = makeEmbeddingResponseData()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return { request in
            await capture.store(request.url?.absoluteString)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }

    @Suite("baseURL configuration", .serialized)
    struct BaseURLConfigurationTests {
        // Port of openai-provider.test.ts: "uses the default OpenAI base URL when not provided"
        @Test("uses default OpenAI base URL")
        func testUsesDefaultBaseURL() async throws {
            let original = getenv("OPENAI_BASE_URL").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("OPENAI_BASE_URL", original, 1)
                } else {
                    unsetenv("OPENAI_BASE_URL")
                }
            }

            unsetenv("OPENAI_BASE_URL")
            let capture = URLCapture()
            let provider = createOpenAIProvider(
                settings: OpenAIProviderSettings(apiKey: "test-api-key", fetch: makeFetch(capture: capture))
            )
            _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
                options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
            )
            let url = await capture.current()
            #expect(url == "https://api.openai.com/v1/embeddings")
        }

        // Port of openai-provider.test.ts: "uses OPENAI_BASE_URL when set"
        @Test("uses OPENAI_BASE_URL when set")
        func testUsesEnvironmentBaseURL() async throws {
            let original = getenv("OPENAI_BASE_URL").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("OPENAI_BASE_URL", original, 1)
                } else {
                    unsetenv("OPENAI_BASE_URL")
                }
            }

            setenv("OPENAI_BASE_URL", "https://proxy.openai.example/v1/", 1)
            let capture = URLCapture()
            let provider = createOpenAIProvider(
                settings: OpenAIProviderSettings(apiKey: "test-api-key", fetch: makeFetch(capture: capture))
            )
            _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
                options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
            )
            let url = await capture.current()
            #expect(url == "https://proxy.openai.example/v1/embeddings")
        }

        // Port of openai-provider.test.ts: "prefers the baseURL option over OPENAI_BASE_URL"
        @Test("prefers baseURL option over environment")
        func testPrefersExplicitBaseURL() async throws {
            let original = getenv("OPENAI_BASE_URL").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("OPENAI_BASE_URL", original, 1)
                } else {
                    unsetenv("OPENAI_BASE_URL")
                }
            }

            setenv("OPENAI_BASE_URL", "https://env.openai.example/v1", 1)
            let capture = URLCapture()
            let provider = createOpenAIProvider(
                settings: OpenAIProviderSettings(
                    baseURL: "https://option.openai.example/v1/",
                    apiKey: "test-api-key",
                    fetch: makeFetch(capture: capture))
            )
            _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
                options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
            )
            let url = await capture.current()
            #expect(url == "https://option.openai.example/v1/embeddings")
        }

        private func makeFetch(capture: URLCapture) -> FetchFunction {
            let data = makeEmbeddingResponseData()
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            return { request in
                await capture.store(request.url?.absoluteString)
                return FetchResponse(body: .data(data), urlResponse: response)
            }
        }
    }
}
