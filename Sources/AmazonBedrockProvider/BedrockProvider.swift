import Foundation
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct AmazonBedrockProviderSettings: Sendable {
    public typealias CredentialProvider = @Sendable () async throws -> BedrockStaticCredentials

    public var region: String?
    public var apiKey: String?
    public var accessKeyId: String?
    public var secretAccessKey: String?
    public var sessionToken: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var credentialProvider: CredentialProvider?
    public var generateId: @Sendable () -> String

    public init(
        region: String? = nil,
        apiKey: String? = nil,
        accessKeyId: String? = nil,
        secretAccessKey: String? = nil,
        sessionToken: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        credentialProvider: CredentialProvider? = nil,
        generateId: @escaping @Sendable () -> String = generateID
    ) {
        self.region = region
        self.apiKey = apiKey
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.credentialProvider = credentialProvider
        self.generateId = generateId
    }
}

public struct BedrockStaticCredentials: Sendable {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?

    public init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}

public final class AmazonBedrockProvider: ProviderV3 {
    private let chatFactory: @Sendable (BedrockChatModelId) -> BedrockChatLanguageModel
    private let embeddingFactory: @Sendable (BedrockEmbeddingModelId) -> BedrockEmbeddingModel
    private let imageFactory: @Sendable (BedrockImageModelId) -> BedrockImageModel
    private let rerankingFactory: @Sendable (BedrockRerankingModelId) -> BedrockRerankingModel

    public let tools: AnthropicTools

