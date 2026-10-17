import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class PerplexityEmbeddingModel: EmbeddingModelV4 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
    }
    private let modelIdentifier: PerplexityEmbeddingModelId
    private let config: Config

    init(modelId: PerplexityEmbeddingModelId, config: Config) { modelIdentifier = modelId; self.config = config }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxEmbeddingsPerCall: Int? { get async throws { 512 } }
    public var supportsParallelCalls: Bool { get async throws { true } }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        if options.values.count > 512 {
            throw TooManyEmbeddingValuesForCallError(provider: provider, modelId: modelId, maxEmbeddingsPerCall: 512, values: options.values)
        }
        let settings = try await parseProviderOptions(provider: "perplexity", providerOptions: options.providerOptions, schema: perplexityEmbeddingModelOptions)
        let encoding = settings?.encodingFormat ?? .base64Int8
        var body: JSONObject = ["model": .string(modelId), "input": .array(options.values.map(JSONValue.string)), "encoding_format": .string(encoding.rawValue)]
        if let dimensions = settings?.dimensions ?? options.dimensions { body["dimensions"] = .number(Double(dimensions)) }
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/v1/embeddings",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: perplexityFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: perplexityEmbeddingResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let embeddings = try response.value.data.map { item in
            let bytes = try convertBase64ToData(item.embedding)
            return bytes.map { byte -> Double in encoding == .base64Int8 ? Double(Int8(bitPattern: byte)) : Double(byte) }
        }
        var metadata: SharedV4ProviderMetadata?
        if let cost = response.value.usage?.cost {
            metadata = ["perplexity": ["cost": [
                "inputCost": cost.inputCost.map(JSONValue.number) ?? .null,
                "totalCost": cost.totalCost.map(JSONValue.number) ?? .null,
                "currency": cost.currency.map(JSONValue.string) ?? .null
            ]]]
        }
        return .init(embeddings: embeddings,
                     usage: response.value.usage.flatMap { Int(exactly: $0.promptTokens).map { .init(tokens: $0) } }, providerMetadata: metadata,
                     response: .init(headers: response.responseHeaders, body: response.rawValue))
    }
}

private struct PerplexityEmbeddingResponse: Decodable {
    struct Item: Decodable { let embedding: String }
    struct Usage: Decodable {
        struct Cost: Decodable {
            let inputCost: Double?
            let totalCost: Double?
            let currency: String?
            enum CodingKeys: String, CodingKey { case inputCost = "input_cost", totalCost = "total_cost", currency }
        }
        let promptTokens: Double
        let cost: Cost?
        enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens", cost }
    }
    let data: [Item]
    let usage: Usage?
}
private let perplexityEmbeddingResponseSchema = FlexibleSchema(
    Schema<PerplexityEmbeddingResponse>.codable(PerplexityEmbeddingResponse.self, jsonSchema: ["type": "object"])
)
