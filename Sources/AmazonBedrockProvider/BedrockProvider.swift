import Foundation
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider
@_exported import struct AnthropicProvider.AnthropicProviderOptions

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

public final class AmazonBedrockProvider: ProviderV4 {
    private let settings: AmazonBedrockProviderSettings
    private let fetch: FetchFunction
    public let tools: AnthropicTools = anthropicTools

    init(settings: AmazonBedrockProviderSettings) {
        self.settings = settings
        self.fetch = makeBedrockFetchFunction(settings: settings)
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        chat(modelId: .init(rawValue: modelId))
    }

    public func languageModel(modelId: String, settings: BedrockChatModelSettings) -> BedrockChatLanguageModel {
        chat(modelId: .init(rawValue: modelId), settings: settings)
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embedding(modelId: .init(rawValue: modelId))
    }

    public func embeddingModel(modelId: String, settings: BedrockEmbeddingModelSettings) -> BedrockEmbeddingModel {
        embedding(modelId: .init(rawValue: modelId), settings: settings)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        try embeddingModel(modelId: modelId)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        image(modelId: .init(rawValue: modelId))
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV4)? {
        reranking(modelId: .init(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String, settings: BedrockChatModelSettings = .init()) -> BedrockChatLanguageModel {
        chat(modelId: .init(rawValue: modelId), settings: settings)
    }

    public func chat(modelId: BedrockChatModelId, settings modelSettings: BedrockChatModelSettings = .init()) -> BedrockChatLanguageModel {
        BedrockChatLanguageModel(modelId: modelId, config: .init(
            baseURL: { try resolveBedrockBaseURL(settings: self.settings, service: "bedrock-runtime") },
            headers: { bedrockHeaders(self.settings.headers) },
            fetch: fetch,
            generateId: settings.generateId,
            modelFamily: modelSettings.modelFamily
        ))
    }

    public func embedding(modelId: BedrockEmbeddingModelId, settings modelSettings: BedrockEmbeddingModelSettings = .init()) -> BedrockEmbeddingModel {
        BedrockEmbeddingModel(modelId: modelId, config: .init(
            baseURL: { try resolveBedrockBaseURL(settings: self.settings, service: "bedrock-runtime") },
            headers: { bedrockHeaders(self.settings.headers) },
            fetch: fetch,
            modelFamily: modelSettings.modelFamily
        ))
    }

    public func textEmbedding(modelId: BedrockEmbeddingModelId) -> BedrockEmbeddingModel {
        embedding(modelId: modelId)
    }

    public func image(modelId: BedrockImageModelId) -> BedrockImageModel {
        BedrockImageModel(modelId: modelId, config: .init(
            baseURL: { try resolveBedrockBaseURL(settings: self.settings, service: "bedrock-runtime") },
            headers: { bedrockHeaders(self.settings.headers) },
            fetch: fetch,
            currentDate: { Date() }
        ))
    }

    public func reranking(modelId: BedrockRerankingModelId) -> BedrockRerankingModel {
        BedrockRerankingModel(modelId: modelId, config: .init(
            baseURL: { try resolveBedrockBaseURL(settings: self.settings, service: "bedrock-agent-runtime") },
            region: { try loadBedrockRegion(self.settings.region) },
            headers: { bedrockHeaders(self.settings.headers) },
            fetch: fetch
        ))
    }
}

public func createAmazonBedrock(settings: AmazonBedrockProviderSettings = .init()) -> AmazonBedrockProvider {
    AmazonBedrockProvider(settings: settings)
}

public let amazonBedrock = createAmazonBedrock()
public let bedrock = amazonBedrock

func loadBedrockRegion(_ region: String?) throws -> String {
    try loadSetting(settingValue: region, environmentVariableName: "AWS_REGION", settingName: "region", description: "AWS region")
}

func resolveBedrockBaseURL(settings: AmazonBedrockProviderSettings, service: String) throws -> String {
    let endpointVariable = service == "bedrock-agent-runtime" ? "AWS_ENDPOINT_URL_BEDROCK_AGENT_RUNTIME" : "AWS_ENDPOINT_URL_BEDROCK_RUNTIME"
    if let baseURL = settings.baseURL
        ?? loadOptionalSetting(settingValue: nil, environmentVariableName: endpointVariable)
        ?? loadOptionalSetting(settingValue: nil, environmentVariableName: "AWS_ENDPOINT_URL") {
        return withoutTrailingSlash(baseURL) ?? baseURL
    }
    let region = try loadBedrockRegion(settings.region)
    try validateBedrockRegion(region)
    let partitions = [
        ("cn-", "amazonaws.com.cn"), ("us-iso-", "c2s.ic.gov"),
        ("us-isob-", "sc2s.sgov.gov"), ("eu-isoe-", "cloud.adc-e.uk"),
        ("us-isof-", "csp.hci.ic.gov"), ("eusc-", "amazonaws.eu")
    ]
    let suffix = partitions.first { region.hasPrefix($0.0) }?.1 ?? "amazonaws.com"
    return "https://\(service).\(region).\(suffix)"
}

func validateBedrockRegion(_ region: String) throws {
    guard region.range(of: "\\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\z", options: .regularExpression) != nil else {
        throw InvalidArgumentError(argument: "region", message: "Invalid AWS region. Expected a single DNS label (letters, digits, and hyphens). Use `baseURL` for custom endpoints.")
    }
}

func bedrockHeaders(_ headers: [String: String]?) -> [String: String?] {
    withUserAgentSuffix(headers ?? [:], "ai-sdk-amazon-bedrock/\(AMAZON_BEDROCK_VERSION)").mapValues { Optional($0) }
}

func makeBedrockFetchFunction(settings: AmazonBedrockProviderSettings, service: String = "bedrock", inheritSessionToken: Bool = false) -> FetchFunction {
    let rawKey = loadOptionalSetting(settingValue: settings.apiKey, environmentVariableName: "AWS_BEARER_TOKEN_BEDROCK")
    if let apiKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
        return createApiKeyFetchFunction(apiKey: apiKey, fetch: settings.fetch)
    }
    return createSigV4FetchFunction(getCredentials: {
        let region = try loadBedrockRegion(settings.region)
        if let provider = settings.credentialProvider {
            do {
                let credentials = try await provider()
                return BedrockCredentials(region: region, accessKeyId: credentials.accessKeyId, secretAccessKey: credentials.secretAccessKey, sessionToken: credentials.sessionToken)
            } catch {
                throw BedrockCredentialError(message: "AWS credential provider failed: \(AISDKProviderUtils.getErrorMessage(error)). Please ensure your credential provider returns valid AWS credentials with accessKeyId and secretAccessKey properties.")
            }
        }
        do {
            let accessKeyId = try loadSetting(settingValue: settings.accessKeyId, environmentVariableName: "AWS_ACCESS_KEY_ID", settingName: "accessKeyId", description: "AWS access key ID")
            let secretAccessKey = try loadSetting(settingValue: settings.secretAccessKey, environmentVariableName: "AWS_SECRET_ACCESS_KEY", settingName: "secretAccessKey", description: "AWS secret access key")
            let sessionToken = !inheritSessionToken && settings.accessKeyId != nil && settings.secretAccessKey != nil
                ? settings.sessionToken
                : loadOptionalSetting(settingValue: settings.sessionToken, environmentVariableName: "AWS_SESSION_TOKEN")
            return BedrockCredentials(region: region, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken)
        } catch {
            let message = AISDKProviderUtils.getErrorMessage(error)
            if message.contains("AWS_ACCESS_KEY_ID") || message.contains("accessKeyId") {
                throw BedrockCredentialError(message: "AWS SigV4 authentication requires AWS credentials. Please provide either:\n1. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables\n2. Provide accessKeyId and secretAccessKey in options\n3. Use a credentialProvider function\n4. Use API key authentication with AWS_BEARER_TOKEN_BEDROCK or apiKey option\nOriginal error: \(message)")
            }
            if message.contains("AWS_SECRET_ACCESS_KEY") || message.contains("secretAccessKey") {
                throw BedrockCredentialError(message: "AWS SigV4 authentication requires both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY. Please ensure both credentials are provided.\nOriginal error: \(message)")
            }
            throw error
        }
    }, fetch: settings.fetch, service: service)
}

struct BedrockCredentialError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
