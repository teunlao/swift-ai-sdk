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

public final class OpenAIProvider: ProviderV3, FilesProvider, SkillsProvider {
    private let responsesFactory: @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel
    private let chatFactory: @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel
    private let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel
    private let imageFactory: @Sendable (OpenAIImageModelId) -> OpenAIImageModel
    private let completionFactory: @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel
    private let transcriptionFactory: @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModel
    private let speechFactory: @Sendable (OpenAISpeechModelId) -> OpenAISpeechModel
    private let filesFactory: @Sendable () -> any FilesV4
    private let skillsFactory: @Sendable () -> any SkillsV4
    public let experimental_realtime: any RealtimeFactoryV4
    public let tools: OpenAITools
    public let options: OpenAIOptionsFacade

    init(
        responses: @escaping @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel,
        chat: @escaping @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel,
        embeddings: @escaping @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel,
        images: @escaping @Sendable (OpenAIImageModelId) -> OpenAIImageModel,
        completions: @escaping @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel,
        transcriptions: @escaping @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModel,
        speeches: @escaping @Sendable (OpenAISpeechModelId) -> OpenAISpeechModel,
        files: @escaping @Sendable () -> any FilesV4,
        skills: @escaping @Sendable () -> any SkillsV4,
        experimentalRealtime: any RealtimeFactoryV4,
        tools: OpenAITools,
        options: OpenAIOptionsFacade
    ) {
        self.responsesFactory = responses
        self.chatFactory = chat
        self.embeddingFactory = embeddings
        self.imageFactory = images
        self.completionFactory = completions
        self.transcriptionFactory = transcriptions
        self.speechFactory = speeches
        self.filesFactory = files
        self.skillsFactory = skills
        self.experimental_realtime = experimentalRealtime
        self.tools = tools
        self.options = options
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        responsesFactory(OpenAIResponsesModelId(rawValue: modelId))
    }

    public func languageModel(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(OpenAIChatModelId(rawValue: modelId))
    }

