import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GoogleVertexEmbeddingConfig: Sendable {
    let provider: String
    let baseURL: @Sendable () throws -> String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
}

private struct GoogleVertexEmbeddingResponse: Codable, Sendable {
    struct Prediction: Codable, Sendable {
        struct Embedding: Codable, Sendable {
            struct Statistics: Codable, Sendable {
                let token_count: Int
            }
            let values: [Double]
            let statistics: Statistics
        }
        let embeddings: Embedding
    }
    let predictions: [Prediction]
}

private struct GoogleVertexEmbedContentResponse: Codable, Sendable {
    struct Embedding: Codable, Sendable { let values: [Double] }
    struct Usage: Codable, Sendable { let promptTokenCount: Int? }
    let embedding: Embedding
    let usageMetadata: Usage?
}

public final class GoogleVertexEmbeddingModel: EmbeddingModelV4 {
    private let modelIdentifier: GoogleVertexEmbeddingModelId
    private let config: GoogleVertexEmbeddingConfig

    init(modelId: GoogleVertexEmbeddingModelId, config: GoogleVertexEmbeddingConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    private var usesEmbedContent: Bool {
        modelId == "gemini-embedding-2" || modelId == "gemini-embedding-2-preview"
    }
    public var maxEmbeddingsPerCall: Int? { get async throws { usesEmbedContent ? 1 : 250 } }
    public var supportsParallelCalls: Bool { get async throws { true } }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let googleOptions = try await parseVertexOptions(
            options.providerOptions,
            schema: googleVertexEmbeddingModelOptionsSchema,
            namespaces: ["googleVertex", "vertex", "google"]
        )
        let maximum = usesEmbedContent ? 1 : 250
        if options.values.count > maximum {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider, modelId: modelId,
                maxEmbeddingsPerCall: maximum, values: options.values
            )
        }
        var parameters = googleOptions?.toParametersDictionary() ?? [:]
        if parameters["outputDimensionality"] == nil, let dimensions = options.dimensions {
            parameters["outputDimensionality"] = .number(Double(dimensions))
        }
        let headers = combineHeaders(try config.headers(), options.headers).compactMapValues { $0 }
        if usesEmbedContent {
            var embedConfig = parameters
            if let taskType = googleOptions?.taskType { embedConfig["taskType"] = .string(taskType.rawValue) }
            if let title = googleOptions?.title { embedConfig["title"] = .string(title) }
            let part: JSONObject = options.values.first.map { ["text": .string($0)] } ?? [:]
            let response = try await postJsonToAPI(
                url: "\(try config.baseURL())/models/\(modelId):embedContent",
                headers: headers,
                body: JSONValue.object([
                    "content": .object(["parts": .array([.object(part)])]),
                    "embedContentConfig": .object(embedConfig)
                ]),
                failedResponseHandler: googleVertexFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: FlexibleSchema(Schema.codable(
                    GoogleVertexEmbedContentResponse.self, jsonSchema: .object(["type": .string("object")])
                ))),
                isAborted: options.abortSignal, fetch: config.fetch
            )
            return EmbeddingModelV4Result(
                embeddings: [response.value.embedding.values],
                usage: response.value.usageMetadata?.promptTokenCount.map { .init(tokens: $0) },
                response: .init(headers: response.responseHeaders, body: response.rawValue)
            )
        }
        let instances = options.values.map { value -> JSONValue in
            var instance = googleOptions?.toInstanceOverrides() ?? [:]
            instance["content"] = .string(value)
            return .object(instance)
        }
        let response = try await postJsonToAPI(
            url: "\(try config.baseURL())/models/\(modelId):predict", headers: headers,
            body: JSONValue.object(["instances": .array(instances), "parameters": .object(parameters)]),
            failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: FlexibleSchema(Schema.codable(
                GoogleVertexEmbeddingResponse.self, jsonSchema: .object(["type": .string("object")])
            ))),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        return EmbeddingModelV4Result(
            embeddings: response.value.predictions.map { $0.embeddings.values },
            usage: .init(tokens: response.value.predictions.reduce(0) { $0 + $1.embeddings.statistics.token_count }),
            response: .init(headers: response.responseHeaders, body: response.rawValue)
        )
    }
}

func parseVertexOptions<Value: Sendable>(
    _ options: SharedV4ProviderOptions?, schema: FlexibleSchema<Value>,
    namespaces: [String] = ["googleVertex", "vertex"]
) async throws -> Value? {
    for namespace in namespaces {
        if let parsed = try await parseProviderOptions(provider: namespace, providerOptions: options, schema: schema) {
            return parsed
        }
    }
    return nil
}
