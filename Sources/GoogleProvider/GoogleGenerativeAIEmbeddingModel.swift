import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GoogleGenerativeAIEmbeddingConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
}

private struct GoogleEmbeddingBatchResponse: Codable, Sendable {
    struct Item: Codable, Sendable {
        let values: [Double]
    }

    let embeddings: [Item]
}

private struct GoogleEmbeddingSingleResponse: Codable, Sendable {
    struct Embedding: Codable, Sendable {
        let values: [Double]
    }

    let embedding: Embedding
}

private let googleEmbeddingBatchResponseSchema = FlexibleSchema(
    Schema.codable(
        GoogleEmbeddingBatchResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let googleEmbeddingSingleResponseSchema = FlexibleSchema(
    Schema.codable(
        GoogleEmbeddingSingleResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

final class GoogleGenerativeAIEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    private let modelIdentifier: GoogleGenerativeAIEmbeddingModelId
    private let config: GoogleGenerativeAIEmbeddingConfig

    init(modelId: GoogleGenerativeAIEmbeddingModelId, config: GoogleGenerativeAIEmbeddingConfig) {
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
        let googleOptions = try await parseProviderOptions(
            provider: "google",
            providerOptions: options.providerOptions,
            schema: googleGenerativeAIEmbeddingProviderOptionsSchema
        )

        let maxValues = try await maxEmbeddingsPerCall ?? Int.max
        if options.values.count > maxValues {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: maxValues,
                values: options.values.map { $0 as Any }
            )
        }

        let combinedHeaders = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = combinedHeaders.compactMapValues { $0 }

        if options.values.count == 1, let value = options.values.first {
            let contentParts: [JSONValue] = [
                .object(["text": .string(value)])
            ]
            let content = JSONValue.object([
                "parts": .array(contentParts)
            ])

            var bodyObject: [String: JSONValue] = [
                "model": .string(getGoogleModelPath(modelIdentifier.rawValue)),
                "content": content
            ]

            if let dimensionality = googleOptions?.outputDimensionality {
                bodyObject["outputDimensionality"] = .number(Double(dimensionality))
            }

            if let taskType = googleOptions?.taskType {
                bodyObject["taskType"] = .string(taskType.rawValue)
            }

            let response = try await postJsonToAPI(
                url: "\(config.baseURL)/models/\(modelIdentifier.rawValue):embedContent",
                headers: normalizedHeaders,
                body: JSONValue.object(bodyObject),
                failedResponseHandler: googleFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: googleEmbeddingSingleResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            let embedding = response.value.embedding.values
            let responseInfo = EmbeddingModelV3ResponseInfo(
                headers: response.responseHeaders,
                body: response.rawValue
            )

            return EmbeddingModelV3DoEmbedResult(
                embeddings: [embedding],
                usage: nil,
                providerMetadata: nil,
                response: responseInfo
            )
        }

        var requests: [JSONValue] = []
        for value in options.values {
            var requestObject: [String: JSONValue] = [
                "model": .string(getGoogleModelPath(modelIdentifier.rawValue)),
                "content": .object([
                    "role": .string("user"),
                    "parts": .array([.object(["text": .string(value)])])
                ])
            ]

            if let dimensionality = googleOptions?.outputDimensionality {
                requestObject["outputDimensionality"] = .number(Double(dimensionality))
            }

            if let taskType = googleOptions?.taskType {
                requestObject["taskType"] = .string(taskType.rawValue)
            }

            requests.append(.object(requestObject))
        }

        let body = JSONValue.object(["requests": .array(requests)])

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/models/\(modelIdentifier.rawValue):batchEmbedContents",
            headers: normalizedHeaders,
            body: body,
            failedResponseHandler: googleFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleEmbeddingBatchResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let embeddings = response.value.embeddings.map { $0.values }
        let responseInfo = EmbeddingModelV3ResponseInfo(
            headers: response.responseHeaders,
            body: response.rawValue
        )

        return EmbeddingModelV3DoEmbedResult(
            embeddings: embeddings,
            usage: nil,
            providerMetadata: nil,
            response: responseInfo
        )
    }
}
