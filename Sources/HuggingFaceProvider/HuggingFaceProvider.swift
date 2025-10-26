import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/huggingface-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

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

public final class HuggingFaceProvider: ProviderV3 {
    private let responsesFactory: @Sendable (HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel

    init(responsesFactory: @escaping @Sendable (HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel) {
        self.responsesFactory = responsesFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        responses(modelId: HuggingFaceResponsesModelId(rawValue: modelId))
    }

    public func responses(modelId: HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel {
        responsesFactory(modelId)
    }

    public func responses(_ modelId: HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel {
        responsesFactory(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .textEmbeddingModel,
            message: "Hugging Face Responses API does not support text embeddings. Use the Hugging Face Inference API directly for embeddings."
        )
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .imageModel,
            message: "Hugging Face Responses API does not support image generation. Use the Hugging Face Inference API directly for image models."
        )
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        throw NoSuchModelError(modelId: modelId, modelType: .transcriptionModel)
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV3)? {
        throw NoSuchModelError(modelId: modelId, modelType: .speechModel)
    }

    public func callAsFunction(_ modelId: HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel {
        responses(modelId: modelId)
    }
}

public func createHuggingFaceProvider(settings: HuggingFaceProviderSettings = .init()) -> HuggingFaceProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://router.huggingface.co/v1"

    let headersClosure: @Sendable () -> [String: String?] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "HUGGINGFACE_API_KEY",
                description: "Hugging Face"
            )
        } catch {
            fatalError("Hugging Face API key is missing: \(error)")
        }

        var baseHeaders: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                baseHeaders[key] = value
            }
        }

        return withUserAgentSuffix(baseHeaders.compactMapValues { $0 }, "ai-sdk/huggingface/\(HUGGINGFACE_VERSION)")
            .mapValues { Optional($0) }
    }

    let responsesFactory: @Sendable (HuggingFaceResponsesModelId) -> HuggingFaceResponsesLanguageModel = { modelId in
        HuggingFaceResponsesLanguageModel(
            modelId: modelId,
            config: HuggingFaceConfig(
                provider: "huggingface.responses",
                url: { options in
                    "\(baseURL)\(options.path)"
                },
                headers: headersClosure,
                fetch: settings.fetch,
                generateId: settings.generateId
            )
        )
    }

    return HuggingFaceProvider(responsesFactory: responsesFactory)
}

public let huggingface = createHuggingFaceProvider()
