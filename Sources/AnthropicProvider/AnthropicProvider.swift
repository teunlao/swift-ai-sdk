import Foundation
import AISDKProvider
import AISDKProviderUtils

@usableFromInline
@Sendable func defaultAnthropicId() -> String {
    UUID().uuidString
}

private let anthropicHTTPSRegex: NSRegularExpression = {
    try! NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
}()

public struct AnthropicProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var authToken: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: @Sendable () -> String
    public var name: String?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        authToken: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: @escaping @Sendable () -> String = defaultAnthropicId,
        name: String? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.authToken = authToken
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
        self.name = name
    }
}

public final class AnthropicProvider: ProviderV3 {
    private let makeMessagesModel: @Sendable (AnthropicMessagesModelId) -> AnthropicMessagesLanguageModel
    public let tools: AnthropicTools

    init(
        makeMessagesModel: @escaping @Sendable (AnthropicMessagesModelId) -> AnthropicMessagesLanguageModel,
        tools: AnthropicTools
    ) {
        self.makeMessagesModel = makeMessagesModel
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        makeMessagesModel(AnthropicMessagesModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        makeMessagesModel(AnthropicMessagesModelId(rawValue: modelId))
    }

    public func chat(modelId: AnthropicMessagesModelId) -> AnthropicMessagesLanguageModel {
        makeMessagesModel(modelId)
    }

    public func messages(modelId: AnthropicMessagesModelId) -> AnthropicMessagesLanguageModel {
        makeMessagesModel(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

public func createAnthropicProvider(settings: AnthropicProviderSettings = .init()) -> AnthropicProvider {
    let baseURL = withoutTrailingSlash(
        loadOptionalSetting(settingValue: settings.baseURL, environmentVariableName: "ANTHROPIC_BASE_URL")
    ) ?? "https://api.anthropic.com/v1"

    if settings.apiKey != nil, settings.authToken != nil {
        fatalError("Both apiKey and authToken were provided. Please use only one authentication method.")
    }

    let providerName = settings.name ?? "anthropic.messages"

    let headersClosure: @Sendable () -> [String: String?] = {
        let authToken = settings.authToken

        var baseHeaders: [String: String?] = [
            "anthropic-version": "2023-06-01"
        ]

        if let authToken {
            baseHeaders["Authorization"] = "Bearer \(authToken)"
        } else {
            let apiKey: String
            do {
                apiKey = try loadAPIKey(
                    apiKey: settings.apiKey,
                    environmentVariableName: "ANTHROPIC_API_KEY",
                    description: "Anthropic"
                )
            } catch {
                fatalError("Anthropic API key is missing: \(error)")
            }
            baseHeaders["x-api-key"] = apiKey
        }

        if let custom = settings.headers {
            for (key, value) in custom {
                baseHeaders[key] = value
            }
        }

        let userAgentHeaders = withUserAgentSuffix(baseHeaders, "ai-sdk/anthropic/\(ANTHROPIC_VERSION)")
        return userAgentHeaders.mapValues { Optional($0) }
    }

    let supportedURLs: @Sendable () -> [String: [NSRegularExpression]] = {
        [
            "image/*": [anthropicHTTPSRegex],
            "application/pdf": [anthropicHTTPSRegex],
        ]
    }

    let config = AnthropicMessagesConfig(
        provider: providerName,
        baseURL: baseURL,
        headers: headersClosure,
        fetch: settings.fetch,
        supportedUrls: supportedURLs,
        generateId: settings.generateId
    )

    let messagesFactory: @Sendable (AnthropicMessagesModelId) -> AnthropicMessagesLanguageModel = { modelId in
        AnthropicMessagesLanguageModel(modelId: modelId, config: config)
    }

    return AnthropicProvider(
        makeMessagesModel: messagesFactory,
        tools: anthropicTools
    )
}

public extension AnthropicProvider {
    func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }
}

public let anthropic = createAnthropicProvider()
