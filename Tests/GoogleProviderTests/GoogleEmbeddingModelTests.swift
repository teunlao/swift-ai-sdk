import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK
import GoogleProvider

@Suite("Google embeddings V4")
struct GoogleEmbeddingModelTests {
    @Test("automatic batching preserves per-value multimodal content and dimensions")
    func multimodalBatchAlignment() async throws {
        let fetch: FetchFunction = { request in
            let body = try googleBody(request)
            let requests = array(body["requests"]).isEmpty ? [JSONValue.object(body)] : array(body["requests"])
            var embeddings: [JSONValue] = []
            for value in requests {
                let entry = object(value)
                let parts = array(object(entry["content"])["parts"])
                let index = try #require(string(object(parts.first)["text"]).flatMap(Int.init))
                #expect(object(parts.last)["text"] == .string("multimodal-\(index)"))
                #expect(entry["outputDimensionality"] == .number(8))
                embeddings.append(.object(["values": .array([.number(Double(index))])]))
            }
            let response: JSONValue = body["requests"] == nil ? .object(["embedding": embeddings[0]]) : .object(["embeddings": .array(embeddings)])
            return try googleResponse(request, data: googleData(response))
        }
        let model = try createGoogle(settings: .init(apiKey: "key", fetch: fetch)).embeddingModel(modelId: "gemini-embedding-2")
        let values = (0...100).map(String.init)
        let content: [JSONValue] = (0...100).map { .array([.object(["text": .string("multimodal-\($0)")])]) }
        let result = try await embedMany(model: .v4(model), values: values, dimensions: 8, maxParallelCalls: 1, maxRetries: 0, providerOptions: ["google": ["content": .array(content)]])
        #expect(result.embeddings == (0...100).map { [Double($0)] })
    }

    @Test("single-input embedding uses provider dimensions and task type")
    func singleEmbedding() async throws {
        let data = try googleData(.object(["embedding": .object(["values": .array([.number(0.5)])])]))
        let transport = GoogleTransport([.init(data)])
        let model = try await transport.provider().embeddingModel(modelId: "gemini-embedding-001")
        let result = try await model.doEmbed(options: .init(values: [""], dimensions: 12, providerOptions: ["google": ["outputDimensionality": .number(3), "taskType": .string("RETRIEVAL_DOCUMENT"), "content": .array([.array([.object(["inlineData": .object(["mimeType": .string("image/png"), "data": .string("AQID")])])])])]]))
        #expect(result.embeddings == [[0.5]])
        let request = try #require(await transport.captured().first)
        #expect(request.url?.path.hasSuffix("gemini-embedding-001:embedContent") == true)
        let body = try googleBody(request)
        #expect(body["outputDimensionality"] == .number(3))
        #expect(body["taskType"] == .string("RETRIEVAL_DOCUMENT"))
        #expect(array(object(body["content"])["parts"]) == [.object(["inlineData": .object(["mimeType": .string("image/png"), "data": .string("AQID")])])])
    }

    @Test("embedding rejects mismatched content and too many direct inputs")
    func invalidBatch() async throws {
        let model = try createGoogle(settings: .init(apiKey: "key")).embeddingModel(modelId: "gemini-embedding-2")
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doEmbed(options: .init(values: ["a", "b"], providerOptions: ["google": ["content": .array([.null])]]))
        }
        await #expect(throws: TooManyEmbeddingValuesForCallError.self) {
            try await model.doEmbed(options: .init(values: Array(repeating: "x", count: 101)))
        }
    }
}