    init(
        chatFactory: @escaping @Sendable (BedrockChatModelId) -> BedrockChatLanguageModel,
        embeddingFactory: @escaping @Sendable (BedrockEmbeddingModelId) -> BedrockEmbeddingModel,
        imageFactory: @escaping @Sendable (BedrockImageModelId) -> BedrockImageModel,
        rerankingFactory: @escaping @Sendable (BedrockRerankingModelId) -> BedrockRerankingModel,
        tools: AnthropicTools
    ) {
        self.chatFactory = chatFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
        self.rerankingFactory = rerankingFactory
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(BedrockChatModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(BedrockEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(BedrockImageModelId(rawValue: modelId))
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV3)? {
        rerankingFactory(BedrockRerankingModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    // MARK: - Convenience

    public func chat(modelId: BedrockChatModelId) -> BedrockChatLanguageModel {
        chatFactory(modelId)
    }

    public func textEmbedding(modelId: BedrockEmbeddingModelId) -> BedrockEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func image(modelId: BedrockImageModelId) -> BedrockImageModel {
        imageFactory(modelId)
    }

    public func reranking(modelId: BedrockRerankingModelId) -> BedrockRerankingModel {
        rerankingFactory(modelId)
    }
}

public func createAmazonBedrock(
    settings: AmazonBedrockProviderSettings = .init()
) -> AmazonBedrockProvider {
    let fetch = makeFetchFunction(settings: settings)

    let region: String = {
        (try? loadSetting(
            settingValue: settings.region,
            environmentVariableName: "AWS_REGION",
            settingName: "region",
            description: "AWS region"
        )) ?? "us-east-1"
    }()

    let baseURLResolver: @Sendable () -> String = {
        if let custom = withoutTrailingSlash(settings.baseURL) {
            return custom
        }

        return "https://bedrock-runtime.\(region).amazonaws.com"
    }

    let headersResolver: @Sendable () -> [String: String?] = {
        let base = settings.headers ?? [:]
        let withUA = withUserAgentSuffix(
            base,
            "ai-sdk/amazon-bedrock/\(AMAZON_BEDROCK_VERSION)"
        )
        return withUA.mapValues { Optional($0) }
    }

    let generateId = settings.generateId

    let chatFactory: @Sendable (BedrockChatModelId) -> BedrockChatLanguageModel = { modelId in
        BedrockChatLanguageModel(
            modelId: modelId,
            config: .init(
                baseURL: baseURLResolver,
                headers: headersResolver,
                fetch: fetch,
                generateId: generateId
            )
        )
    }

    let embeddingFactory: @Sendable (BedrockEmbeddingModelId) -> BedrockEmbeddingModel = { modelId in
        BedrockEmbeddingModel(
            modelId: modelId,
            config: BedrockEmbeddingConfig(
                baseURL: baseURLResolver,
                headers: headersResolver,
                fetch: fetch
            )
        )
    }

    let imageFactory: @Sendable (BedrockImageModelId) -> BedrockImageModel = { modelId in
        BedrockImageModel(
            modelId: modelId,
            config: BedrockImageModelConfig(
                baseURL: baseURLResolver,
                headers: headersResolver,
                fetch: fetch,
                currentDate: { Date() }
            )
        )
    }

    let rerankingFactory: @Sendable (BedrockRerankingModelId) -> BedrockRerankingModel = { modelId in
        BedrockRerankingModel(
            modelId: modelId,
            config: BedrockRerankingModel.Config(
                baseURL: baseURLResolver,
                region: region,
                headers: headersResolver,
                fetch: fetch
            )
        )
    }

    return AmazonBedrockProvider(
        chatFactory: chatFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory,
        rerankingFactory: rerankingFactory,
        tools: anthropicTools
    )
}

public let bedrock = createAmazonBedrock()

// MARK: - Fetch Function Helpers

private func makeFetchFunction(settings: AmazonBedrockProviderSettings) -> FetchFunction {
    if let apiKey = trimmed(settings.apiKey) ?? trimmed(loadOptionalSetting(settingValue: nil, environmentVariableName: "AWS_BEARER_TOKEN_BEDROCK")),
       !apiKey.isEmpty {
        return createApiKeyFetchFunction(apiKey: apiKey, fetch: settings.fetch)
    }

    return createSigV4FetchFunction(
        getCredentials: {
            let region = try loadSetting(
                settingValue: settings.region,
                environmentVariableName: "AWS_REGION",
                settingName: "region",
                description: "AWS region"
            )

            if let provider = settings.credentialProvider {
                let creds = try await provider()
                return BedrockCredentials(
                    region: region,
                    accessKeyId: creds.accessKeyId,
                    secretAccessKey: creds.secretAccessKey,
                    sessionToken: creds.sessionToken
                )
            }

            do {
                let accessKeyId = try loadSetting(
                    settingValue: settings.accessKeyId,
                    environmentVariableName: "AWS_ACCESS_KEY_ID",
                    settingName: "accessKeyId",
                    description: "AWS access key ID"
                )

                let secretAccessKey = try loadSetting(
                    settingValue: settings.secretAccessKey,
                    environmentVariableName: "AWS_SECRET_ACCESS_KEY",
                    settingName: "secretAccessKey",
                    description: "AWS secret access key"
                )

                let sessionToken = loadOptionalSetting(
                    settingValue: settings.sessionToken,
                    environmentVariableName: "AWS_SESSION_TOKEN"
                )

                return BedrockCredentials(
                    region: region,
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    sessionToken: sessionToken
                )
            } catch {
                let message = errorMessage(for: error)
                throw APICallError(message: message, url: "", requestBodyValues: nil, cause: error)
            }
        },
        fetch: settings.fetch
    )
}

private func trimmed(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

private func errorMessage(for error: Error) -> String {
    let description = String(describing: error)
    if description.contains("AWS_ACCESS_KEY_ID") || description.contains("accessKeyId") {
        return "AWS SigV4 authentication requires AWS credentials. Provide AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, pass credentials in settings, use a credential provider, or provide an API key. Original error: \(description)"
    }
    if description.contains("AWS_SECRET_ACCESS_KEY") || description.contains("secretAccessKey") {
        return "AWS SigV4 authentication requires both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY. Original error: \(description)"
    }
    return description
}
