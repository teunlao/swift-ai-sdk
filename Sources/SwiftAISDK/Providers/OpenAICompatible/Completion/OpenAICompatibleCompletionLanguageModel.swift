import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleCompletionConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let fetch: FetchFunction?
    public let includeUsage: Bool
    public let errorConfiguration: OpenAICompatibleErrorConfiguration

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.includeUsage = includeUsage
        self.errorConfiguration = errorConfiguration
    }
}

public final class OpenAICompatibleCompletionLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleCompletionModelId
    private let config: OpenAICompatibleCompletionConfig

    public init(modelId: OpenAICompatibleCompletionModelId, config: OpenAICompatibleCompletionConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private var providerOptionsName: String {
        provider.split(separator: ".").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }

    public var supportedUrls: [String: [NSRegularExpression]] {
        [:]
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        fatalError("OpenAICompatibleCompletionLanguageModel.doGenerate not yet implemented")
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        fatalError("OpenAICompatibleCompletionLanguageModel.doStream not yet implemented")
    }
}
