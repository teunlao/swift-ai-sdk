import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex embeddings V4")
struct GoogleVertexEmbeddingModelTests {
    @Test(arguments: ["googleVertex", "vertex", "google"])
    func predictRequestAndResponse(namespace: String) async throws {
        let requests = VertexRequests()
        let fixture = try vertexFixture("embedding.json")
        let model = try vertexProvider { request in
            await requests.append(request)
            return try vertexResponse(request, fixture)
        }.embeddingModel(modelId: "text-embedding-005")
        let result = try await model.doEmbed(options: .init(
            values: ["one", "two"], dimensions: 128,
            providerOptions: [namespace: ["taskType": .string("RETRIEVAL_DOCUMENT"), "title": .string("Document"), "autoTruncate": .bool(false)]],
            headers: ["x-request": "custom"]
        ))
        #expect(result.embeddings == [[0.1, 0.2], [0.3, 0.4]])
        #expect(result.usage?.tokens == 25)
        #expect(result.response?.headers?["x-request-id"] == "vertex-request")
        let raw = try #require(result.response?.body)
        #expect(try jsonValue(from: raw) == JSONDecoder().decode(JSONValue.self, from: Data(fixture.utf8)))
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://vertex.example/models/text-embedding-005:predict")
        #expect(request.value(forHTTPHeaderField: "x-request") == "custom")
        #expect(try vertexBody(request) == .object([
            "instances": .array(["one", "two"].map { .object(["content": .string($0), "task_type": .string("RETRIEVAL_DOCUMENT"), "title": .string("Document")]) }),
            "parameters": .object(["outputDimensionality": .number(128), "autoTruncate": .bool(false)])
        ]))
    }

    @Test(arguments: ["gemini-embedding-2", "gemini-embedding-2-preview"])
    func embedContent(modelId: String) async throws {
        let requests = VertexRequests()
        let model = try vertexProvider { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"embedding":{"values":[0.5]},"usageMetadata":{"promptTokenCount":3}}"#)
        }.embeddingModel(modelId: modelId)
        let result = try await model.doEmbed(options: .init(values: ["query"], dimensions: 128, providerOptions: [
            "googleVertex": ["outputDimensionality": .number(64.5), "taskType": .string("RETRIEVAL_QUERY"), "autoTruncate": .bool(false)],
            "vertex": ["outputDimensionality": .number(8)]
        ]))
        #expect(try await model.maxEmbeddingsPerCall == 1)
        #expect(result.embeddings == [[0.5]])
        #expect(result.usage?.tokens == 3)
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://vertex.example/models/\(modelId):embedContent")
        #expect(try vertexBody(request) == .object([
            "content": .object(["parts": .array([.object(["text": .string("query")])])]),
            "embedContentConfig": .object(["outputDimensionality": .number(64.5), "taskType": .string("RETRIEVAL_QUERY"), "autoTruncate": .bool(false)])
        ]))
    }

    @Test(arguments: [("text-embedding-005", 250), ("gemini-embedding-2", 1)])
    func enforcesCallLimit(modelId: String, maximum: Int) async throws {
        let model = try vertexProvider { _ in throw CancellationError() }.embeddingModel(modelId: modelId)
        do {
            _ = try await model.doEmbed(options: .init(values: Array(repeating: "value", count: maximum + 1)))
            Issue.record("Expected embedding call limit")
        } catch let error as TooManyEmbeddingValuesForCallError {
            #expect(error.maxEmbeddingsPerCall == maximum)
            #expect(error.modelId == modelId)
            #expect(error.values.count == maximum + 1)
        }
    }

    @Test func validatesSelectedNamespace() async throws {
        let model = try vertexProvider { _ in throw CancellationError() }.embeddingModel(modelId: "text-embedding-005")
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doEmbed(options: .init(values: ["hello"], providerOptions: [
                "googleVertex": ["outputDimensionality": .null], "vertex": ["outputDimensionality": .number(4)]
            ]))
        }
    }
}
