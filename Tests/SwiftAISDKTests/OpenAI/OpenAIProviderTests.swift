import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

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

    @Test("base URL configuration precedence")
    func testBaseURLPrecedence() async throws {
        let original = getenv("OPENAI_BASE_URL").flatMap { String(validatingCString: $0) }
        defer {
            if let original {
                setenv("OPENAI_BASE_URL", original, 1)
            } else {
                unsetenv("OPENAI_BASE_URL")
            }
        }

        // Default URL
        unsetenv("OPENAI_BASE_URL")
        var capture = URLCapture()
        var provider = createOpenAIProvider(settings: OpenAIProviderSettings(apiKey: "test-api-key", fetch: makeFetch(capture: capture)))
        _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(values: ["hello"]))
        let defaultURL = await capture.current()
        #expect(defaultURL == "https://api.openai.com/v1/embeddings")

        // Environment override
        setenv("OPENAI_BASE_URL", "https://proxy.openai.example/v1/", 1)
        capture = URLCapture()
        provider = createOpenAIProvider(settings: OpenAIProviderSettings(apiKey: "test-api-key", fetch: makeFetch(capture: capture)))
        _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(values: ["hello"]))
        let envURL = await capture.current()
        #expect(envURL == "https://proxy.openai.example/v1/embeddings")

        // Explicit option override
        capture = URLCapture()
        provider = createOpenAIProvider(
            settings: OpenAIProviderSettings(
                baseURL: "https://option.example/v1/",
                apiKey: "test-api-key",
                fetch: makeFetch(capture: capture)
            )
        )
        _ = try await provider.textEmbeddingModel(modelId: "text-embedding-3-small").doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(values: ["hello"]))
        let optionURL = await capture.current()
        #expect(optionURL == "https://option.example/v1/embeddings")
    }
}
