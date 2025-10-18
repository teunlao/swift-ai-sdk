import Foundation
import AISDKProvider
import AISDKProviderUtils

enum ProviderFactory {
    static func makeLanguageModel(
        provider: String,
        modelId: String,
        configuration: PlaygroundConfiguration,
        logger: PlaygroundLogger
    ) throws -> any LanguageModelV3 {
        switch provider.lowercased() {
        case "gateway":
            guard let apiKey = configuration.keys.gateway, !apiKey.isEmpty else {
                throw ContextError.missingAPIKey(provider: "gateway")
            }
            let baseURL = configuration.baseURLOverrides["gateway"]
            return GatewayLanguageModel(
                modelId: modelId,
                apiKey: apiKey,
                baseURL: baseURL
            )

        case "openai":
            return try OpenAIPlaygroundFactory.makeLanguageModel(
                modelId: modelId,
                configuration: configuration,
                logger: logger
            )

        default:
            throw ContextError.unsupportedProvider(provider)
        }
    }
}
