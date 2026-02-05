import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-provider.ts
// Upstream commit: f3a72bc2
//===----------------------------------------------------------------------===//

public struct FalProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, baseURL: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

public final class FalProvider: ProviderV3 {
    private let imageFactory: @Sendable (FalImageModelId) -> FalImageModel
    private let transcriptionFactory: @Sendable (FalTranscriptionModelId) -> FalTranscriptionModel
    private let speechFactory: @Sendable (FalSpeechModelId) -> FalSpeechModel
    private let videoFactory: @Sendable (FalVideoModelId) -> FalVideoModel

    init(
        imageFactory: @escaping @Sendable (FalImageModelId) -> FalImageModel,
        transcriptionFactory: @escaping @Sendable (FalTranscriptionModelId) -> FalTranscriptionModel,
        speechFactory: @escaping @Sendable (FalSpeechModelId) -> FalSpeechModel,
        videoFactory: @escaping @Sendable (FalVideoModelId) -> FalVideoModel
    ) {
        self.imageFactory = imageFactory
        self.transcriptionFactory = transcriptionFactory
        self.speechFactory = speechFactory
        self.videoFactory = videoFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        image(modelId: FalImageModelId(rawValue: modelId))
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV3)? {
        speech(modelId: FalSpeechModelId(rawValue: modelId))
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        transcription(modelId: FalTranscriptionModelId(rawValue: modelId))
    }

    public func image(modelId: FalImageModelId) -> FalImageModel {
        imageFactory(modelId)
    }

    public func image(_ modelId: FalImageModelId) -> FalImageModel {
        imageFactory(modelId)
    }

    public func speech(modelId: FalSpeechModelId) -> FalSpeechModel {
        speechFactory(modelId)
    }

    public func speech(_ modelId: FalSpeechModelId) -> FalSpeechModel {
        speechFactory(modelId)
    }

    public func transcription(modelId: FalTranscriptionModelId) -> FalTranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func transcription(_ modelId: FalTranscriptionModelId) -> FalTranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func video(modelId: FalVideoModelId) -> FalVideoModel {
        videoFactory(modelId)
    }

    public func video(_ modelId: FalVideoModelId) -> FalVideoModel {
        videoFactory(modelId)
    }
}

public func createFalProvider(settings: FalProviderSettings = .init()) -> FalProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL ?? "https://fal.run") ?? "https://fal.run"

    let headersClosure: @Sendable () -> [String: String?] = {
        var values: [String: String?] = [:]
        let apiKey: String
        do {
            apiKey = try loadFalAPIKey(apiKey: settings.apiKey)
        } catch {
            fatalError("Fal API key is missing: \(error)")
        }

        values["Authorization"] = "Key \(apiKey)"
        if let custom = settings.headers {
            for (key, value) in custom {
                values[key] = value
            }
        }

        let withUA = withUserAgentSuffix(values, "ai-sdk/fal/\(FAL_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let fetch = settings.fetch

    let imageFactory: @Sendable (FalImageModelId) -> FalImageModel = { modelId in
        FalImageModel(
            modelId: modelId,
            config: FalImageModelConfig(
                provider: "fal.image",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    let transcriptionFactory: @Sendable (FalTranscriptionModelId) -> FalTranscriptionModel = { modelId in
        FalTranscriptionModel(
            modelId: modelId,
            config: FalConfig(
                provider: "fal.transcription",
                url: { options in options.path },
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    let speechFactory: @Sendable (FalSpeechModelId) -> FalSpeechModel = { modelId in
        FalSpeechModel(
            modelId: modelId,
            config: FalConfig(
                provider: "fal.speech",
                url: { options in options.path },
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    let videoFactory: @Sendable (FalVideoModelId) -> FalVideoModel = { modelId in
        FalVideoModel(
            modelId: modelId,
            config: FalConfig(
                provider: "fal.video",
                url: { options in options.path },
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    return FalProvider(
        imageFactory: imageFactory,
        transcriptionFactory: transcriptionFactory,
        speechFactory: speechFactory,
        videoFactory: videoFactory
    )
}

/// Alias matching upstream naming (`createFal`).
public func createFal(settings: FalProviderSettings = .init()) -> FalProvider {
    createFalProvider(settings: settings)
}

public let fal = createFalProvider()

// MARK: - API Key Loading

private func loadFalAPIKey(apiKey: String?) throws -> String {
    if let apiKey {
        return apiKey
    }

    let environment = ProcessInfo.processInfo.environment
    if let key = environment["FAL_API_KEY"], !key.isEmpty {
        return key
    }
    if let key = environment["FAL_KEY"], !key.isEmpty {
        return key
    }

    throw LoadAPIKeyError(
        message: "fal.ai API key is missing. Pass it using the 'apiKey' parameter or set either the FAL_API_KEY or FAL_KEY environment variable."
    )
}
