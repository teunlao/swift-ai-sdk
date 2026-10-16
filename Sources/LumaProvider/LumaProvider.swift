import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/luma/src/luma-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct LumaProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

public final class LumaProvider: ProviderV4 {
    private let imageFactory: @Sendable (LumaImageModelId) -> LumaImageModel

    init(imageFactory: @escaping @Sendable (LumaImageModelId) -> LumaImageModel) {
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        image(modelId: LumaImageModelId(rawValue: modelId))
    }

    public func image(modelId: LumaImageModelId) -> LumaImageModel {
        imageFactory(modelId)
    }

    public func imageModel(_ modelId: LumaImageModelId) -> LumaImageModel {
        imageFactory(modelId)
    }
}

private let defaultLumaBaseURL = "https://api.lumalabs.ai"

public func createLuma(settings: LumaProviderSettings = .init()) -> LumaProvider {
    let normalizedBaseURL = withoutTrailingSlash(settings.baseURL ?? defaultLumaBaseURL) ?? defaultLumaBaseURL
    let fetch = settings.fetch

    let headersClosure: @Sendable () throws -> [String: String?] = {
        let apiKey = try loadAPIKey(
            apiKey: settings.apiKey,
            environmentVariableName: "LUMA_API_KEY",
            description: "Luma"
        )
        var baseHeaders: [String: String?] = ["Authorization": "Bearer \(apiKey)"]

        if let headers = settings.headers {
            for (key, value) in headers {
                baseHeaders[key] = value
            }
        }

        let withUA = withUserAgentSuffix(baseHeaders, "ai-sdk-luma/\(LUMA_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let imageFactory: @Sendable (LumaImageModelId) -> LumaImageModel = { modelId in
        LumaImageModel(
            modelId: modelId,
            config: LumaImageModelConfig(
                provider: "luma.image",
                baseURL: normalizedBaseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    return LumaProvider(imageFactory: imageFactory)
}

public let luma = createLuma()
