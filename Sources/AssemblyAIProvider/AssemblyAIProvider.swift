import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AssemblyAIProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey; self.headers = headers; self.fetch = fetch
    }
}

public final class AssemblyAIProvider: ProviderV4 {
    public struct Models: Sendable { public let transcription: AssemblyAITranscriptionModel }
    private let config: AssemblyAITranscriptionModel.Config
    init(settings: AssemblyAIProviderSettings) {
        config = .init(provider: "assemblyai.transcription", headers: {
            let headers = combineHeaders(
                ["authorization": try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "ASSEMBLYAI_API_KEY", description: "AssemblyAI")],
                settings.headers?.mapValues(Optional.some)
            )
            return withUserAgentSuffix(headers, "ai-sdk-assemblyai/\(ASSEMBLYAI_VERSION)").mapValues(Optional.some)
        }, fetch: settings.fetch)
    }
    public func transcription(modelId: AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel { .init(modelId: modelId, config: config) }
    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV4)? { transcription(modelId: .init(rawValue: modelId)) }
    public func callAsFunction(_ modelId: AssemblyAITranscriptionModelId) -> Models { .init(transcription: transcription(modelId: modelId)) }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        throw NoSuchModelError(modelId: "unknown", modelType: .languageModel, message: "AssemblyAI does not provide language models")
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel) }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
}
public func createAssemblyAI(settings: AssemblyAIProviderSettings = .init()) -> AssemblyAIProvider { .init(settings: settings) }
public let assemblyai = createAssemblyAI()
