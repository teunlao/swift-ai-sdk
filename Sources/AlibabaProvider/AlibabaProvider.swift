import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/alibaba-provider.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

private struct AlibabaErrorData: Codable {
    struct ErrorPayload: Codable {
        let message: String
        let code: String?
        let type: String?
    }

    let error: ErrorPayload
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let alibabaErrorDataSchema = FlexibleSchema(
    Schema<AlibabaErrorData>.codable(
        AlibabaErrorData.self,
        jsonSchema: genericJSONObjectSchema
    )
)

let alibabaFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: alibabaErrorDataSchema,
    errorToMessage: { $0.error.message }
)

public struct AlibabaProviderSettings: Sendable {
    /// Use a different URL prefix for API calls.
    /// Default: `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`.
    public var baseURL: String?

    /// Use a different URL prefix for video generation API calls.
    /// Default: `https://dashscope-intl.aliyuncs.com`.
    public var videoBaseURL: String?

    /// API key sent using the `Authorization` header. Defaults to `ALIBABA_API_KEY`.
    public var apiKey: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation.
    public var fetch: FetchFunction?

    /// Include usage information in streaming responses.
    /// Default: true.
    public var includeUsage: Bool?

    public init(
        baseURL: String? = nil,
        videoBaseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        includeUsage: Bool? = nil
    ) {
        self.baseURL = baseURL
        self.videoBaseURL = videoBaseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.includeUsage = includeUsage
    }
}

public final class AlibabaProvider: ProviderV3 {
    private let chatFactory: @Sendable (AlibabaChatModelId) -> AlibabaChatLanguageModel
    private let videoFactory: @Sendable (AlibabaVideoModelId) -> AlibabaVideoModel

    init(
        chatFactory: @escaping @Sendable (AlibabaChatModelId) -> AlibabaChatLanguageModel,
        videoFactory: @escaping @Sendable (AlibabaVideoModelId) -> AlibabaVideoModel
    ) {
        self.chatFactory = chatFactory
        self.videoFactory = videoFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(AlibabaChatModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func videoModel(modelId: String) throws -> (any VideoModelV3)? {
        videoFactory(AlibabaVideoModelId(rawValue: modelId))
    }

    public func languageModel(modelId: AlibabaChatModelId) -> AlibabaChatLanguageModel {
        chatFactory(modelId)
    }

    public func languageModel(_ modelId: AlibabaChatModelId) -> AlibabaChatLanguageModel {
        chatFactory(modelId)
    }

    public func chatModel(modelId: AlibabaChatModelId) -> AlibabaChatLanguageModel {
        chatFactory(modelId)
    }

    public func chatModel(_ modelId: AlibabaChatModelId) -> AlibabaChatLanguageModel {
        chatFactory(modelId)
    }

    public func video(modelId: AlibabaVideoModelId) -> AlibabaVideoModel {
        videoFactory(modelId)
    }

    public func video(_ modelId: AlibabaVideoModelId) -> AlibabaVideoModel {
        videoFactory(modelId)
    }

    public func videoModel(modelId: AlibabaVideoModelId) -> AlibabaVideoModel {
        videoFactory(modelId)
    }

    public func videoModel(_ modelId: AlibabaVideoModelId) -> AlibabaVideoModel {
        videoFactory(modelId)
    }
}

private let defaultAlibabaBaseURL = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
private let defaultAlibabaVideoBaseURL = "https://dashscope-intl.aliyuncs.com"

// MARK: - Provider call/aliases (parity with TS facade)

public extension AlibabaProvider {
    /// Allow calling the provider instance like a function: `alibaba("qwen-plus")`.
    func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }
}

/// Create an Alibaba Cloud (Qwen) provider instance.
public func createAlibabaProvider(
    settings: AlibabaProviderSettings = .init()
) -> AlibabaProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL ?? defaultAlibabaBaseURL) ?? defaultAlibabaBaseURL
    let videoBaseURL = withoutTrailingSlash(settings.videoBaseURL ?? defaultAlibabaVideoBaseURL) ?? defaultAlibabaVideoBaseURL

    let headersClosure: @Sendable () throws -> [String: String?] = {
        let apiKey = try loadAPIKey(
            apiKey: settings.apiKey,
            environmentVariableName: "ALIBABA_API_KEY",
            description: "Alibaba Cloud (DashScope)"
        )

        var headers: [String: String?] = [
            "Authorization": "Bearer \(apiKey)",
        ]

        if let custom = settings.headers {
            for (key, value) in custom {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk/alibaba/\(ALIBABA_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let chatFactory: @Sendable (AlibabaChatModelId) -> AlibabaChatLanguageModel = { modelId in
        AlibabaChatLanguageModel(
            modelId: modelId,
            config: AlibabaChatConfig(
                provider: "alibaba.chat",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch,
                includeUsage: settings.includeUsage ?? true
            )
        )
    }

    let videoFactory: @Sendable (AlibabaVideoModelId) -> AlibabaVideoModel = { modelId in
        AlibabaVideoModel(
            modelId: modelId,
            config: AlibabaVideoModelConfig(
                provider: "alibaba.video",
                baseURL: videoBaseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return AlibabaProvider(chatFactory: chatFactory, videoFactory: videoFactory)
}

/// Alias matching upstream naming (`createAlibaba`).
public func createAlibaba(
    settings: AlibabaProviderSettings = .init()
) -> AlibabaProvider {
    createAlibabaProvider(settings: settings)
}

/// Default Alibaba provider instance.
public let alibaba: AlibabaProvider = createAlibabaProvider()
