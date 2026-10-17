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
    public var webSocket: OpenAIWebSocketFactory?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        organization: String? = nil,
        project: String? = nil,
        headers: [String: String]? = nil,
        name: String? = nil,
        fetch: FetchFunction? = nil,
        webSocket: OpenAIWebSocketFactory? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.organization = organization
        self.project = project
        self.headers = headers
        self.name = name
        self.fetch = fetch
        self.webSocket = webSocket
    }
}

public final class OpenAIProvider: ProviderV4 {
    private let responsesFactory: @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel
    private let chatFactory: @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel
    private let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel
    private let imageFactory: @Sendable (OpenAIImageModelId) -> OpenAIImageModelV4
    private let completionFactory: @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel
    private let transcriptionFactory: @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4
    private let speechFactory: @Sendable (OpenAISpeechModelId) -> OpenAISpeechModelV4
    private let filesFactory: @Sendable () -> any FilesV4
    private let skillsFactory: @Sendable () -> any SkillsV4
    public let experimental_realtime: any RealtimeFactoryV4
    public let tools: OpenAITools
    public let options: OpenAIOptionsFacade

    init(
        responses: @escaping @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel,
        chat: @escaping @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel,
        embeddings: @escaping @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel,
        images: @escaping @Sendable (OpenAIImageModelId) -> OpenAIImageModelV4,
        completions: @escaping @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel,
        transcriptions: @escaping @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4,
        speeches: @escaping @Sendable (OpenAISpeechModelId) -> OpenAISpeechModelV4,
        files: @escaping @Sendable () -> any FilesV4,
        skills: @escaping @Sendable () -> any SkillsV4,
        experimentalRealtime: any RealtimeFactoryV4,
        tools: OpenAITools,
        options: OpenAIOptionsFacade
    ) {
        responsesFactory = responses
        chatFactory = chat
        embeddingFactory = embeddings
        imageFactory = images
        completionFactory = completions
        transcriptionFactory = transcriptions
        speechFactory = speeches
        filesFactory = files
        skillsFactory = skills
        experimental_realtime = experimentalRealtime
        self.tools = tools
        self.options = options
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        responsesFactory(OpenAIResponsesModelId(rawValue: modelId))
    }

