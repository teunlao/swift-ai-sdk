import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/assemblyai/src/assemblyai-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct AssemblyAIProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class AssemblyAIProvider: ProviderV3 {
    private let transcriptionFactory: @Sendable (AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel

    init(transcriptionFactory: @escaping @Sendable (AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel) {
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
        transcription(modelId: AssemblyAITranscriptionModelId(rawValue: modelId))
    }

    public func transcription(modelId: AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func callAsFunction(_ modelId: AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel {
        transcription(modelId: modelId)
    }
}

public func createAssemblyAIProvider(settings: AssemblyAIProviderSettings = .init()) -> AssemblyAIProvider {
    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "ASSEMBLYAI_API_KEY",
                description: "AssemblyAI"
            )
        } catch {
            fatalError("AssemblyAI API key is missing: \(error)")
        }

        computed["authorization"] = apiKey
        if let custom = settings.headers {
            for (key, value) in custom {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed.compactMapValues { $0 }, "ai-sdk/assemblyai/\(ASSEMBLYAI_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let transcriptionFactory: @Sendable (AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel = { modelId in
        AssemblyAITranscriptionModel(
            modelId: modelId,
            config: AssemblyAITranscriptionModel.Config(
                provider: "assemblyai.transcription",
                url: { options in
                    "https://api.assemblyai.com\(options.path)"
                },
                headers: headersClosure,
                fetch: settings.fetch,
                currentDate: { Date() }
            )
        )
    }

    return AssemblyAIProvider(transcriptionFactory: transcriptionFactory)
}

public let assemblyai = createAssemblyAIProvider()
