import Foundation
import AISDKProvider
import SwiftAISDK

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
            await logger.verbose("Использую провайдера openai (model=\(modelId))")
        }

        let settings = OpenAIProviderSettings(
            baseURL: baseURL,
            apiKey: apiKey,
            organization: organization,
            project: project
        )

        let provider = createOpenAIProvider(settings: settings)
        return provider.languageModel(modelId: modelId)
    }
}