    public func chatModel(_ modelId: String) throws -> any LanguageModelV3 {
        try chatModel(modelId: modelId)
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV3 {
        completionFactory(OpenAICompletionModelId(rawValue: modelId))
    }

    public func completionModel(_ modelId: String) throws -> any LanguageModelV3 {
        try completionModel(modelId: modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(OpenAIEmbeddingModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(_ modelId: String) throws -> any EmbeddingModelV3<String> {
        try textEmbeddingModel(modelId: modelId)
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        try textEmbeddingModel(modelId: modelId)
    }

    public func embeddingModel(_ modelId: String) throws -> any EmbeddingModelV3<String> {
        try embeddingModel(modelId: modelId)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(OpenAIImageModelId(rawValue: modelId))
    }

    public func imageModel(_ modelId: String) throws -> any ImageModelV3 {
        try imageModel(modelId: modelId)
    }

    public func transcriptionModel(modelId: String) throws -> any TranscriptionModelV3 {
        transcriptionFactory(OpenAITranscriptionModelId(rawValue: modelId))
    }

    public func transcriptionModel(_ modelId: String) throws -> any TranscriptionModelV3 {
        try transcriptionModel(modelId: modelId)
    }

    public func speechModel(modelId: String) throws -> any SpeechModelV3 {
        speechFactory(OpenAISpeechModelId(rawValue: modelId))
    }

    public func speechModel(_ modelId: String) throws -> any SpeechModelV3 {
        try speechModel(modelId: modelId)
    }

    public func responses(modelId: OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel {
        responsesFactory(modelId)
    }

    public func responses(_ modelId: String) -> OpenAIResponsesLanguageModel {
        responsesFactory(OpenAIResponsesModelId(rawValue: modelId))
    }

    public func chat(modelId: OpenAIChatModelId) -> OpenAIChatLanguageModel {
        chatFactory(modelId)
    }

    public func chat(_ modelId: String) -> OpenAIChatLanguageModel {
        chatFactory(OpenAIChatModelId(rawValue: modelId))
    }

    public func transcription(modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func transcription(_ modelId: String) -> OpenAITranscriptionModel {
        transcriptionFactory(OpenAITranscriptionModelId(rawValue: modelId))
    }

    public func speech(modelId: OpenAISpeechModelId) -> OpenAISpeechModel {
        speechFactory(modelId)
    }

    public func speech(_ modelId: String) -> OpenAISpeechModel {
        speechFactory(OpenAISpeechModelId(rawValue: modelId))
    }

    public func files() -> any FilesV4 {
        filesFactory()
    }

    public func skills() -> any SkillsV4 {
        skillsFactory()
    }
}

public func createOpenAIProvider(settings: OpenAIProviderSettings = .init()) throws -> OpenAIProvider {
    let baseURL = withoutTrailingSlash(
        try validateBaseURL(
            loadOptionalSetting(
                settingValue: settings.baseURL,
                environmentVariableName: "OPENAI_BASE_URL"
            )
        )
    ) ?? "https://api.openai.com/v1"

    let providerName = settings.name ?? "openai"

    let headersClosure: @Sendable () throws -> [String: String?] = {
        // Lazily load API key on first request to mirror upstream behavior.
        let apiKey = try loadAPIKey(
            apiKey: settings.apiKey,
            environmentVariableName: "OPENAI_API_KEY",
            description: "OpenAI"
        )

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
            webSocket: settings.webSocket,
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

    let filesFactory: @Sendable () -> any FilesV4 = {
        OpenAIFiles(config: .init(
            provider: "\(providerName).files",
            baseURL: baseURL,
            headers: headersClosure,
            fetch: settings.fetch
        ))
    }

    let skillsFactory: @Sendable () -> any SkillsV4 = {
        OpenAISkills(config: .init(
            provider: "\(providerName).skills",
            url: { path in "\(baseURL)\(path)" },
            headers: headersClosure,
            fetch: settings.fetch
        ))
    }

    let realtimeFactory = OpenAIRealtimeFactory(config: .init(
        provider: "\(providerName).realtime",
        baseURL: baseURL,
        headers: headersClosure,
        fetch: settings.fetch
    ))

    return OpenAIProvider(
        responses: responsesFactory,
        chat: chatFactory,
        embeddings: embeddingFactory,
        images: imageFactory,
        completions: completionFactory,
        transcriptions: transcriptionFactory,
        speeches: speechFactory,
        files: filesFactory,
        skills: skillsFactory,
        experimentalRealtime: realtimeFactory,
        tools: openaiTools,
        options: OpenAIOptionsFacade()
    )
}

// MARK: - Provider call/aliases (parity with TS facade)

public extension OpenAIProvider {
    /// Allow calling the provider instance like a function: `openai("gpt-5")`.
    func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    /// Typed alias for embeddings to mirror TS facade naming.
    func embedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    /// Native V4 embedding model factory used by the Provider V4 facade.
    func embeddingV4(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModelV4 {
        embeddingFactory(modelId).asV4()
    }

    /// Typed alias to mirror upstream `embeddingModel(...)`.
    func embeddingModel(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    /// Typed alias for image models.
    func image(_ modelId: OpenAIImageModelId) -> OpenAIImageModel {
        imageFactory(modelId)
    }

    /// Native V4 image model factory used by the Provider V4 facade.
    func imageV4(_ modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        imageFactory(modelId).asV4()
    }

    /// Native V4 image model alias used by the Provider V4 facade.
    func imageModelV4(_ modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        imageV4(modelId)
    }

    /// Typed alias for completion models.
    func completion(_ modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModel {
        completionFactory(modelId)
    }

    /// Native V4 completion model factory used by the Provider V4 facade.
    func completionV4(_ modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModelV4 {
        completionFactory(modelId).asV4()
    }

    /// Native V4 completion model alias used by the Provider V4 facade.
    func completionModelV4(_ modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModelV4 {
        completionV4(modelId)
    }

    /// Native V4 responses model factory used by the Provider V4 facade.
    func responsesV4(_ modelId: OpenAIResponsesModelId) -> OpenAIResponsesLanguageModelV4 {
        responsesFactory(modelId).asV4()
    }

    /// Native V4 responses model alias used by the Provider V4 facade.
    func responsesModelV4(_ modelId: OpenAIResponsesModelId) -> OpenAIResponsesLanguageModelV4 {
        responsesV4(modelId)
    }

    /// Native V4 chat model factory used by the Provider V4 facade.
    func chatV4(_ modelId: OpenAIChatModelId) -> OpenAIChatLanguageModelV4 {
        chatFactory(modelId).asV4()
    }

    /// Native V4 chat model alias used by the Provider V4 facade.
    func chatModelV4(_ modelId: OpenAIChatModelId) -> OpenAIChatLanguageModelV4 {
        chatV4(modelId)
    }

    /// Alias for `textEmbeddingModel` to match upstream naming.
    func textEmbedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    /// Native V4 text embedding alias used by the Provider V4 facade.
    func textEmbeddingV4(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModelV4 {
        embeddingV4(modelId)
    }

    /// Typed alias for transcription models (not just String-based).
    func transcriptionModel(_ modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    /// Native V4 transcription model factory used by the Provider V4 facade.
    func transcriptionV4(_ modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4 {
        transcriptionFactory(modelId).asV4()
    }

    /// Native V4 transcription model alias used by the Provider V4 facade.
    func transcriptionModelV4(_ modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4 {
        transcriptionV4(modelId)
    }

    /// Typed alias for speech models (not just String-based).
    func speechModel(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModel {
        speechFactory(modelId)
    }

    /// Native V4 speech alias used by the Provider V4 facade.
    func speechV4(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModelV4 {
        speechFactory(modelId).asV4()
    }

    /// Convenience alias to match facade style: `openai.speech("tts-1")`.
    func speech(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModel {
        speechFactory(modelId)
    }

    /// Native V4 speech model alias used by the Provider V4 facade.
    func speechModelV4(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModelV4 {
        speechV4(modelId)
    }
}

// MARK: - Default provider instance (parity with TS `export const openai = createOpenAI()`)

public let openai: OpenAIProviderV4 = try! createOpenAI()
