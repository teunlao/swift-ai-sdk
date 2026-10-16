import AISDKProvider
import OpenAIProvider

enum OpenAIPlaygroundFactory {
    static func makeLanguageModel(
        modelId: String,
        configuration: PlaygroundConfiguration,
        logger: PlaygroundLogger
    ) throws -> any LanguageModelV4 {
        guard let apiKey = configuration.keys.openAI, !apiKey.isEmpty else {
            throw ContextError.missingAPIKey(provider: "openai")
        }
        Task { await logger.verbose("Using openai provider (model=\(modelId))") }
        return try createOpenAI(settings: .init(
            baseURL: configuration.baseURLOverrides["openai"]?.absoluteString,
            apiKey: apiKey,
            organization: configuration.environment["OPENAI_ORGANIZATION"],
            project: configuration.environment["OPENAI_PROJECT"]
        )).languageModel(modelId: modelId)
    }
}
