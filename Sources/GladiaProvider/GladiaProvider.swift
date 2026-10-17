import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GladiaProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey; self.headers = headers; self.fetch = fetch
    }
}
public final class GladiaProvider: ProviderV4 {
    public struct Models: Sendable { public let transcription: GladiaTranscriptionModel }
    private let config: GladiaConfig
    init(settings: GladiaProviderSettings) {
        config = .init(provider: "gladia.transcription", headers: {
            let headers = combineHeaders(
                ["x-gladia-key": try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "GLADIA_API_KEY", description: "Gladia")], settings.headers?.mapValues(Optional.some)
            )
            return withUserAgentSuffix(headers, "ai-sdk-gladia/\(GLADIA_VERSION)").mapValues(Optional.some)
        }, fetch: settings.fetch)
    }
    public func transcription() -> GladiaTranscriptionModel { .init(config: config) }
    public func callAsFunction() -> Models { .init(transcription: transcription()) }
    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV4)? { transcription() }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .languageModel, message: "Gladia does not provide language models") }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel, message: "Gladia does not provide embedding models") }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel, message: "Gladia does not provide image models") }
}
public func createGladia(settings: GladiaProviderSettings = .init()) -> GladiaProvider { .init(settings: settings) }
public let gladia = createGladia()
