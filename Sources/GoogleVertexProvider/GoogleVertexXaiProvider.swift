import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

public typealias GoogleVertexXaiModelId = String

public final class GoogleVertexXaiProvider: ProviderV4 {
    private let config: VertexPartnerConfig
    init(settings: GoogleVertexXaiProviderSettings) { config = .init(settings) }

    public func callAsFunction(_ modelId: String) -> OpenAICompatibleChatLanguageModelV4 { chatModel(modelId: modelId) }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 { chatModel(modelId: modelId) }
    public func chatModel(modelId: String) -> OpenAICompatibleChatLanguageModelV4 {
        let config = self.config
        return .init(modelId: .init(rawValue: modelId), config: .init(
            provider: "googleVertex.xai.chat", headers: vertexCompatibleHeaders,
            url: { "\(try config.baseURL(.xai))\($0.path)" }, fetch: config.fetch(),
            includeUsage: true, supportsStructuredOutputs: true,
            supportedUrls: { ["image/*": [try NSRegularExpression(pattern: "^https?://.*$")]] },
            transformRequestBody: { body in
                var result = body
                result.removeValue(forKey: "reasoning_effort")
                return result
            },
            convertUsage: { usage in
                guard let usage else { return .init() }
                let prompt = usage.promptTokens ?? 0
                let completion = usage.completionTokens ?? 0
                let cached = usage.promptTokensDetails?.cachedTokens ?? 0
                let reasoning = usage.completionTokensDetails?.reasoningTokens ?? 0
                return .init(inputTokens: .init(total: prompt, noCache: prompt - cached, cacheRead: cached),
                             outputTokens: .init(total: completion + reasoning, text: completion, reasoning: reasoning), raw: usage.raw)
            }
        ))
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel) }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
}

public func createGoogleVertexXai(settings: GoogleVertexXaiProviderSettings = .init()) -> GoogleVertexXaiProvider {
    .init(settings: settings)
}
public let googleVertexXai = createGoogleVertexXai()
