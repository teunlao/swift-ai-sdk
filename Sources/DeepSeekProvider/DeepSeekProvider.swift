import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

/// Settings for configuring the DeepSeek provider.
/// Mirrors `packages/deepseek/src/deepseek-provider.ts`.
public struct DeepSeekProviderSettings: Sendable {
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

/// DeepSeek provider backed by the OpenAI-compatible chat implementation.
/// Mirrors `packages/deepseek/src/deepseek-provider.ts`.
public final class DeepSeekProvider: ProviderV3 {
    private let chatFactory: @Sendable (DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel

    init(chatFactory: @escaping @Sendable (DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel) {
        self.chatFactory = chatFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(DeepSeekChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(DeepSeekChatModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(_ modelId: DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func languageModel(_ modelId: DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }
}

private func defaultDeepSeekFetchFunction() -> FetchFunction {
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

private func createDeepSeekAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultDeepSeekFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "DEEPSEEK_API_KEY",
            description: "DeepSeek API key"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createDeepSeekProvider(settings: DeepSeekProviderSettings = .init()) -> DeepSeekProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.deepseek.com"

    let headersClosure: @Sendable () -> [String: String] = {
        var headers: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk/deepseek/\(DEEPSEEK_PROVIDER_VERSION)")
        return withUA
    }

    let fetch = createDeepSeekAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let chatFactory: @Sendable (DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: OpenAICompatibleChatConfig(
                provider: "deepseek.chat",
                headers: headersClosure,
                url: { options in "\(baseURL)\(options.path)" },
                fetch: fetch,
                metadataExtractor: deepSeekMetadataExtractor
            )
        )
    }

    return DeepSeekProvider(chatFactory: chatFactory)
}

/// Alias matching the upstream naming (`createDeepSeek`).
public func createDeepSeek(settings: DeepSeekProviderSettings = .init()) -> DeepSeekProvider {
    createDeepSeekProvider(settings: settings)
}

/// Default DeepSeek provider instance (`export const deepseek = createDeepSeek()`).
public let deepseek: DeepSeekProvider = createDeepSeekProvider()
