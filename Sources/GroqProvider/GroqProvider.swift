import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GroqProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class GroqProvider: ProviderV3 {
    private let languageModelFactory: @Sendable (GroqChatModelId) -> GroqChatLanguageModel
    private let transcriptionModelFactory: @Sendable (GroqTranscriptionModelId) -> GroqTranscriptionModel
    public let tools: GroqTools

    init(
        languageModelFactory: @escaping @Sendable (GroqChatModelId) -> GroqChatLanguageModel,
        transcriptionModelFactory: @escaping @Sendable (GroqTranscriptionModelId) -> GroqTranscriptionModel,
        tools: GroqTools
    ) {
        self.languageModelFactory = languageModelFactory
        self.transcriptionModelFactory = transcriptionModelFactory
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageModelFactory(GroqChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        languageModelFactory(GroqChatModelId(rawValue: modelId))
    }

    public func chat(modelId: GroqChatModelId) -> GroqChatLanguageModel {
        languageModelFactory(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func transcription(modelId: GroqTranscriptionModelId) -> GroqTranscriptionModel {
        transcriptionModelFactory(modelId)
    }

    public func transcriptionModel(modelId: String) throws -> any TranscriptionModelV3 {
        transcription(modelId: GroqTranscriptionModelId(rawValue: modelId))
    }
}


public func createGroqProvider(settings: GroqProviderSettings = .init()) -> GroqProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.groq.com/openai/v1"

    let headersClosure: @Sendable () -> [String: String?] = {
        var baseHeaders: [String: String?] = [:]
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "GROQ_API_KEY",
                description: "Groq"
            )
        } catch {
            fatalError("Groq API key is missing: \(error)")
        }
        baseHeaders["Authorization"] = "Bearer \(apiKey)"
        if let headers = settings.headers {
            for (key, value) in headers {
                baseHeaders[key] = value
            }
        }
        let withUA = withUserAgentSuffix(baseHeaders, "ai-sdk/groq/\(GROQ_PROVIDER_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let languageModelFactory: @Sendable (GroqChatModelId) -> GroqChatLanguageModel = { modelId in
        GroqChatLanguageModel(
            modelId: modelId,
            config: GroqChatLanguageModel.Config(
                provider: "groq.chat",
                url: { options in "\(baseURL)\(options.path)" },
                headers: headersClosure,
                fetch: settings.fetch,
                generateId: generateID
            )
        )
    }

    let transcriptionFactory: @Sendable (GroqTranscriptionModelId) -> GroqTranscriptionModel = { modelId in
        GroqTranscriptionModel(
            modelId: modelId,
            config: GroqTranscriptionModel.Config(
                provider: "groq.transcription",
                url: { options in "\(baseURL)\(options.path)" },
                headers: headersClosure,
                fetch: settings.fetch,
                currentDate: { Date() }
            )
        )
    }

    return GroqProvider(
        languageModelFactory: languageModelFactory,
        transcriptionModelFactory: transcriptionFactory,
        tools: groqTools
    )
}

public let groq = createGroqProvider()
