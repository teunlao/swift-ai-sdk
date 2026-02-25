import AISDKProvider
import AISDKProviderUtils
import Foundation
import OpenAICompatibleProvider

private let defaultMoonshotAIBaseURL = "https://api.moonshot.ai/v1"

private func defaultMoonshotAIFetchFunction() -> FetchFunction {
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

private func createMoonshotAIAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultMoonshotAIFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            let resolved = try loadAPIKey(
                apiKey: apiKey,
                environmentVariableName: "MOONSHOT_API_KEY",
                description: "Moonshot API key"
            )
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public struct MoonshotAIProviderSettings: Sendable {
    /// Moonshot API key. Defaults to `MOONSHOT_API_KEY`.
    public var apiKey: String?
    /// Base URL for the API calls.
    public var baseURL: String?
    /// Custom headers to include in the requests.
    public var headers: [String: String]?
    /// Custom fetch implementation.
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

public final class MoonshotAIProvider: ProviderV3 {
    private let chatFactory: @Sendable (MoonshotAIChatModelId) -> MoonshotAIChatLanguageModel

    init(chatFactory: @escaping @Sendable (MoonshotAIChatModelId) -> MoonshotAIChatLanguageModel) {
        self.chatFactory = chatFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(MoonshotAIChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(MoonshotAIChatModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

public func createMoonshotAIProvider(settings: MoonshotAIProviderSettings = .init()) -> MoonshotAIProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL ?? defaultMoonshotAIBaseURL) ?? defaultMoonshotAIBaseURL

    let headersClosure: @Sendable () -> [String: String] = {
        var headers: [String: String?] = [:]
        if let provided = settings.headers {
            for (key, value) in provided {
                headers[key] = value
            }
        }

        return withUserAgentSuffix(
            headers,
            "ai-sdk/moonshotai/\(MOONSHOTAI_VERSION)"
        )
    }

    let fetch = createMoonshotAIAuthFetch(apiKey: settings.apiKey, customFetch: settings.fetch)

    let transformRequestBody: @Sendable ([String: JSONValue]) -> [String: JSONValue] = { args in
        var rest = args
        let thinking = rest.removeValue(forKey: "thinking")
        let reasoningHistory = rest.removeValue(forKey: "reasoningHistory")

        if let thinking, thinking != .null {
            if case .object(let dict) = thinking {
                var payload: [String: JSONValue] = [:]

                if let typeValue = dict["type"], typeValue != .null {
                    payload["type"] = typeValue
                }

                if let budgetTokens = dict["budgetTokens"], budgetTokens != .null {
                    payload["budget_tokens"] = budgetTokens
                }

                rest["thinking"] = .object(payload)
            } else {
                // Closest match to upstream JS behavior:
                // non-object truthy values become an empty object after JSON serialization.
                rest["thinking"] = .object([:])
            }
        }

        if let reasoningHistory, reasoningHistory != .null {
            rest["reasoning_history"] = reasoningHistory
        }

        return rest
    }

    let chatFactory: @Sendable (MoonshotAIChatModelId) -> MoonshotAIChatLanguageModel = { modelId in
        MoonshotAIChatLanguageModel(
            modelId: modelId,
            config: OpenAICompatibleChatConfig(
                provider: "moonshotai.chat",
                headers: headersClosure,
                url: { options in "\(baseURL)\(options.path)" },
                fetch: fetch,
                includeUsage: true,
                errorConfiguration: defaultOpenAICompatibleErrorConfiguration,
                transformRequestBody: transformRequestBody
            )
        )
    }

    return MoonshotAIProvider(chatFactory: chatFactory)
}

/// Alias matching the upstream naming (`createMoonshotAI`).
public func createMoonshotAI(settings: MoonshotAIProviderSettings = .init()) -> MoonshotAIProvider {
    createMoonshotAIProvider(settings: settings)
}

/// Default MoonshotAI provider instance (`export const moonshotai = createMoonshotAI()`).
public let moonshotai: MoonshotAIProvider = createMoonshotAIProvider()

