import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct HumeProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey; self.headers = headers; self.fetch = fetch
    }
}
public final class HumeProvider: ProviderV4 {
    public struct Models: Sendable { public let speech: HumeSpeechModel }
    private let config: HumeConfig
    init(settings: HumeProviderSettings) {
        config = .init(provider: "hume.speech", headers: {
            let headers = combineHeaders(
                ["X-Hume-Api-Key": try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "HUME_API_KEY", description: "Hume")], settings.headers?.mapValues(Optional.some)
            )
            return withUserAgentSuffix(headers, "ai-sdk-hume/\(HUME_VERSION)").mapValues(Optional.some)
        }, fetch: settings.fetch)
    }
    public func speech() -> HumeSpeechModel { .init(config: config) }
    public func speechModel(modelId: String) -> (any SpeechModelV4)? { speech() }
    public func callAsFunction() -> Models { .init(speech: speech()) }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .languageModel, message: "Hume does not provide language models") }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel, message: "Hume does not provide embedding models") }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel, message: "Hume does not provide image models") }
}
public func createHume(settings: HumeProviderSettings = .init()) -> HumeProvider { .init(settings: settings) }
public let hume = createHume()
