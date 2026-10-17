import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GoogleEmbeddingConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
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

final class GoogleEmbeddingModel: EmbeddingModelV4, EmbeddingModelProviderOptionsTransformer {

    private let modelIdentifier: GoogleEmbeddingModelId
    private let config: GoogleEmbeddingConfig

    init(modelId: GoogleEmbeddingModelId, config: GoogleEmbeddingConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 100 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func transformProviderOptions(_ options: EmbeddingModelProviderOptionsTransformerOptions) async throws -> SharedV4ProviderOptions? {
        guard case .array(let content) = options.providerOptions?["google"]?["content"] else {
            return options.providerOptions
        }
        try validateContentCount(content.count, values: options.values)
        var result = options.providerOptions ?? [:]
        result["google", default: [:]]["content"] = .array(Array(content[options.startIndex..<options.endIndex]))
        return result
    }

    private func validateContentCount(_ count: Int?, values: [String]) throws {
        if let count, count != values.count {
            throw InvalidArgumentError(argument: "providerOptions.google.content", message: "The number of multimodal content entries (\(count)) must match the number of values (\(values.count)).")
        }
    }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
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

        try validateContentCount(googleOptions?.content?.count, values: options.values)
        let dimensionality = googleOptions?.outputDimensionality ?? options.dimensions
        func parts(_ value: String, index: Int) -> [JSONValue] {
            guard let content = googleOptions?.content?[index] else { return [.object(["text": .string(value)])] }
            return (value.isEmpty ? [] : [.object(["text": .string(value)])]) + content
        }
        let combinedHeaders = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = combinedHeaders.compactMapValues { $0 }

        if options.values.count == 1, let value = options.values.first {
            let contentParts = parts(value, index: 0)
            let content = JSONValue.object([
                "parts": .array(contentParts)
            ])

            var bodyObject: [String: JSONValue] = [
                "model": .string("models/\(modelIdentifier.rawValue)"),
                "content": content
            ]

            if let dimensionality {
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
            let responseInfo = EmbeddingModelV4ResponseInfo(
                headers: response.responseHeaders,
                body: response.rawValue
            )

            return EmbeddingModelV4Result(
                embeddings: [embedding],
                usage: nil,
                providerMetadata: nil,
                response: responseInfo
            )
        }

        var requests: [JSONValue] = []
        for (index, value) in options.values.enumerated() {
            var requestObject: [String: JSONValue] = [
                "model": .string("models/\(modelIdentifier.rawValue)"),
                "content": .object([
                    "role": .string("user"),
                    "parts": .array(parts(value, index: index))
                ])
            ]

            if let dimensionality {
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
        let responseInfo = EmbeddingModelV4ResponseInfo(
            headers: response.responseHeaders,
            body: response.rawValue
        )

        return EmbeddingModelV4Result(
            embeddings: embeddings,
            usage: nil,
            providerMetadata: nil,
            response: responseInfo
        )
    }
}
