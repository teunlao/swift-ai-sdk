import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct BedrockEmbeddingModelSettings: Sendable {
    public enum ModelFamily: String, Sendable { case titan, cohere, nova }
    public var modelFamily: ModelFamily?
    public init(modelFamily: ModelFamily? = nil) { self.modelFamily = modelFamily }
}

struct BedrockEmbeddingConfig: Sendable {
    let baseURL: @Sendable () throws -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    var modelFamily: BedrockEmbeddingModelSettings.ModelFamily? = nil
}

public final class BedrockEmbeddingModel: EmbeddingModelV4 {
    private let modelIdentifier: BedrockEmbeddingModelId
    private let config: BedrockEmbeddingConfig

    init(modelId: BedrockEmbeddingModelId, config: BedrockEmbeddingConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { "amazon-bedrock" }
    public var modelId: String { modelIdentifier.rawValue }
    private var modelFamily: BedrockEmbeddingModelSettings.ModelFamily {
        config.modelFamily ?? (modelId.contains("amazon.nova-") && modelId.contains("embed") ? .nova : modelId.contains("cohere.embed-") ? .cohere : .titan)
    }
    public var maxEmbeddingsPerCall: Int? { get async throws { modelFamily == .cohere ? 96 : 1 } }
    public var supportsParallelCalls: Bool { get async throws { true } }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let limit = modelFamily == .cohere ? 96 : 1
        guard options.values.count <= limit else {
            throw TooManyEmbeddingValuesForCallError(provider: provider, modelId: modelId, maxEmbeddingsPerCall: limit, values: options.values.map { $0 as Any })
        }
        let providerOptions = try await parseBedrockOptions(providerOptions: options.providerOptions, schema: bedrockEmbeddingProviderOptionsSchema) ?? BedrockEmbeddingProviderOptions()
        var body: [String: JSONValue]
        switch modelFamily {
        case .nova:
            var text: [String: JSONValue] = ["truncationMode": .string(providerOptions.truncate?.rawValue ?? "END")]
            if let value = options.values.first { text["value"] = .string(value) }
            body = [
                "taskType": .string("SINGLE_EMBEDDING"),
                "singleEmbeddingParams": .object([
                    "embeddingPurpose": .string(providerOptions.embeddingPurpose?.rawValue ?? "GENERIC_INDEX"),
                    "embeddingDimension": .number(Double(providerOptions.embeddingDimension?.rawValue ?? options.dimensions ?? 1024)),
                    "text": .object(text)
                ])
            ]
        case .cohere:
            body = ["input_type": .string(providerOptions.inputType?.rawValue ?? "search_query"), "texts": .array(options.values.map(JSONValue.string))]
            if let truncate = providerOptions.truncate { body["truncate"] = .string(truncate.rawValue) }
            if let dimensions = providerOptions.outputDimension?.rawValue ?? options.dimensions { body["output_dimension"] = .number(Double(dimensions)) }
        case .titan:
            body = [:]
            if let value = options.values.first { body["inputText"] = .string(value) }
            if let dimensions = providerOptions.dimensions?.rawValue ?? options.dimensions { body["dimensions"] = .number(Double(dimensions)) }
            if let normalize = providerOptions.normalize { body["normalize"] = .bool(normalize) }
        }
        let response = try await postJsonToAPI(
            url: "\(try config.baseURL())/model/\(bedrockEncodeURIComponent(modelId))/invoke",
            headers: combineHeaders(config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        let value = response.value
        let embeddings: [[Double]]
        if let embedding = value.embedding {
            embeddings = [embedding]
        } else if let nova = value.novaEmbeddings {
            embeddings = nova.first.map { [$0.embedding] } ?? []
        } else {
            embeddings = value.embeddings ?? value.floatEmbeddings ?? []
        }
        let tokens: Int?
        switch value.tokenCount {
        case .value(let count): tokens = count
        case .missing:
            tokens = response.responseHeaders["x-amzn-bedrock-input-token-count"].flatMap(Double.init).flatMap(Int.init(exactly:))
        }
        return EmbeddingModelV4Result(embeddings: embeddings, usage: tokens.map(EmbeddingModelV4Usage.init(tokens:)), response: .init(headers: response.responseHeaders, body: response.rawValue), warnings: [])
    }
}

private struct BedrockEmbeddingResponse: Decodable, Sendable {
    struct NovaEmbedding: Codable, Sendable { let embeddingType: String; let embedding: [Double] }
    struct FloatEmbeddings: Decodable { let float: [[Double]] }
    enum TokenCount: Sendable { case missing, value(Int?) }
    let embedding: [Double]?
    let tokenCount: TokenCount
    let novaEmbeddings: [NovaEmbedding]?
    let embeddings: [[Double]]?
    let floatEmbeddings: [[Double]]?

    private enum CodingKeys: String, CodingKey { case embedding, inputTextTokenCount, inputTokenCount, embeddings }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        embedding = try container.decodeIfPresent([Double].self, forKey: .embedding)
        let inputTextTokenCount = try container.decodeIfPresent(Double.self, forKey: .inputTextTokenCount)
        let inputTokenCount = try container.decodeIfPresent(Double.self, forKey: .inputTokenCount)
        tokenCount = (inputTextTokenCount ?? inputTokenCount).map { .value(Int(exactly: $0)) } ?? .missing
        novaEmbeddings = try? container.decode([NovaEmbedding].self, forKey: .embeddings)
        embeddings = try? container.decode([[Double]].self, forKey: .embeddings)
        floatEmbeddings = (try? container.decode(FloatEmbeddings.self, forKey: .embeddings))?.float
        guard (embedding != nil && inputTextTokenCount != nil) || novaEmbeddings != nil || embeddings != nil || floatEmbeddings != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected embedding response shape."))
        }
    }
}

private let bedrockEmbeddingResponseSchema = FlexibleSchema(Schema<BedrockEmbeddingResponse>.codable(
    BedrockEmbeddingResponse.self,
    jsonSchema: .object(["type": .string("object")])
))
