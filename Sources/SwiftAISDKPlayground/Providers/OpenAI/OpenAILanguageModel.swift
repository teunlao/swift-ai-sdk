import Foundation
import AISDKProvider
import OpenAIProvider

/// Factory for creating OpenAI language models in the playground.
///
/// Demonstrates multiple ways to use the OpenAI provider API:
/// 1. Global `openai` constant (default instance)
/// 2. Custom provider via `createOpenAIProvider(settings:)`
/// 3. Shortcut methods: `.chat()`, `.embedding()`, `.image()`, etc.
/// 4. `callAsFunction` syntax: `openai("gpt-4o")`
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
            await logger.verbose("🆕 New API: can use global `openai` constant or shortcut methods")
        }

        // If no custom settings, use global `openai` constant (NEW!)
        if baseURL == nil && organization == nil && project == nil {
            Task {
                await logger.verbose("✅ Using global openai.languageModel(\"\(modelId)\")")
            }
            // NEW: Using global `openai` constant (parity with TypeScript)
            return try openai.languageModel(modelId: modelId)

            // Alternative syntaxes (all equivalent):
            // return openai(modelId)  // callAsFunction syntax
            // return openai.chat(.gpt4o)  // typed model ID
            // return openai.responses(.gpt4o)  // responses API
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
