import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleChatConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let fetch: FetchFunction?
    public let includeUsage: Bool
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let metadataExtractor: OpenAICompatibleMetadataExtractor?
    public let supportsStructuredOutputs: Bool
    public let supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])?

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        metadataExtractor: OpenAICompatibleMetadataExtractor? = nil,
        supportsStructuredOutputs: Bool = false,
        supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])? = nil
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.includeUsage = includeUsage
        self.errorConfiguration = errorConfiguration
        self.metadataExtractor = metadataExtractor
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.supportedUrls = supportedUrls
    }
}

public final class OpenAICompatibleChatLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleChatModelId
    private let config: OpenAICompatibleChatConfig

    public init(modelId: OpenAICompatibleChatModelId, config: OpenAICompatibleChatConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private var providerOptionsName: String {
        provider.split(separator: ".").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            try await config.supportedUrls?() ?? [:]
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        fatalError("OpenAICompatibleChatLanguageModel.doGenerate not yet implemented")
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        fatalError("OpenAICompatibleChatLanguageModel.doStream not yet implemented")
    }
}
