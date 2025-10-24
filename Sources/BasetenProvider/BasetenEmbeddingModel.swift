import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

final class BasetenEmbeddingModel: EmbeddingModelV3 {
    typealias VALUE = String

    private let delegate: OpenAICompatibleEmbeddingModel
    private let headersClosure: @Sendable () -> [String: String]
    private let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String
    private let fetch: FetchFunction?
    private let errorConfiguration: OpenAICompatibleErrorConfiguration
    private let performanceClient: BasetenPerformanceClient?

    init(
        delegate: OpenAICompatibleEmbeddingModel,
        headers: @escaping @Sendable () -> [String: String],
        urlBuilder: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction?,
        errorConfiguration: OpenAICompatibleErrorConfiguration,
        performanceClient: BasetenPerformanceClient?
    ) {
        self.delegate = delegate
        self.headersClosure = headers
        self.urlBuilder = urlBuilder
        self.fetch = fetch
        self.errorConfiguration = errorConfiguration
        self.performanceClient = performanceClient
    }

    var provider: String { delegate.provider }
    var modelId: String { delegate.modelId }

    var maxEmbeddingsPerCall: Int? {
        get async throws { try await delegate.maxEmbeddingsPerCall }
    }

    var supportsParallelCalls: Bool {
        get async throws { try await delegate.supportsParallelCalls }
    }

    func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        guard let performanceClient else {
            return try await delegate.doEmbed(options: options)
        }

        let baseHeaders = headersClosure().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let mergedHeaders = combineHeaders(baseHeaders, requestHeaders).compactMapValues { $0 }

        let response = try await performanceClient.embed(
            values: options.values,
            modelId: delegate.modelId,
            headers: mergedHeaders,
            abortSignal: options.abortSignal
        )

        let embeddings = response.value.data.map { $0.embedding }
        let usageTokens = response.value.usage?.totalTokens
        let usage = usageTokens.map { EmbeddingModelV3Usage(tokens: $0) }

        return EmbeddingModelV3DoEmbedResult(
            embeddings: embeddings,
            usage: usage,
            response: EmbeddingModelV3ResponseInfo(
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }
}

struct BasetenPerformanceEmbedRequest: Encodable {
    let model: String
    let input: [String]
}

struct BasetenPerformanceEmbedResponse: Codable {
    struct DataItem: Codable {
        let embedding: [Double]
    }

    struct Usage: Codable {
        let totalTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case totalTokens = "total_tokens"
        }
    }

    let data: [DataItem]
    let usage: Usage?
}

private let basetenPerformanceEmbedResponseSchema = FlexibleSchema(
    Schema<BasetenPerformanceEmbedResponse>.codable(
        BasetenPerformanceEmbedResponse.self,
        jsonSchema: JSONValue.object(["type": .string("object")])
    )
)

final class BasetenPerformanceClient: @unchecked Sendable {
    private let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String
    private let errorConfiguration: OpenAICompatibleErrorConfiguration
    private let fetch: FetchFunction?

    init(
        urlBuilder: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        errorConfiguration: OpenAICompatibleErrorConfiguration,
        fetch: FetchFunction?
    ) {
        self.urlBuilder = urlBuilder
        self.errorConfiguration = errorConfiguration
        self.fetch = fetch
    }

    func embed(
        values: [String],
        modelId: String,
        headers: [String: String],
        abortSignal: (@Sendable () -> Bool)?
    ) async throws -> ResponseHandlerResult<BasetenPerformanceEmbedResponse> {
        let url = urlBuilder(OpenAICompatibleURLOptions(modelId: modelId, path: "/embeddings"))
        let request = BasetenPerformanceEmbedRequest(model: modelId, input: values)

        return try await postJsonToAPI(
            url: url,
            headers: headers,
            body: request,
            failedResponseHandler: errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: basetenPerformanceEmbedResponseSchema),
            isAborted: abortSignal,
            fetch: fetch
        )
    }
}
