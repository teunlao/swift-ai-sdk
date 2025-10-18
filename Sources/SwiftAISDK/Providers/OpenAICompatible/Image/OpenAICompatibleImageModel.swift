import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleImageModelConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let fetch: FetchFunction?
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let currentDate: @Sendable () -> Date

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.errorConfiguration = errorConfiguration
        self.currentDate = currentDate
    }
}

public final class OpenAICompatibleImageModel: ImageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleImageModelId
    private let config: OpenAICompatibleImageModelConfig

    public init(modelId: OpenAICompatibleImageModelId, config: OpenAICompatibleImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(10) }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        fatalError("OpenAICompatibleImageModel.doGenerate not yet implemented")
    }
}
