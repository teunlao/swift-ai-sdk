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
    private let chatFactory: @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel
    private let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel
    private let imageFactory: @Sendable (OpenAIImageModelId) -> OpenAIImageModel
    private let completionFactory: @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel
    private let transcriptionFactory: @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModel
    private let speechFactory: @Sendable (OpenAISpeechModelId) -> OpenAISpeechModel
    public let tools: OpenAITools

    init(
        responses: @escaping @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel,
        chat: @escaping @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel,
        embeddings: @escaping @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel,
        images: @escaping @Sendable (OpenAIImageModelId) -> OpenAIImageModel,
        completions: @escaping @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel,
        transcriptions: @escaping @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModel,
        speeches: @escaping @Sendable (OpenAISpeechModelId) -> OpenAISpeechModel,
        tools: OpenAITools
    ) {
        self.responsesFactory = responses
        self.chatFactory = chat
        self.embeddingFactory = embeddings
        self.imageFactory = images
        self.completionFactory = completions
        self.transcriptionFactory = transcriptions
        self.speechFactory = speeches
        self.tools = tools
    }

    public func languageModel(modelId: String) -> any LanguageModelV3 {
        responsesFactory(OpenAIResponsesModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) -> any LanguageModelV3 {
        chatFactory(OpenAIChatModelId(rawValue: modelId))
    }

    public func completionModel(modelId: String) -> any LanguageModelV3 {
        completionFactory(OpenAICompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) -> any EmbeddingModelV3<String> {
        embeddingFactory(OpenAIEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) -> any ImageModelV3 {
        imageFactory(OpenAIImageModelId(rawValue: modelId))
    }

    public func transcriptionModel(modelId: String) -> any TranscriptionModelV3 {
        transcriptionFactory(OpenAITranscriptionModelId(rawValue: modelId))
    }

    public func speechModel(modelId: String) -> any SpeechModelV3 {
        speechFactory(OpenAISpeechModelId(rawValue: modelId))
    }

    public func responses(modelId: OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel {
        responsesFactory(modelId)
    }

    public func chat(modelId: OpenAIChatModelId) -> OpenAIChatLanguageModel {
        chatFactory(modelId)
    }

    public func transcription(modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func speech(modelId: OpenAISpeechModelId) -> OpenAISpeechModel {
        speechFactory(modelId)
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

    let headersClosure: @Sendable () -> [String: String?] = {
        // Lazily load API key on first request to mirror upstream behavior.
        // If missing, fail with a clear error message.
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
    let chatConfig = makeConfig(providerSuffix: "chat")
    let embeddingConfig = makeConfig(providerSuffix: "embedding")
    let imageConfig = makeConfig(providerSuffix: "image")
    let completionConfig = makeConfig(providerSuffix: "completion")
    let transcriptionConfig = makeConfig(providerSuffix: "transcription")
    let speechConfig = makeConfig(providerSuffix: "speech")

    let responsesFactory: @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel = { modelId in
        OpenAIResponsesLanguageModel(
            modelId: modelId,
            config: responsesConfig
        )
    }

    let chatFactory: @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel = { modelId in
        OpenAIChatLanguageModel(
            modelId: modelId,
            config: chatConfig
        )
    }

    let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel = { modelId in
        OpenAIEmbeddingModel(
            modelId: modelId,
            config: embeddingConfig
        )
    }

    let imageFactory: @Sendable (OpenAIImageModelId) -> OpenAIImageModel = { modelId in
        OpenAIImageModel(
            modelId: modelId,
            config: imageConfig
        )
    }

    let completionFactory: @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel = { modelId in
        OpenAICompletionLanguageModel(
            modelId: modelId,
            config: completionConfig
        )
    }

    let transcriptionFactory: @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModel = { modelId in
        OpenAITranscriptionModel(
            modelId: modelId,
            config: transcriptionConfig
        )
    }

    let speechFactory: @Sendable (OpenAISpeechModelId) -> OpenAISpeechModel = { modelId in
        OpenAISpeechModel(
            modelId: modelId,
            config: speechConfig
        )
    }

    return OpenAIProvider(
        responses: responsesFactory,
        chat: chatFactory,
        embeddings: embeddingFactory,
        images: imageFactory,
        completions: completionFactory,
        transcriptions: transcriptionFactory,
        speeches: speechFactory,
        tools: openaiTools
    )
}

// MARK: - Provider call/aliases (parity with TS facade)

public extension OpenAIProvider {
    /// Allow calling the provider instance like a function: `openai("gpt-5")`.
    func callAsFunction(_ modelId: String) -> any LanguageModelV3 {
        languageModel(modelId: modelId)
    }

    /// Typed alias for embeddings to mirror TS facade naming.
    func embedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    /// Typed alias for image models.
    func image(_ modelId: OpenAIImageModelId) -> OpenAIImageModel {
        imageFactory(modelId)
    }

    /// Typed alias for completion models.
    func completion(_ modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModel {
        completionFactory(modelId)
    }

    /// Alias for `textEmbeddingModel` to match upstream naming.
    func textEmbedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    /// Typed alias for transcription models (not just String-based).
    func transcriptionModel(_ modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    /// Typed alias for speech models (not just String-based).
    func speechModel(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModel {
        speechFactory(modelId)
    }
}

// MARK: - Default provider instance (parity with TS `export const openai = createOpenAI()`)

public let openai: OpenAIProvider = createOpenAIProvider()
