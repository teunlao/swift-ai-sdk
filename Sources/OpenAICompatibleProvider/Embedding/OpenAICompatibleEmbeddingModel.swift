import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleEmbeddingConfig: Sendable {
    public let provider: String
    public let url: @Sendable (OpenAICompatibleURLOptions) throws -> String
    public let headers: @Sendable () async throws -> [String: String]
    public let fetch: FetchFunction?
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let maxEmbeddingsPerCallOverride: Int?
    public let supportsParallelCallsOverride: Bool?

    public init(provider: String, url: @escaping @Sendable (OpenAICompatibleURLOptions) throws -> String,
                headers: @escaping @Sendable () async throws -> [String: String] = { [:] }, fetch: FetchFunction? = nil,
                errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
                maxEmbeddingsPerCall: Int? = nil, supportsParallelCalls: Bool? = nil) {
        self.provider = provider; self.url = url; self.headers = headers; self.fetch = fetch
        self.errorConfiguration = errorConfiguration
        self.maxEmbeddingsPerCallOverride = maxEmbeddingsPerCall
        self.supportsParallelCallsOverride = supportsParallelCalls
    }
}

public final class OpenAICompatibleEmbeddingModel: EmbeddingModelV4 {
    public let specificationVersion = "v4"
    public let modelId: String
    public var provider: String { config.provider }
    public var maxEmbeddingsPerCall: Int? { get async throws { config.maxEmbeddingsPerCallOverride ?? 2048 } }
    public var supportsParallelCalls: Bool { get async throws { config.supportsParallelCallsOverride ?? true } }
    private let config: OpenAICompatibleEmbeddingConfig
    private var providerOptionsName: String { provider.split(separator: ".").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "" }

    public init(modelId: OpenAICompatibleEmbeddingModelId, config: OpenAICompatibleEmbeddingConfig) {
        self.modelId = modelId.rawValue; self.config = config
    }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        var warnings: [SharedV4Warning] = []
        let deprecated = try await parseProviderOptions(provider: "openai-compatible", providerOptions: options.providerOptions,
                                                       schema: openAICompatibleEmbeddingProviderOptionsSchema)
        if deprecated != nil { warnings.append(.deprecated(setting: "providerOptions key 'openai-compatible'", message: "Use 'openaiCompatible' instead.")) }
        if let warning = openAICompatibleDeprecatedProviderOptionsWarning(rawName: providerOptionsName, providerOptions: options.providerOptions) { warnings.append(warning) }
        let compatible = try await parseProviderOptions(provider: "openaiCompatible", providerOptions: options.providerOptions,
                                                        schema: openAICompatibleEmbeddingProviderOptionsSchema)
        let specific = try await parseProviderOptions(provider: providerOptionsName, providerOptions: options.providerOptions,
                                                      schema: openAICompatibleEmbeddingProviderOptionsSchema)
        let dimensions = specific?.dimensions ?? compatible?.dimensions ?? deprecated?.dimensions ?? options.dimensions.map(Double.init)
        let user = specific?.user ?? compatible?.user ?? deprecated?.user
        let maximum = config.maxEmbeddingsPerCallOverride ?? 2048
        guard options.values.count <= maximum else {
            throw TooManyEmbeddingValuesForCallError(provider: provider, modelId: modelId, maxEmbeddingsPerCall: maximum, values: options.values.map { $0 as Any })
        }
        var body: [String: JSONValue] = ["model": .string(modelId), "input": .array(options.values.map(JSONValue.string)), "encoding_format": "float"]
        if let dimensions { body["dimensions"] = .number(dimensions) }
        if let user { body["user"] = .string(user) }
        let headers = combineHeaders(try await config.headers().mapValues(Optional.some), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }
        let response = try await postJsonToAPI(url: try config.url(.init(modelId: modelId, path: "/embeddings")), headers: headers,
                                               body: JSONValue.object(body), failedResponseHandler: config.errorConfiguration.failedResponseHandler,
                                               successfulResponseHandler: createJsonResponseHandler(responseSchema: embeddingResponseSchema),
                                               isAborted: options.abortSignal, fetch: config.fetch)
        return .init(embeddings: response.value.data.map(\.embedding), usage: response.value.usage.map { .init(tokens: $0.promptTokens) },
                     providerMetadata: response.value.providerMetadata,
                     response: .init(headers: response.responseHeaders, body: response.rawValue), warnings: warnings)
    }
}

private struct EmbeddingResponse: Decodable, Sendable {
    struct Item: Decodable, Sendable { let embedding: [Double] }
    struct Usage: Decodable, Sendable {
        let promptTokens: Int
        enum CodingKeys: String, CodingKey { case promptTokens = "prompt_tokens" }
    }
    let data: [Item]
    let usage: Usage?
    let providerMetadata: SharedV4ProviderMetadata?
}
private let embeddingResponseSchema = FlexibleSchema(Schema<EmbeddingResponse>.codable(EmbeddingResponse.self, jsonSchema: ["type": "object"]))
