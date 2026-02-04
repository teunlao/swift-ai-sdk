import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/prodia/src/prodia-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct ProdiaProviderSettings: Sendable {
    /// Prodia API key. Default value is taken from the `PRODIA_TOKEN` environment variable.
    public var apiKey: String?

    /// Base URL for the API calls. Defaults to `https://inference.prodia.com/v2`.
    public var baseURL: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation (useful for tests / middleware).
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

public final class ProdiaProvider: ProviderV3 {
    private let imageFactory: @Sendable (ProdiaImageModelId) -> ProdiaImageModel

    init(imageFactory: @escaping @Sendable (ProdiaImageModelId) -> ProdiaImageModel) {
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(ProdiaImageModelId(rawValue: modelId))
    }

    public func image(modelId: ProdiaImageModelId) -> ProdiaImageModel {
        imageFactory(modelId)
    }
}

private let defaultBaseURL = "https://inference.prodia.com/v2"

public func createProdiaProvider(settings: ProdiaProviderSettings = .init()) -> ProdiaProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? defaultBaseURL

    let headersClosure: @Sendable () -> [String: String?] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "PRODIA_TOKEN",
                description: "Prodia"
            )
        } catch {
            fatalError("Prodia API key is missing: \(error)")
        }

        var computed: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk/prodia/\(PRODIA_VERSION)"
        )
        return withUA.mapValues { Optional($0) }
    }

    let imageFactory: @Sendable (ProdiaImageModelId) -> ProdiaImageModel = { modelId in
        ProdiaImageModel(
            modelId: modelId,
            config: ProdiaImageModelConfig(
                provider: "prodia.image",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return ProdiaProvider(imageFactory: imageFactory)
}

public let prodia = createProdiaProvider()

