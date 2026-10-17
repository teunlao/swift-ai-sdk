import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class AlibabaEmbeddingModel: EmbeddingModelV4 {
    private let identifier: AlibabaEmbeddingModelId
    private let config: AlibabaConfig
    init(modelId: AlibabaEmbeddingModelId, config: AlibabaConfig) { identifier = modelId; self.config = config }
    public var modelId: String { identifier.rawValue }
    public var provider: String { config.provider }
    public var maxEmbeddingsPerCall: Int? { get async throws { 10 } }
    public var supportsParallelCalls: Bool { get async throws { false } }
    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        if options.values.count > 10 {
            throw TooManyEmbeddingValuesForCallError(provider: provider, modelId: modelId, maxEmbeddingsPerCall: 10, values: options.values)
        }
        let settings = try await parseProviderOptions(provider: "alibaba", providerOptions: options.providerOptions, schema: alibabaEmbeddingModelOptions)
        if settings?.outputType == .sparse {
            throw UnsupportedFunctionalityError(functionality: "Alibaba embedding outputType 'sparse'", message: "Alibaba embedding outputType 'sparse' is not supported because AI SDK embeddings require dense number arrays. Use 'dense' or 'dense&sparse' instead.")
        }
        var parameters: JSONObject = [:]
        if let type = settings?.textType { parameters["text_type"] = .string(type.rawValue) }
        if let dimension = settings?.dimension ?? options.dimensions.map(Double.init) { parameters["dimension"] = .number(dimension) }
        if let type = settings?.outputType { parameters["output_type"] = .string(type.rawValue) }
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/services/embeddings/text-embedding/text-embedding",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(["model": .string(modelId), "input": ["texts": .array(options.values.map(JSONValue.string))], "parameters": .object(parameters)]),
            failedResponseHandler: alibabaEmbeddingFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: alibabaEmbeddingResponseSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        let vectors = response.value.output.embeddings.enumerated().sorted {
            $0.element.textIndex == $1.element.textIndex ? $0.offset < $1.offset : $0.element.textIndex < $1.element.textIndex
        }.map(\.element)
        let sparse: [JSONValue] = vectors.compactMap { value -> JSONValue? in
            guard let sparse = value.sparse else { return Optional<JSONValue>.none }
            return ["textIndex": .number(value.textIndex), "sparseEmbedding": .array(sparse.map { .object($0.fields) })]
        }
        return .init(embeddings: vectors.map(\.embedding),
                     usage: response.value.usage.flatMap { Int(exactly: $0.totalTokens).map { .init(tokens: $0) } },
                     providerMetadata: sparse.isEmpty ? nil : ["alibaba": ["sparseEmbeddings": .array(sparse)]],
                     response: .init(headers: response.responseHeaders, body: response.rawValue))
    }
}
private struct AlibabaEmbeddingResponse: Decodable {
    struct Sparse: Decodable {
        let index: Double
        let value: Double
        let token: String?
        let hasToken: Bool
        private enum Keys: String, CodingKey { case index, value, token }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Keys.self)
            index = try values.decode(Double.self, forKey: .index)
            value = try values.decode(Double.self, forKey: .value)
            token = try values.decodeIfPresent(String.self, forKey: .token)
            hasToken = values.contains(.token)
        }
        var fields: JSONObject {
            var fields: JSONObject = ["index": .number(index), "value": .number(value)]
            if hasToken { fields["token"] = token.map(JSONValue.string) ?? .null }
            return fields
        }
    }
    struct Vector: Decodable {
        let embedding: [Double]
        let textIndex: Double
        let sparse: [Sparse]?
        enum CodingKeys: String, CodingKey { case embedding; case textIndex = "text_index", sparse = "sparse_embedding" }
    }
    struct Output: Decodable { let embeddings: [Vector] }
    struct Usage: Decodable {
        let totalTokens: Double
        enum CodingKeys: String, CodingKey { case totalTokens = "total_tokens" }
    }
    let output: Output
    let usage: Usage?
}
private struct AlibabaEmbeddingError: Decodable {
    let code: String?
    let message: String
    let requestId: String?
    enum CodingKeys: String, CodingKey { case code, message; case requestId = "request_id" }
}
private let alibabaEmbeddingResponseSchema = FlexibleSchema(Schema<AlibabaEmbeddingResponse>.codable(AlibabaEmbeddingResponse.self, jsonSchema: ["type": "object"]))
private let alibabaEmbeddingFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<AlibabaEmbeddingError>.codable(AlibabaEmbeddingError.self, jsonSchema: ["type": "object"])), errorToMessage: { $0.message }
)
