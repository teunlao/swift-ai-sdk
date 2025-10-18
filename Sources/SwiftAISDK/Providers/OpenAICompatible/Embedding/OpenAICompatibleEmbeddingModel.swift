import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleEmbeddingConfig: Sendable {
    public let provider: String
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let headers: @Sendable () -> [String: String]
    public let fetch: FetchFunction?
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let maxEmbeddingsPerCall: Int?
    public let supportsParallelCalls: Bool?

    public init(
        provider: String,
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        headers: @escaping @Sendable () -> [String: String],
        fetch: FetchFunction? = nil,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        maxEmbeddingsPerCall: Int? = nil,
        supportsParallelCalls: Bool? = nil
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.errorConfiguration = errorConfiguration
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        self.supportsParallelCalls = supportsParallelCalls
    }
}

public final class OpenAICompatibleEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleEmbeddingModelId
    private let config: OpenAICompatibleEmbeddingConfig

    public init(modelId: OpenAICompatibleEmbeddingModelId, config: OpenAICompatibleEmbeddingConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private var providerOptionsName: String {
        provider.split(separator: ".").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { config.maxEmbeddingsPerCall ?? 2048 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { config.supportsParallelCalls ?? true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        fatalError("OpenAICompatibleEmbeddingModel.doEmbed not yet implemented")
    }
}
