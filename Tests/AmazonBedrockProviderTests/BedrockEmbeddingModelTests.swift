import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AmazonBedrockProvider

@Suite("Bedrock embedding V4 contracts")
struct BedrockEmbeddingModelTests {
    @Test("Titan dimensions honor provider precedence and parse token usage")
    func titanDimensions() async throws {
        let server = try BedrockTestServer(json: .object(["embedding": .array([.number(0.1), .number(0.2)]), "inputTextTokenCount": .number(8)]))
        let result = try await server.provider().embedding(modelId: .amazonTitanEmbedTextV2).doEmbed(options: .init(values: ["text"], dimensions: 512, providerOptions: ["amazonBedrock": ["dimensions": .number(256), "normalize": .bool(false)], "bedrock": ["dimensions": .number(1024)]]))
        #expect(result.embeddings == [[0.1, 0.2]])
        #expect(result.usage?.tokens == 8)
        #expect(try await server.requestBody() == .object(["inputText": .string("text"), "dimensions": .number(256), "normalize": .bool(false)]))
    }

    @Test("Cross-region Cohere accepts batches and preserves every embedding", arguments: [false, true])
    func cohereBatch(_ v4: Bool) async throws {
        let embeddings: JSONValue = .array([.array([.number(1)]), .array([.number(2)])])
        let server = try BedrockTestServer(json: .object(["embeddings": v4 ? .object(["float": embeddings]) : embeddings]), headers: ["x-amzn-bedrock-input-token-count": "12"])
        let model = server.provider().embedding(modelId: v4 ? "us.cohere.embed-v4:0" : "global.cohere.embed-english-v3")
        let result = try await model.doEmbed(options: .init(values: ["first", "second"], dimensions: 512, providerOptions: ["amazonBedrock": ["inputType": .string("classification"), "truncate": .string("START")]]))
        #expect(try await model.maxEmbeddingsPerCall == 96)
        #expect(result.embeddings == [[1], [2]])
        #expect(result.usage?.tokens == 12)
        #expect(try await server.requestBody() == .object(["texts": .array([.string("first"), .string("second")]), "input_type": .string("classification"), "truncate": .string("START"), "output_dimension": .number(512)]))
    }

    @Test("Opaque profile model family determines Cohere batching and payload")
    func opaqueFamily() async throws {
        let server = try BedrockTestServer(json: .object(["embeddings": .array([.array([.number(1)]), .array([.number(2)])])]))
        let model = server.provider().embedding(modelId: "opaque-profile", settings: .init(modelFamily: .cohere))
        let result = try await model.doEmbed(options: .init(values: ["a", "b"]))
        #expect(result.embeddings == [[1], [2]])
        #expect(result.usage == nil)
        #expect(try await server.requestBody()["input_type"] == .string("search_query"))
    }

    @Test("Nova embeddings use portable dimensions and default text truncation")
    func novaDimensions() async throws {
        let server = try BedrockTestServer(json: .object(["embeddings": .array([.object(["embeddingType": .string("TEXT"), "embedding": .array([.number(0.5)])])]), "inputTokenCount": .number(4)]))
        let result = try await server.provider().embedding(modelId: "us.amazon.nova-2-multimodal-embeddings-v1:0").doEmbed(options: .init(values: ["value"], dimensions: 384))
        #expect(result.embeddings == [[0.5]])
        #expect(result.usage?.tokens == 4)
        #expect(try await server.requestBody()["singleEmbeddingParams"] == .object(["embeddingPurpose": .string("GENERIC_INDEX"), "embeddingDimension": .number(384), "text": .object(["truncationMode": .string("END"), "value": .string("value")])]))
    }

    @Test("Nova usage falls back to the response header when the body omits it")
    func novaHeaderUsage() async throws {
        let server = try BedrockTestServer(json: .object(["embeddings": .array([.object(["embeddingType": .string("TEXT"), "embedding": .array([.number(0.5)])])])]), headers: ["x-amzn-bedrock-input-token-count": "12"])
        let result = try await server.provider().embedding(modelId: "amazon.nova-2-multimodal-embeddings-v1:0").doEmbed(options: .init(values: ["text"]))
        #expect(result.embeddings == [[0.5]])
        #expect(result.usage?.tokens == 12)
    }

    @Test("Invalid body token counts remain unknown instead of using the header", arguments: [false, true])
    func unknownUsage(_ nova: Bool) async throws {
        let raw: JSONValue = nova
            ? .object(["embeddings": .array([.object(["embeddingType": .string("TEXT"), "embedding": .array([.number(0.5)])])]), "inputTokenCount": .number(1e100)])
            : .object(["embedding": .array([.number(0.5)]), "inputTextTokenCount": .number(1.5)])
        let server = try BedrockTestServer(json: raw, headers: ["x-amzn-bedrock-input-token-count": "12"])
        let model = server.provider().embedding(modelId: nova ? "amazon.nova-2-multimodal-embeddings-v1:0" : .amazonTitanEmbedTextV2)
        let result = try await model.doEmbed(options: .init(values: ["text"]))
        #expect(result.embeddings == [[0.5]])
        #expect(result.usage == nil)
        #expect(try jsonValue(from: #require(result.response?.body)) == raw)
    }

    @Test("Embedding limits and malformed response shapes fail at the model boundary")
    func embeddingFailures() async throws {
        let server = try BedrockTestServer(json: .object(["unexpected": .bool(true)]))
        let model = server.provider().embedding(modelId: .amazonTitanEmbedTextV2)
        await #expect(throws: TooManyEmbeddingValuesForCallError.self) { _ = try await model.doEmbed(options: .init(values: ["a", "b"])) }
        do {
            _ = try await model.doEmbed(options: .init(values: ["a"]))
            Issue.record("Expected invalid API response")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.isRetryable == false)
            #expect(error.cause is TypeValidationError)
        }
    }
}
