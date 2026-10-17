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
            let provider = createGateway(settings: .init(
                baseURL: configuration.baseURLOverrides["gateway"]?.absoluteString,
                apiKey: configuration.keys.gateway
            ))
            return .model(try provider.languageModel(modelId: modelId))

        case "openai":
            return .model(try OpenAIPlaygroundFactory.makeLanguageModel(
                modelId: modelId,
                configuration: configuration,
                logger: logger
            ))

        default:
            throw ContextError.unsupportedProvider(provider)
        }
    }
}
