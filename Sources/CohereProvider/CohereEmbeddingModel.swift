import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class CohereEmbeddingModel: EmbeddingModelV4 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
    }
    private let modelIdentifier: CohereEmbeddingModelId
    private let config: Config

    init(modelId: CohereEmbeddingModelId, config: Config) { modelIdentifier = modelId; self.config = config }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxEmbeddingsPerCall: Int? { get async throws { 96 } }
    public var supportsParallelCalls: Bool { get async throws { true } }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let settings = try await parseProviderOptions(provider: "cohere", providerOptions: options.providerOptions, schema: cohereEmbeddingModelOptions)
        let embeddingType = settings?.embeddingType ?? .float
        if options.values.count > 96 {
            throw TooManyEmbeddingValuesForCallError(provider: provider, modelId: modelId, maxEmbeddingsPerCall: 96, values: options.values)
        }
        var body: JSONObject = [
            "model": .string(modelId), "embedding_types": [.string(embeddingType.rawValue)],
            "texts": .array(options.values.map(JSONValue.string)), "input_type": .string(settings?.inputType?.rawValue ?? "search_query")
        ]
        if let value = settings?.truncate { body["truncate"] = .string(value.rawValue) }
        if let value = settings?.outputDimension ?? options.dimensions { body["output_dimension"] = .number(Double(value)) }
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/embed",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: cohereFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: cohereEmbeddingResponseSchema(embeddingType)),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        return .init(embeddings: response.value.embeddings, usage: .init(tokens: response.value.tokens),
                     response: .init(headers: response.responseHeaders, body: response.rawValue))
    }
}

private let cohereEmbeddingFormatKey = CodingUserInfoKey(rawValue: "cohere.embeddingType")!

private struct CohereEmbeddingResponse: Decodable, Sendable {
    private struct Meta: Decodable {
        struct BilledUnits: Decodable {
            let inputTokens: Int
            enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens" }
        }
        let billedUnits: BilledUnits
        enum CodingKeys: String, CodingKey { case billedUnits = "billed_units" }
    }
    private struct FormatKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private enum Keys: String, CodingKey { case embeddings, meta }
    let embeddings: [[Double]]
    let tokens: Int

    init(from decoder: Decoder) throws {
        guard let format = decoder.userInfo[cohereEmbeddingFormatKey] as? CohereEmbeddingModelOptions.EmbeddingType else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing requested embedding format"))
        }
        let container = try decoder.container(keyedBy: Keys.self)
        let vectors = try container.nestedContainer(keyedBy: FormatKey.self, forKey: .embeddings)
        embeddings = try vectors.decode([[Double]].self, forKey: .init(stringValue: format.rawValue))
        tokens = try container.decode(Meta.self, forKey: .meta).billedUnits.inputTokens
    }
}

private func cohereEmbeddingResponseSchema(_ format: CohereEmbeddingModelOptions.EmbeddingType) -> FlexibleSchema<CohereEmbeddingResponse> {
    FlexibleSchema(Schema<CohereEmbeddingResponse>(jsonSchemaResolver: { ["type": "object"] }, validator: { raw in
        do {
            let decoder = JSONDecoder()
            decoder.userInfo[cohereEmbeddingFormatKey] = format
            // Keep decimal tokens intact until JSONDecoder produces Double values.
            let data = try JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed])
            return .success(value: try decoder.decode(CohereEmbeddingResponse.self, from: data))
        } catch { return .failure(error: TypeValidationError.wrap(value: raw, cause: error)) }
    }))
}
