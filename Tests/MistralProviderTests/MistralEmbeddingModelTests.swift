import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import MistralProvider

@Suite("MistralEmbeddingModel")
struct MistralEmbeddingModelTests {
    private func makeEmbeddingModel() -> (MistralEmbeddingModel, RequestRecorder, ResponseBox) {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.embeddingURL,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
        let responseBox = ResponseBox(initial: placeholderResponse)

        let fetch: FetchFunction = { request in
            await recorder.record(request)
            return await responseBox.value()
        }

        let provider = createMistralProvider(
            settings: .init(
                apiKey: "test-api-key",
                fetch: fetch
            )
        )

        return (provider.textEmbedding(.mistralEmbed), recorder, responseBox)
    }

    @Test("doEmbed returns embeddings")
    func embeddings() async throws {
        let (model, _, responseBox) = makeEmbeddingModel()

        let embeddings = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "data": embeddings.enumerated().map { index, values in
                    [
                        "object": "embedding",
                        "embedding": values,
                        "index": index
                    ]
                },
                "usage": ["prompt_tokens": 8]
            ]
        )

        let result = try await model.doEmbed(options: .init(values: ["sunny", "rainy"]))
        #expect(result.embeddings == embeddings)
    }

    @Test("doEmbed extracts usage")
    func usage() async throws {
        let (model, _, responseBox) = makeEmbeddingModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "data": [["embedding": [0.0]]],
                "usage": ["prompt_tokens": 42]
            ]
        )

        let result = try await model.doEmbed(options: .init(values: ["example"]))
        #expect(result.usage?.tokens == 42)
    }

    @Test("doEmbed exposes response metadata")
    func responseMetadata() async throws {
        let (model, _, responseBox) = makeEmbeddingModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "data": [["embedding": [0.0]]]
            ],
            headers: ["Test-Header": "test-value"]
        )

        let result = try await model.doEmbed(options: .init(values: ["example"]))
        let headers = result.response?.headers ?? [:]
        #expect(headers["test-header"] == "test-value")
        #expect(headers["content-type"] == "application/json")
        #expect(result.response?.body != nil)
    }

    @Test("doEmbed sends model and values")
    func requestPayload() async throws {
        let (model, recorder, responseBox) = makeEmbeddingModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "data": [["embedding": [0.0]]]
            ]
        )

        let values = ["sunny day", "rainy night"]
        _ = try await model.doEmbed(options: .init(values: values))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let body = try decodeJSONBody(request)
        #expect(body["model"] as? String == "mistral-embed")
        #expect(body["encoding_format"] as? String == "float")
        #expect(body["input"] as? [String] == values)
    }

    @Test("doEmbed merges headers")
    func requestHeaders() async throws {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.embeddingURL,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
        let responseBox = ResponseBox(initial: placeholderResponse)

        let fetch: FetchFunction = { request in
            await recorder.record(request)
            return await responseBox.value()
        }

        let provider = createMistralProvider(
            settings: .init(
                apiKey: "test-api-key",
                headers: ["Custom-Provider-Header": "provider-value"],
                fetch: fetch
            )
        )

        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "data": [["embedding": [0.0]]]
            ]
        )

        _ = try await provider.embedding(.mistralEmbed).doEmbed(options: .init(values: ["value"], headers: ["Custom-Request-Header": "request-value"]))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["custom-provider-header"] == "provider-value")
        #expect(headers["custom-request-header"] == "request-value")
        #expect(headers["user-agent"]?.contains("ai-sdk/mistral") == true)
    }
}
