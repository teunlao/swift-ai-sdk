import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AlibabaProvider

@Suite("Alibaba native embeddings")
struct AlibabaEmbeddingModelTests {
    private func model(_ response: JSONValue, status: Int = 200, inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }) -> AlibabaEmbeddingModel {
        createAlibaba(settings: .init(embeddingBaseURL: "https://embedding.example/api/v1/", apiKey: "key", fetch: { request in
            try inspect(request)
            return FetchResponse(body: .data(try JSONEncoder().encode(response)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Response": "response"])!)
        })).embedding(.textEmbeddingV4)
    }

    @Test("native dense and sparse results are ordered by text index and parameters preserve source numbers")
    func denseSparse() async throws {
        let response: JSONValue = ["output": ["embeddings": [["text_index": 1, "embedding": [2.0]], ["text_index": 0, "embedding": [1.0], "sparse_embedding": [["index": 3, "value": 0.5, "token": .null, "extra": true]]]]], "usage": ["total_tokens": 4]]
        let instance = model(response) { request in
            #expect(request.url?.absoluteString == "https://embedding.example/api/v1/services/embeddings/text-embedding/text-embedding")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-alibaba/") == true)
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == ["model": "text-embedding-v4", "input": ["texts": ["one", "two"]], "parameters": ["text_type": "query", "dimension": 1.5, "output_type": "dense&sparse"]])
        }
        let result = try await instance.doEmbed(options: .init(values: ["one", "two"], dimensions: 128, providerOptions: ["alibaba": ["textType": "query", "dimension": 1.5, "outputType": "dense&sparse"]]))
        #expect(result.embeddings == [[1], [2]])
        #expect(result.usage?.tokens == 4)
        #expect(result.providerMetadata == ["alibaba": ["sparseEmbeddings": [["textIndex": 0, "sparseEmbedding": [["index": 3, "value": 0.5, "token": .null]]]]]])
        #expect(result.response?.headers?["x-response"] == "response")
    }

    @Test("default parameters are empty and unrepresentable usage does not discard embeddings")
    func numericUsage() async throws {
        let response: JSONValue = ["output": ["embeddings": [["text_index": 0, "embedding": [1.0]]]], "usage": ["total_tokens": .number(1e100)]]
        let result = try await model(response) { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == ["model": "text-embedding-v4", "input": ["texts": ["text"]], "parameters": [:]])
        }.doEmbed(options: .init(values: ["text"]))
        #expect(result.embeddings == [[1]])
        #expect(result.usage == nil)
        #expect(result.providerMetadata == nil)
        #expect(try jsonValue(from: #require(result.response?.body)) == response)
    }

    @Test("call limit precedes option validation and sparse-only output is a typed refusal")
    func validation() async throws {
        let instance = model(.null)
        await #expect(throws: TooManyEmbeddingValuesForCallError.self) { try await instance.doEmbed(options: .init(values: Array(repeating: "text", count: 11), providerOptions: ["alibaba": ["outputType": "sparse"]])) }
        await #expect(throws: UnsupportedFunctionalityError.self) { try await instance.doEmbed(options: .init(values: ["text"], providerOptions: ["alibaba": ["outputType": "sparse"]])) }
        await #expect(throws: InvalidArgumentError.self) { try await instance.doEmbed(options: .init(values: ["text"], providerOptions: ["alibaba": ["dimension": .null]])) }
    }

    @Test("native endpoint errors preserve their message and HTTP status")
    func errors() async throws {
        do {
            _ = try await model(["code": "Denied", "message": "Native error", "request_id": .null], status: 403).doEmbed(options: .init(values: ["text"]))
            Issue.record("Expected native endpoint failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 403)
            #expect(error.message == "Native error")
        }
    }
}
