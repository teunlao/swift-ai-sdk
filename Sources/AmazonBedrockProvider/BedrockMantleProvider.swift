import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

public struct BedrockMantleProviderSettings: Sendable {
    public var region: String?
    public var apiKey: String?
    public var accessKeyId: String?
    public var secretAccessKey: String?
    public var sessionToken: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var credentialProvider: AmazonBedrockProviderSettings.CredentialProvider?
    public init(region: String? = nil, apiKey: String? = nil, accessKeyId: String? = nil, secretAccessKey: String? = nil, sessionToken: String? = nil, baseURL: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil, credentialProvider: AmazonBedrockProviderSettings.CredentialProvider? = nil) {
        self.region = region; self.apiKey = apiKey; self.accessKeyId = accessKeyId; self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch; self.credentialProvider = credentialProvider
    }
    var common: AmazonBedrockProviderSettings {
        .init(region: region, apiKey: apiKey, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken, baseURL: baseURL, headers: headers, fetch: fetch, credentialProvider: credentialProvider)
    }
}

public struct BedrockMantleModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let gptOss20b: Self = "openai.gpt-oss-20b"
    public static let gptOss120b: Self = "openai.gpt-oss-120b"
    public static let gptOssSafeguard20b: Self = "openai.gpt-oss-safeguard-20b"
    public static let gptOssSafeguard120b: Self = "openai.gpt-oss-safeguard-120b"
}

public final class BedrockMantleProvider: ProviderV4 {
    private let settings: BedrockMantleProviderSettings
    private let fetch: FetchFunction
    init(settings: BedrockMantleProviderSettings) {
        self.settings = settings
        self.fetch = makeBedrockFetchFunction(settings: settings.common, service: "bedrock-mantle", inheritSessionToken: true)
    }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 { chat(modelId: .init(rawValue: modelId)) }
    public func callAsFunction(_ modelId: String) -> OpenAIChatLanguageModelV4 { chat(modelId: .init(rawValue: modelId)) }
    public func chat(modelId: BedrockMantleModelId) -> OpenAIChatLanguageModelV4 {
        .init(modelId: .init(rawValue: modelId.rawValue), config: config(provider: "bedrock-mantle.chat"))
    }
    public func responses(modelId: BedrockMantleModelId) -> OpenAIResponsesLanguageModelV4 {
        .init(modelId: .init(rawValue: modelId.rawValue), config: config(provider: "bedrock-mantle.responses"))
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel) }
    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV4 { try embeddingModel(modelId: modelId) }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
    private func config(provider: String) -> OpenAIConfig {
        .init(provider: provider, url: { options in
            let base: String
            if let custom = withoutTrailingSlash(self.settings.baseURL) { base = custom }
            else {
                let region = try loadBedrockRegion(self.settings.region)
                try validateBedrockRegion(region)
                let openAIRoute = options.modelId.range(of: "^(?:openai\\.gpt-(?!oss-)|google\\.gemma-4|xai\\.)", options: .regularExpression) != nil
                base = "https://bedrock-mantle.\(region).api.aws/\(openAIRoute ? "openai/v1" : "v1")"
            }
            return base + options.path
        }, headers: { bedrockHeaders(self.settings.headers) }, fetch: fetch, supportsWebSearchSourcesInclude: false)
    }
}

public func createBedrockMantle(settings: BedrockMantleProviderSettings = .init()) -> BedrockMantleProvider { .init(settings: settings) }
public let bedrockMantle = createBedrockMantle()
