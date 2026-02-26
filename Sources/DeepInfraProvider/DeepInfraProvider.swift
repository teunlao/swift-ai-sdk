import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepinfra/src/deepinfra-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct DeepInfraProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

public final class DeepInfraProvider: ProviderV3 {
    private let chatFactory: @Sendable (DeepInfraChatModelId) -> OpenAICompatibleChatLanguageModel
    private let completionFactory: @Sendable (DeepInfraCompletionModelId) -> OpenAICompatibleCompletionLanguageModel
    private let embeddingFactory: @Sendable (DeepInfraEmbeddingModelId) -> OpenAICompatibleEmbeddingModel
    private let imageFactory: @Sendable (DeepInfraImageModelId) -> DeepInfraImageModel

    init(
        chatFactory: @escaping @Sendable (DeepInfraChatModelId) -> OpenAICompatibleChatLanguageModel,
        completionFactory: @escaping @Sendable (DeepInfraCompletionModelId) -> OpenAICompatibleCompletionLanguageModel,
        embeddingFactory: @escaping @Sendable (DeepInfraEmbeddingModelId) -> OpenAICompatibleEmbeddingModel,
        imageFactory: @escaping @Sendable (DeepInfraImageModelId) -> DeepInfraImageModel
    ) {
        self.chatFactory = chatFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(DeepInfraChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV3 {
        completionFactory(DeepInfraCompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(DeepInfraEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(DeepInfraImageModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: DeepInfraChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func completion(modelId: DeepInfraCompletionModelId) -> OpenAICompatibleCompletionLanguageModel {
        completionFactory(modelId)
    }

    public func embedding(modelId: DeepInfraEmbeddingModelId) -> OpenAICompatibleEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func image(modelId: DeepInfraImageModelId) -> DeepInfraImageModel {
        imageFactory(modelId)
    }
}

private func defaultDeepInfraFetchFunction() -> FetchFunction {
    { request in
        let session = URLSession.shared

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            let (bytes, response) = try await session.bytes(for: request)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                Task {
                    var buffer = Data()
                    buffer.reserveCapacity(16_384)

                    do {
                        for try await byte in bytes {
                            buffer.append(byte)

                            if buffer.count >= 16_384 {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }

                        if !buffer.isEmpty {
                            continuation.yield(buffer)
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            return FetchResponse(body: .stream(stream), urlResponse: response)
        } else {
            let (data, response) = try await session.data(for: request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }
}

private func createDeepInfraAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultDeepInfraFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "DEEPINFRA_API_KEY",
            description: "DeepInfra API key"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createDeepInfraProvider(settings: DeepInfraProviderSettings = .init()) -> DeepInfraProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.deepinfra.com/v1"

    let headersClosure: @Sendable () -> [String: String] = {
        var baseHeaders: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                baseHeaders[key] = value
            }
        }

        return withUserAgentSuffix(baseHeaders, "ai-sdk/deepinfra/\(DEEPINFRA_VERSION)")
    }

    let fetch = createDeepInfraAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String = { options in
        "\(baseURL)/openai\(options.path)"
    }

    let chatFactory: @Sendable (DeepInfraChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        let config = OpenAICompatibleChatConfig(
            provider: "deepinfra.chat",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch,
            usagePostprocessor: fixDeepInfraUsageForGeminiModels
        )
        return OpenAICompatibleChatLanguageModel(modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue), config: config)
    }

    let completionFactory: @Sendable (DeepInfraCompletionModelId) -> OpenAICompatibleCompletionLanguageModel = { modelId in
        let config = OpenAICompatibleCompletionConfig(
            provider: "deepinfra.completion",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch
        )
        return OpenAICompatibleCompletionLanguageModel(modelId: OpenAICompatibleCompletionModelId(rawValue: modelId.rawValue), config: config)
    }

    let embeddingFactory: @Sendable (DeepInfraEmbeddingModelId) -> OpenAICompatibleEmbeddingModel = { modelId in
        let config = OpenAICompatibleEmbeddingConfig(
            provider: "deepinfra.embedding",
            url: urlBuilder,
            headers: headersClosure,
            fetch: fetch
        )
        return OpenAICompatibleEmbeddingModel(modelId: OpenAICompatibleEmbeddingModelId(rawValue: modelId.rawValue), config: config)
    }

    let imageFactory: @Sendable (DeepInfraImageModelId) -> DeepInfraImageModel = { modelId in
        let config = DeepInfraImageModelConfig(
            provider: "deepinfra.image",
            baseURL: "\(baseURL)/inference",
            headers: { headersClosure().mapValues { Optional($0) } },
            fetch: fetch,
            currentDate: { Date() }
        )
        return DeepInfraImageModel(modelId: modelId, config: config)
    }

    return DeepInfraProvider(
        chatFactory: chatFactory,
        completionFactory: completionFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory
    )
}

/// Alias matching the upstream naming (`createDeepInfra`).
public func createDeepInfra(settings: DeepInfraProviderSettings = .init()) -> DeepInfraProvider {
    createDeepInfraProvider(settings: settings)
}

public let deepinfra = createDeepInfraProvider()

// MARK: - DeepInfra-specific Usage Fix

/// Fixes incorrect token usage for Gemini/Gemma models returned by DeepInfra.
///
/// Mirrors `packages/deepinfra/src/deepinfra-chat-language-model.ts`.
/// DeepInfra sometimes returns `completion_tokens` as *text-only* tokens while reporting
/// `completion_tokens_details.reasoning_tokens` separately. In OpenAI-compatible semantics,
/// `completion_tokens` must include reasoning tokens.
@Sendable
private func fixDeepInfraUsageForGeminiModels(_ usage: LanguageModelV3Usage) -> LanguageModelV3Usage {
    guard let raw = usage.raw, case .object(var dict) = raw else {
        return usage
    }

    guard case .number(let completionNumber) = dict["completion_tokens"] else {
        return usage
    }

    guard case .object(let completionDetails) = dict["completion_tokens_details"],
          case .number(let reasoningNumber) = completionDetails["reasoning_tokens"] else {
        return usage
    }

    let completionTokens = Int(completionNumber)
    let reasoningTokens = Int(reasoningNumber)

    // If reasoning tokens exceed completion tokens, DeepInfra is returning invalid OpenAI-compatible usage.
    guard reasoningTokens > completionTokens else {
        return usage
    }

    let correctedCompletionTokens = completionTokens + reasoningTokens
    dict["completion_tokens"] = .number(Double(correctedCompletionTokens))

    // Match upstream: only adjust total_tokens if present; remove if it was explicitly null.
    if case .number(let totalNumber) = dict["total_tokens"] {
        dict["total_tokens"] = .number(totalNumber + Double(reasoningTokens))
    } else if dict["total_tokens"] == .null {
        dict.removeValue(forKey: "total_tokens")
    }

    let promptTokens: Int
    if case .number(let promptNumber) = dict["prompt_tokens"] {
        promptTokens = Int(promptNumber)
    } else {
        promptTokens = usage.inputTokens.total ?? 0
    }

    let cacheReadTokens: Int
    if case .object(let promptDetails) = dict["prompt_tokens_details"],
       case .number(let cachedNumber) = promptDetails["cached_tokens"] {
        cacheReadTokens = Int(cachedNumber)
    } else {
        cacheReadTokens = usage.inputTokens.cacheRead ?? 0
    }

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: promptTokens,
            noCache: promptTokens - cacheReadTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: usage.inputTokens.cacheWrite
        ),
        outputTokens: .init(
            total: correctedCompletionTokens,
            text: correctedCompletionTokens - reasoningTokens,
            reasoning: reasoningTokens
        ),
        raw: .object(dict)
    )
}
