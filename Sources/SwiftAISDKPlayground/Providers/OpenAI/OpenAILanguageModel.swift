import Foundation
import AISDKProvider
import OpenAIProvider

/// Factory for creating OpenAI language models in the playground.
///
/// Demonstrates the legacy V3 OpenAI provider API used by this playground path.
enum OpenAIPlaygroundFactory {
    static func makeLanguageModel(
        modelId: String,
        configuration: PlaygroundConfiguration,
        logger: PlaygroundLogger
    ) throws -> any LanguageModelV3 {
        guard let apiKey = configuration.keys.openAI, !apiKey.isEmpty else {
            throw ContextError.missingAPIKey(provider: "openai")
        }

        let baseURL = configuration.baseURLOverrides["openai"]?.absoluteString
        let organization = configuration.environment["OPENAI_ORGANIZATION"]
        let project = configuration.environment["OPENAI_PROJECT"]

        Task {
            await logger.verbose("Using openai provider (model=\(modelId))")
            await logger.verbose("Using legacy createOpenAIProvider because this playground path expects LanguageModelV3")
        }

        // This playground path is still V3-oriented; the package default `openai`
        // is V4 for upstream parity.
        if baseURL == nil && organization == nil && project == nil {
            Task {
                await logger.verbose("Using createOpenAIProvider().languageModel(\"\(modelId)\")")
            }
            return try createOpenAIProvider(
                settings: OpenAIProviderSettings(apiKey: apiKey)
            ).languageModel(modelId: modelId)
        }

        // Custom provider when settings are provided
        let settings = OpenAIProviderSettings(
            baseURL: baseURL,
            apiKey: apiKey,
            organization: organization,
            project: project
        )

        let provider = createOpenAIProvider(settings: settings)

        // Demonstrate different API methods
        Task {
            await logger.verbose("✅ Created custom provider with settings")
            await logger.verbose("   Available methods:")
            await logger.verbose("   - provider(\"\(modelId)\")  // callAsFunction")
            await logger.verbose("   - provider.languageModel(\"\(modelId)\")")
            await logger.verbose("   - provider.chat(.gpt4o)")
            await logger.verbose("   - provider.completion(.gpt35TurboInstruct)")
            await logger.verbose("   - provider.embedding(.textEmbedding3Small)")
            await logger.verbose("   - provider.textEmbedding(.textEmbedding3Small)")
            await logger.verbose("   - provider.image(.dall_e_3)")
            await logger.verbose("   - provider.transcription(.whisper1)")
            await logger.verbose("   - provider.speech(.tts1)")
        }

        return try provider.languageModel(modelId: modelId)
    }
}
