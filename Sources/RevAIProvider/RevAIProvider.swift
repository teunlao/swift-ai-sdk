import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/revai/src/revai-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct RevAIProviderSettings: Sendable {
    /// API key for authenticating requests.
    public var apiKey: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation (useful for tests / middleware).
    public var fetch: FetchFunction?

    public init(
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class RevAIProvider: ProviderV3 {
    public struct Models: Sendable {
        public let transcription: RevAITranscriptionModel
    }

    private let transcriptionFactory: @Sendable (RevAITranscriptionModelId) -> RevAITranscriptionModel

    init(transcriptionFactory: @escaping @Sendable (RevAITranscriptionModelId) -> RevAITranscriptionModel) {
        self.transcriptionFactory = transcriptionFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .languageModel,
            message: "Rev.ai does not provide language models"
        )
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .textEmbeddingModel,
            message: "Rev.ai does not provide text embedding models"
        )
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .imageModel,
            message: "Rev.ai does not provide image models"
        )
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        let identifier = RevAITranscriptionModelId(rawValue: modelId)
        guard identifier == .machine || identifier == .lowCost || identifier == .fusion else {
            throw NoSuchModelError(modelId: modelId, modelType: .transcriptionModel)
        }
        return transcription(modelId: identifier)
    }

    public func transcription(modelId: RevAITranscriptionModelId = .machine) -> RevAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func callAsFunction(_ modelId: RevAITranscriptionModelId = .machine) -> Models {
        Models(transcription: transcription(modelId: modelId))
    }
}

public func createRevAIProvider(settings: RevAIProviderSettings = .init()) -> RevAIProvider {
    let headersClosure: @Sendable () -> [String: String?] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "REVAI_API_KEY",
                description: "Rev.ai"
            )
        } catch {
            fatalError("Rev.ai API key is missing: \(error)")
        }

        var computed: [String: String?] = [
            "authorization": "Bearer \(apiKey)",
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk/revai/\(REVAI_VERSION)"
        )
        return withUA.mapValues { Optional($0) }
    }

    let transcriptionFactory: @Sendable (RevAITranscriptionModelId) -> RevAITranscriptionModel = { modelId in
        RevAITranscriptionModel(
            modelId: modelId,
            config: RevAIConfig(
                provider: "revai.transcription",
                url: { options in "https://api.rev.ai\(options.path)" },
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return RevAIProvider(transcriptionFactory: transcriptionFactory)
}

public let revai = createRevAIProvider()

