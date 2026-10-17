import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct HuggingFaceProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: (@Sendable () -> String)?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: (@Sendable () -> String)? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}

public final class HuggingFaceProvider: ProviderV4 {
    private let responsesFactory: @Sendable (HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel

    init(responsesFactory: @escaping @Sendable (HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel) {
        self.responsesFactory = responsesFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        responsesFactory(HuggingFaceResponsesModelId(rawValue: modelId))
    }

    public func responses(_ modelId: HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel {
        responsesFactory(modelId)
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .embeddingModel,
            message: "Hugging Face Responses API does not support text embeddings. Use the Hugging Face Inference API directly for embeddings."
        )
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .imageModel,
            message: "Hugging Face Responses API does not support image generation. Use the Hugging Face Inference API directly for image models."
        )
    }

    public func callAsFunction(_ modelId: HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel {
        responsesFactory(modelId)
    }
}

public func createHuggingFace(settings: HuggingFaceProviderSettings = .init()) -> HuggingFaceProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://router.huggingface.co/v1"
    let headers: @Sendable () throws -> [String: String?] = {
        let key = try loadAPIKey(
            apiKey: settings.apiKey,
            environmentVariableName: "HUGGINGFACE_API_KEY",
            description: "Hugging Face"
        )
        let headers = combineHeaders(
            ["Authorization": "Bearer \(key)"],
            settings.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }
        return withUserAgentSuffix(headers, "ai-sdk-huggingface/\(HUGGINGFACE_VERSION)").mapValues { Optional($0) }
    }

    return HuggingFaceProvider { modelId in
        HuggingFaceResponsesLanguageModel(
            modelId: modelId,
            config: HuggingFaceConfig(
                provider: "huggingface.responses",
                url: { "\(baseURL)\($0.path)" },
                headers: headers,
                fetch: settings.fetch,
                generateId: settings.generateId ?? { generateID() }
            )
        )
    }
}

public let huggingFace = createHuggingFace()
