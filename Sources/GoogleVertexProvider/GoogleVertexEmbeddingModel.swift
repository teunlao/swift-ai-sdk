import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-embedding-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct GoogleVertexEmbeddingConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
}

private struct GoogleVertexEmbeddingPrediction: Codable, Sendable {
    struct Embedding: Codable, Sendable {
        struct Statistics: Codable, Sendable {
            let tokenCount: Int

            private enum CodingKeys: String, CodingKey {
                case tokenCount = "token_count"
            }
        }

        let values: [Double]
        let statistics: Statistics
    }

    let embeddings: Embedding
}

private struct GoogleVertexEmbeddingResponse: Codable, Sendable {
    let predictions: [GoogleVertexEmbeddingPrediction]
}

private let googleVertexEmbeddingResponseSchema = FlexibleSchema(
    Schema.codable(
        GoogleVertexEmbeddingResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public final class GoogleVertexEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    private let modelIdentifier: GoogleVertexEmbeddingModelId
    private let config: GoogleVertexEmbeddingConfig

    init(modelId: GoogleVertexEmbeddingModelId, config: GoogleVertexEmbeddingConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 2048 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        let values = options.values
        let maxValues = try await maxEmbeddingsPerCall ?? Int.max
        if values.count > maxValues {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelIdentifier.rawValue,
                maxEmbeddingsPerCall: maxValues,
                values: values
            )
        }

        let vertexOptions = try await parseProviderOptions(
            provider: "vertex",
            providerOptions: options.providerOptions,
            schema: googleVertexEmbeddingProviderOptionsSchema
        )

        let googleOptions: GoogleVertexEmbeddingProviderOptions?
        if let vertexOptions {
            googleOptions = vertexOptions
        } else {
            googleOptions = try await parseProviderOptions(
                provider: "google",
                providerOptions: options.providerOptions,
                schema: googleVertexEmbeddingProviderOptionsSchema
            )
        }

        let instances: [JSONValue] = values.map { value in
            var instance: [String: JSONValue] = [
                "content": .string(value)
            ]

            if let overrides = googleOptions?.toInstanceOverrides() {
                for (key, entry) in overrides {
                    instance[key] = entry
                }
            }

            return .object(instance)
        }

        var parameters: [String: JSONValue] = [:]
        if let optionsParameters = googleOptions?.toParametersDictionary() {
            for (key, entry) in optionsParameters {
                parameters[key] = entry
            }
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/models/\(modelIdentifier.rawValue):predict",
            headers: headers,
            body: JSONValue.object([
                "instances": .array(instances),
                "parameters": .object(parameters)
            ]),
            failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVertexEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let embeddings = response.value.predictions.map { $0.embeddings.values }
        let tokens = response.value.predictions.reduce(0) { partialResult, prediction in
            partialResult + prediction.embeddings.statistics.tokenCount
        }

        return EmbeddingModelV3DoEmbedResult(
            embeddings: embeddings,
            usage: EmbeddingModelV3Usage(tokens: tokens),
            providerMetadata: nil,
            response: EmbeddingModelV3ResponseInfo(
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }
}
