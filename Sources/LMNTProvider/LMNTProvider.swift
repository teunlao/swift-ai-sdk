import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Settings for configuring the LMNT provider.
/// Mirrors `packages/lmnt/src/lmnt-provider.ts`.
public struct LMNTProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class LMNTProvider: ProviderV3 {
    private let speechFactory: @Sendable (LMNTSpeechModelId) -> LMNTSpeechModel

    init(speechFactory: @escaping @Sendable (LMNTSpeechModelId) -> LMNTSpeechModel) {
        self.speechFactory = speechFactory
    }

    // ProviderV3
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
        speechFactory(LMNTSpeechModelId(rawValue: modelId))
    }

    // Convenience
    public func callAsFunction(_ modelId: LMNTSpeechModelId) -> LMNTSpeechModel {
        speechFactory(modelId)
    }

    public func speech(_ modelId: LMNTSpeechModelId) -> LMNTSpeechModel {
        speechFactory(modelId)
    }
}

/// Create an LMNT provider instance.
public func createLMNT(settings: LMNTProviderSettings = .init()) -> LMNTProvider {
    let headersClosure: @Sendable () -> [String: String?] = {
        var base: [String: String?] = [:]
        let key: String
        do {
            key = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "LMNT_API_KEY",
                description: "LMNT"
            )
        } catch {
            fatalError("LMNT API key is missing: \(error)")
        }
        base["x-api-key"] = key
        if let custom = settings.headers {
            for (k, v) in custom { base[k] = v }
        }
        let withUA = withUserAgentSuffix(base, "ai-sdk/lmnt/\(LMNT_PROVIDER_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let factory: @Sendable (LMNTSpeechModelId) -> LMNTSpeechModel = { modelId in
        LMNTSpeechModel(
            modelId,
            config: LMNTConfig(
                provider: "lmnt.speech",
                url: { opts in "https://api.lmnt.com\(opts.path)" },
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return LMNTProvider(speechFactory: factory)
}

/// Default LMNT provider instance.
public let lmnt = createLMNT()
