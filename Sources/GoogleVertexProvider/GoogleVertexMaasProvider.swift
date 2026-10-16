import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

public typealias GoogleVertexMaasModelId = String

public final class GoogleVertexMaasProvider: ProviderV4 {
    private let config: VertexPartnerConfig
    init(settings: GoogleVertexMaasProviderSettings) { config = .init(settings) }

    public func callAsFunction(_ modelId: String) -> OpenAICompatibleChatLanguageModelV4 { chatModel(modelId: modelId) }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 { chatModel(modelId: modelId) }
    public func chatModel(modelId: String) -> OpenAICompatibleChatLanguageModelV4 {
        let config = self.config
        return .init(modelId: .init(rawValue: modelId), config: .init(
            provider: "vertex.maas.chat", headers: vertexCompatibleHeaders,
            url: { "\(try config.baseURL(.maas))\($0.path)" }, fetch: config.fetch(),
            transformRequestBody: { body in
                var result = body
                if case .string(let model) = body["model"],
                   ["meta/llama-4-maverick-17b-128e-instruct-maas", "meta/llama-4-scout-17b-16e-instruct-maas"].contains(model),
                   body["max_tokens"] == nil {
                    result["max_tokens"] = .number(8192)
                }
                return result
            }
        ))
    }
    public func completionModel(modelId: String) -> OpenAICompatibleCompletionLanguageModelV4 {
        let config = self.config
        return .init(modelId: .init(rawValue: modelId), config: .init(
            provider: "vertex.maas.completion", headers: vertexCompatibleHeaders,
            url: { "\(try config.baseURL(.maas))\($0.path)" }, fetch: config.fetch()
        ))
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        let config = self.config
        return OpenAICompatibleEmbeddingModelV4(modelId: .init(rawValue: modelId), config: .init(
            provider: "vertex.maas.embedding", url: { "\(try config.baseURL(.maas))\($0.path)" },
            headers: vertexCompatibleHeaders, fetch: config.fetch()
        ))
    }
    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        let config = self.config
        return OpenAICompatibleImageModelV4(modelId: .init(rawValue: modelId), config: .init(
            provider: "vertex.maas.image", headers: vertexCompatibleHeaders,
            url: { "\(try config.baseURL(.maas))\($0.path)" }, fetch: config.fetch()
        ))
    }
}

@Sendable func vertexCompatibleHeaders() -> [String: String] {
    withUserAgentSuffix([:], "ai-sdk-openai-compatible/\(OPENAI_COMPATIBLE_VERSION)")
}

public func createGoogleVertexMaas(settings: GoogleVertexMaasProviderSettings = .init()) -> GoogleVertexMaasProvider {
    .init(settings: settings)
}
public let googleVertexMaas = createGoogleVertexMaas()
