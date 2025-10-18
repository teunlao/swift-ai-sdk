import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var organization: String?
    public var project: String?
    public var headers: [String: String]?
    public var name: String?
    public var fetch: FetchFunction?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        organization: String? = nil,
        project: String? = nil,
        headers: [String: String]? = nil,
        name: String? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.organization = organization
        self.project = project
        self.headers = headers
        self.name = name
        self.fetch = fetch
    }
}

public final class OpenAIProvider: ProviderV3 {
    private let responsesFactory: @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel
    private let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel
    public let tools: OpenAITools

    init(
        responses: @escaping @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel,
        embeddings: @escaping @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel,
        tools: OpenAITools
    ) {
        self.responsesFactory = responses
        self.embeddingFactory = embeddings
        self.tools = tools
    }

    public func languageModel(modelId: String) -> any LanguageModelV3 {
        responsesFactory(OpenAIResponsesModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) -> any EmbeddingModelV3<String> {
        embeddingFactory(OpenAIEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) -> any ImageModelV3 {
        fatalError("OpenAI image models not yet implemented")
    }

    public func transcriptionModel(modelId: String) -> any TranscriptionModelV3 {
        fatalError("OpenAI transcription models not yet implemented")
    }

    public func speechModel(modelId: String) -> any SpeechModelV3 {
        fatalError("OpenAI speech models not yet implemented")
    }

    public func responses(modelId: OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel {
        responsesFactory(modelId)
    }
}

public func createOpenAIProvider(settings: OpenAIProviderSettings = .init()) -> OpenAIProvider {
    let baseURL = withoutTrailingSlash(
        loadOptionalSetting(
            settingValue: settings.baseURL,
            environmentVariableName: "OPENAI_BASE_URL"
        )
    ) ?? "https://api.openai.com/v1"

    let providerName = settings.name ?? "openai"
    let apiKey: String
    do {
        apiKey = try loadAPIKey(
            apiKey: settings.apiKey,
            environmentVariableName: "OPENAI_API_KEY",
            description: "OpenAI"
        )
    } catch {
        fatalError("OpenAI API key is missing: \(error)")
    }

    let headersClosure: @Sendable () -> [String: String?] = {
        let baseHeaders: [String: String?] = [
            "Authorization": "Bearer \(apiKey)",
            "OpenAI-Organization": settings.organization,
            "OpenAI-Project": settings.project
        ]

        let merged = combineHeaders(baseHeaders, settings.headers?.mapValues { Optional($0) })
        let userAgentHeaders = withUserAgentSuffix(merged, "ai-sdk/openai/\(OPENAI_VERSION)")
        return userAgentHeaders.mapValues { Optional($0) }
    }

    func makeConfig(providerSuffix: String, fileIdPrefixes: [String]? = nil) -> OpenAIConfig {
        OpenAIConfig(
            provider: "\(providerName).\(providerSuffix)",
            url: { options in "\(baseURL)\(options.path)" },
            headers: headersClosure,
            fetch: settings.fetch,
            fileIdPrefixes: fileIdPrefixes
        )
    }

    let responsesConfig = makeConfig(providerSuffix: "responses", fileIdPrefixes: ["file-"])
    let embeddingConfig = makeConfig(providerSuffix: "embedding")

    let responsesFactory: @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel = { modelId in
        OpenAIResponsesLanguageModel(
            modelId: modelId,
            config: responsesConfig
        )
    }

    let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel = { modelId in
        OpenAIEmbeddingModel(
            modelId: modelId,
            config: embeddingConfig
        )
    }

    return OpenAIProvider(
        responses: responsesFactory,
        embeddings: embeddingFactory,
        tools: openaiTools
    )
}
