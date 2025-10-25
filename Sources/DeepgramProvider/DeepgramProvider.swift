import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepgram/src/deepgram-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct DeepgramProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class DeepgramProvider: ProviderV3 {
    private let transcriptionFactory: @Sendable (DeepgramTranscriptionModelId) -> DeepgramTranscriptionModel

    init(transcriptionFactory: @escaping @Sendable (DeepgramTranscriptionModelId) -> DeepgramTranscriptionModel) {
        self.transcriptionFactory = transcriptionFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        transcription(modelId: DeepgramTranscriptionModelId(rawValue: modelId))
    }

    public func transcription(modelId: DeepgramTranscriptionModelId) -> DeepgramTranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func callAsFunction(_ modelId: DeepgramTranscriptionModelId) -> DeepgramTranscriptionModel {
        transcription(modelId: modelId)
    }
}

public func createDeepgramProvider(settings: DeepgramProviderSettings = .init()) -> DeepgramProvider {
    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "DEEPGRAM_API_KEY",
                description: "Deepgram"
            )
        } catch {
            fatalError("Deepgram API key is missing: \(error)")
        }

        computed["Authorization"] = "Token \(apiKey)"
        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed.compactMapValues { $0 }, "ai-sdk/deepgram/\(DEEPGRAM_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let transcriptionFactory: @Sendable (DeepgramTranscriptionModelId) -> DeepgramTranscriptionModel = { modelId in
        DeepgramTranscriptionModel(
            modelId: modelId,
            config: DeepgramTranscriptionModel.Config(
                provider: "deepgram.transcription",
                url: { options in
                    "https://api.deepgram.com\(options.path)"
                },
                headers: headersClosure,
                fetch: settings.fetch,
                currentDate: { Date() }
            )
        )
    }

    return DeepgramProvider(transcriptionFactory: transcriptionFactory)
}

public let deepgram = createDeepgramProvider()
