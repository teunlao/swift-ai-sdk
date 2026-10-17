import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import PerplexityProvider

@Suite("Perplexity embeddings")
struct PerplexityEmbeddingModelTests {
    struct ErrorCase: Sendable {
        let body: JSONValue
        let message: String
    }
    private func model(
        response: JSONValue = ["data": [["embedding": "AH+A/w=="]], "usage": ["prompt_tokens": 4]],
        status: Int = 200,
        inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> PerplexityEmbeddingModel {
        createPerplexity(settings: .init(baseURL: "https://proxy.example/api/", apiKey: "key", headers: ["X-Provider": "provider"], fetch: { request in
            try inspect(request)
            return FetchResponse(body: .data(try JSONEncoder().encode(response)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Response": "response"])!)
        })).embedding(.pplxEmbedV106b)
    }

    @Test("quantized vectors preserve signed bytes or packed unsigned bytes", arguments: [false, true])
    func quantizedVectors(binary: Bool) async throws {
        let instance = model(response: ["data": [["embedding": "AH+A/w=="]], "usage": ["prompt_tokens": 4, "cost": ["input_cost": 0.2, "total_cost": 0.5, "currency": "USD"]]]) { request in
            #expect(request.url?.absoluteString == "https://proxy.example/api/v1/embeddings")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "X-Pplx-Integration") == "vercel-ai-sdk")
            #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
            #expect(request.value(forHTTPHeaderField: "X-Call") == "call")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-perplexity/") == true)
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == ["model": "pplx-embed-v1-0.6b", "input": ["text"], "dimensions": 4, "encoding_format": .string(binary ? "base64_binary" : "base64_int8")])
        }
        var settings: JSONObject = ["dimensions": 4]
        if binary { settings["encodingFormat"] = "base64_binary" }
        let result = try await instance.doEmbed(options: .init(values: ["text"], dimensions: 128, providerOptions: ["perplexity": settings], headers: ["X-Call": "call"]))
        #expect(result.embeddings == (binary ? [[0, 127, 128, 255]] : [[0, 127, -128, -1]]))
        #expect(result.usage?.tokens == 4)
        #expect(result.providerMetadata == ["perplexity": ["cost": ["inputCost": 0.2, "totalCost": 0.5, "currency": "USD"]]])
        #expect(result.response?.headers?["x-response"] == "response")
    }

    @Test("nullable usage is omitted while empty cost objects expose null metadata", arguments: [JSONValue.null, ["prompt_tokens": 0, "cost": [:]]])
    func nullableUsage(usage: JSONValue) async throws {
        let result = try await model(response: ["data": [["embedding": "AA=="]], "usage": usage]).doEmbed(options: .init(values: ["text"]))
        #expect(result.embeddings == [[0]])
        if usage == .null {
            #expect(result.usage == nil)
            #expect(result.providerMetadata == nil)
        } else {
            #expect(result.usage?.tokens == 0)
            #expect(result.providerMetadata == ["perplexity": ["cost": ["inputCost": .null, "totalCost": .null, "currency": .null]]])
        }
    }

    @Test("embedding limits precede provider-option validation")
    func limitAndOptions() async throws {
        let instance = model()
        await #expect(throws: TooManyEmbeddingValuesForCallError.self) {
            try await instance.doEmbed(options: .init(values: Array(repeating: "text", count: 513), providerOptions: ["perplexity": ["dimensions": .null]]))
        }
        for dimension in [JSONValue.null, 0, 1.5, .number(1e100)] {
            await #expect(throws: InvalidArgumentError.self) {
                try await instance.doEmbed(options: .init(values: ["text"], providerOptions: ["perplexity": ["dimensions": dimension]]))
            }
        }
    }

    @Test("embedding response fields are validated before decoding bytes", arguments: [
        JSONValue.object(["data": [["embedding": 1]]]),
        ["data": [["embedding": "AA=="]], "usage": [:]],
        ["data": [["embedding": "AA=="]], "usage": ["prompt_tokens": 1, "cost": ["currency": true]]]
    ])
    func invalidResponse(response: JSONValue) async throws {
        await #expect(throws: APICallError.self) { try await model(response: response).doEmbed(options: .init(values: ["text"])) }
    }

    @Test("polymorphic API errors retain source precedence and provider data", arguments: [
        ErrorCase(body: ["error": "first", "detail": "ignored", "message": "ignored"], message: "first"),
        ErrorCase(body: ["error": ["code": "type", "message": .null, "type": "provider_type"], "extra": 7], message: "provider_type"),
        ErrorCase(body: ["detail": "detail"], message: "detail"),
        ErrorCase(body: ["detail": [["msg": "one", "extra": true], ["msg": "two"]]], message: "one, two"),
        ErrorCase(body: ["message": "top-level"], message: "top-level"),
        ErrorCase(body: [:], message: "unknown error")
    ])
    func errorFormats(value: ErrorCase) async throws {
        do {
            _ = try await model(response: value.body, status: 400).doEmbed(options: .init(values: ["text"]))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.message == value.message)
            #expect(error.statusCode == 400)
            let data = try #require(error.data as? PerplexityErrorData)
            #expect(data.raw == value.body)
        }
    }

    @Test("explicit null in optional HTTP error fields triggers status fallback")
    func malformedError() async throws {
        do {
            _ = try await model(response: ["error": .null, "message": "ignored"], status: 400).doEmbed(options: .init(values: ["text"]))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.data == nil)
            #expect(error.message == "Bad Request")
        }
    }

    @Test("aborted embedding requests produce cancellation")
    func cancellation() async throws {
        await #expect(throws: CancellationError.self) { try await model().doEmbed(options: .init(values: ["text"], abortSignal: { true })) }
    }
}