    public func languageModel(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func responses(modelId: OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel {
        responsesFactory(modelId)
    }

    public func responses(_ modelId: String) -> OpenAIResponsesLanguageModel {
        responses(modelId: OpenAIResponsesModelId(rawValue: modelId))
    }

    public func chat(modelId: OpenAIChatModelId) -> OpenAIChatLanguageModel {
        chatFactory(modelId)
    }

    public func chat(_ modelId: String) -> OpenAIChatLanguageModel {
        chat(modelId: OpenAIChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV4 {
        chat(modelId)
    }

    public func chatModel(_ modelId: OpenAIChatModelId) -> OpenAIChatLanguageModel {
        chat(modelId: modelId)
    }

    public func completion(modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModel {
        completionFactory(modelId)
    }

    public func completion(_ modelId: String) -> OpenAICompletionLanguageModel {
        completion(modelId: OpenAICompletionModelId(rawValue: modelId))
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV4 {
        completion(modelId)
    }

    public func completionModel(_ modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModel {
        completion(modelId: modelId)
    }

    public func embedding(modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func embedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embedding(modelId: modelId)
    }

    public func embedding(_ modelId: String) -> OpenAIEmbeddingModel {
        embedding(modelId: OpenAIEmbeddingModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embedding(modelId)
    }

    public func embeddingModel(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embedding(modelId: modelId)
    }

    public func textEmbedding(modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embedding(modelId: modelId)
    }

    public func textEmbedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embedding(modelId: modelId)
    }

    public func textEmbedding(_ modelId: String) -> OpenAIEmbeddingModel {
        embedding(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embedding(modelId)
    }

    public func textEmbeddingModel(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embedding(modelId: modelId)
    }

    public func image(modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        imageFactory(modelId)
    }

    public func image(_ modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        image(modelId: modelId)
    }

    public func image(_ modelId: String) -> OpenAIImageModelV4 {
        image(modelId: OpenAIImageModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        image(modelId)
    }

    public func imageModel(_ modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        image(modelId: modelId)
    }

    public func transcription(modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4 {
        transcriptionFactory(modelId)
    }

    public func transcription(_ modelId: String) -> OpenAITranscriptionModelV4 {
        transcription(modelId: OpenAITranscriptionModelId(rawValue: modelId))
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        transcription(modelId)
    }

    public func transcriptionModel(_ modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4 {
        transcription(modelId: modelId)
    }

    public func speech(modelId: OpenAISpeechModelId) -> OpenAISpeechModelV4 {
        speechFactory(modelId)
    }

    public func speech(_ modelId: String) -> OpenAISpeechModelV4 {
        speech(modelId: OpenAISpeechModelId(rawValue: modelId))
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        speech(modelId)
    }

    public func speechModel(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModelV4 {
        speech(modelId: modelId)
    }

    public func files() throws -> (any FilesV4)? { filesFactory() }
    public func skills() throws -> (any SkillsV4)? { skillsFactory() }
}

public func createOpenAIProvider(settings: OpenAIProviderSettings = .init()) throws -> OpenAIProvider {
    let baseURL = withoutTrailingSlash(
        try validateBaseURL(loadOptionalSetting(settingValue: settings.baseURL, environmentVariableName: "OPENAI_BASE_URL"))
    ) ?? "https://api.openai.com/v1"
    let providerName = settings.name ?? "openai"
    let headers: @Sendable () throws -> [String: String?] = {
        let apiKey = try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "OPENAI_API_KEY", description: "OpenAI")
        return withUserAgentSuffix(combineHeaders([
            "Authorization": "Bearer \(apiKey)",
            "OpenAI-Organization": settings.organization,
            "OpenAI-Project": settings.project
        ], settings.headers?.mapValues { Optional($0) }), "ai-sdk-openai/\(OPENAI_VERSION)").mapValues { Optional($0) }
    }
    func config(_ suffix: String, fileIdPrefixes: [String]? = nil) -> OpenAIConfig {
        OpenAIConfig(
            provider: "\(providerName).\(suffix)",
            baseURL: suffix == "responses" ? baseURL : nil,
            url: { "\(baseURL)\($0.path)" },
            headers: headers,
            fetch: settings.fetch,
            webSocket: settings.webSocket,
            fileIdPrefixes: fileIdPrefixes
        )
    }
    let responsesConfig = config("responses", fileIdPrefixes: ["file-"])
    let chatConfig = config("chat")
    let embeddingConfig = config("embedding")
    let imageConfig = config("image")
    let completionConfig = config("completion")
    let transcriptionConfig = config("transcription")
    let speechConfig = config("speech")
    return OpenAIProvider(
        responses: { OpenAIResponsesLanguageModel(modelId: $0, config: responsesConfig) },
        chat: { OpenAIChatLanguageModel(modelId: $0, config: chatConfig) },
        embeddings: { OpenAIEmbeddingModel(modelId: $0, config: embeddingConfig) },
        images: { OpenAIImageModelV4(modelId: $0, config: imageConfig) },
        completions: { OpenAICompletionLanguageModel(modelId: $0, config: completionConfig) },
        transcriptions: { OpenAITranscriptionModelV4(modelId: $0, config: transcriptionConfig) },
        speeches: { OpenAISpeechModelV4(modelId: $0, config: speechConfig) },
        files: { OpenAIFiles(config: .init(provider: "\(providerName).files", baseURL: baseURL, headers: headers, fetch: settings.fetch)) },
        skills: { OpenAISkills(config: .init(provider: "\(providerName).skills", url: { "\(baseURL)\($0)" }, headers: headers, fetch: settings.fetch)) },
        experimentalRealtime: OpenAIRealtimeFactory(config: .init(provider: "\(providerName).realtime", baseURL: baseURL, headers: headers, fetch: settings.fetch)),
        tools: openaiTools,
        options: OpenAIOptionsFacade()
    )
}

public func createOpenAI(settings: OpenAIProviderSettings = .init()) throws -> OpenAIProvider {
    try createOpenAIProvider(settings: settings)
}

public let openai: OpenAIProvider = try! createOpenAI()
