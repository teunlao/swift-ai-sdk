import Foundation
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK

enum ProviderFactory {
    static func makeLanguageModel(
        provider: String,
        modelId: String,
        configuration: PlaygroundConfiguration,
        logger: PlaygroundLogger
    ) throws -> LanguageModel {
        switch provider.lowercased() {
        case "gateway":
            guard let apiKey = configuration.keys.gateway, !apiKey.isEmpty else {
                throw ContextError.missingAPIKey(provider: "gateway")
            }
            let baseURL = configuration.baseURLOverrides["gateway"]
            return .v3(GatewayLanguageModel(
                modelId: modelId,
                apiKey: apiKey,
                baseURL: baseURL
            ))

        case "openai":
            return .v4(try OpenAIPlaygroundFactory.makeLanguageModel(
                modelId: modelId,
                configuration: configuration,
                logger: logger
            ))

        default:
            throw ContextError.unsupportedProvider(provider)
        }
    }
}
