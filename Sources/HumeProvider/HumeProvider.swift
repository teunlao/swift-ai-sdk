import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/hume/src/hume-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct HumeProviderSettings: Sendable {
    public struct InternalSettings: Sendable {
        public var currentDate: @Sendable () -> Date

        public init(currentDate: @escaping @Sendable () -> Date = { Date() }) {
            self.currentDate = currentDate
        }
    }

    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var _internal: InternalSettings?

    public init(
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        _internal: InternalSettings? = nil
    ) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self._internal = _internal
    }
}

public final class HumeProvider: ProviderV3 {
    private let speechFactory: @Sendable (HumeSpeechModelId) -> HumeSpeechModel

    init(speechFactory: @escaping @Sendable (HumeSpeechModelId) -> HumeSpeechModel) {
        self.speechFactory = speechFactory
    }

    // MARK: - ProviderV3

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV3)? {
        speechFactory(HumeSpeechModelId(rawValue: modelId))
    }

    // MARK: - Convenience

    public func callAsFunction(_ modelId: HumeSpeechModelId = .default) -> HumeSpeechModel {
        speechFactory(modelId)
    }

    public func speech(_ modelId: HumeSpeechModelId = .default) -> HumeSpeechModel {
        speechFactory(modelId)
    }
}

public func createHume(settings: HumeProviderSettings = .init()) -> HumeProvider {
    let headersClosure: @Sendable () -> [String: String?] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "HUME_API_KEY",
                description: "Hume"
            )
        } catch {
            fatalError("Hume API key is missing: \(error)")
        }

        var headers: [String: String?] = [
            "X-Hume-Api-Key": apiKey
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk/hume/\(HUME_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let config = HumeConfig(
        provider: "hume.speech",
        url: { options in
            "https://api.hume.ai\(options.path)"
        },
        headers: headersClosure,
        fetch: settings.fetch
    )

    let providedCurrentDate: @Sendable () -> Date
    if let custom = settings._internal?.currentDate {
        providedCurrentDate = custom
    } else {
        providedCurrentDate = { Date() }
    }

    let factory: @Sendable (HumeSpeechModelId) -> HumeSpeechModel = { _ in
        HumeSpeechModel(
            modelId: "",
            config: HumeSpeechModelConfig(
                config: config,
                currentDate: providedCurrentDate
            )
        )
    }

    return HumeProvider(speechFactory: factory)
}

public let hume = createHume()
