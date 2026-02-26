import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/vercel/src/vercel-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct VercelProviderSettings: Sendable {
    /// Vercel API key.
    public var apiKey: String?

    /// Base URL for the API calls.
    public var baseURL: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation. You can use it as a middleware to intercept requests,
    /// or to provide a custom fetch implementation for e.g. testing.
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

public final class VercelProvider: ProviderV3 {
    private let chatFactory: @Sendable (VercelChatModelId) -> OpenAICompatibleChatLanguageModel

    init(chatFactory: @escaping @Sendable (VercelChatModelId) -> OpenAICompatibleChatLanguageModel) {
        self.chatFactory = chatFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(VercelChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
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

    public func chat(_ modelId: VercelChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func languageModel(_ modelId: VercelChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }
}

private let defaultBaseURL = "https://api.v0.dev/v1"

private func defaultVercelFetchFunction() -> FetchFunction {
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

private func createVercelAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultVercelFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "VERCEL_API_KEY",
            description: "Vercel"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createVercelProvider(settings: VercelProviderSettings = .init()) -> VercelProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? defaultBaseURL

    let headersClosure: @Sendable () -> [String: String] = {
        var computed: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        return withUserAgentSuffix(computed, "ai-sdk/vercel/\(VERCEL_VERSION)")
    }

    let fetch = createVercelAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let chatFactory: @Sendable (VercelChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: OpenAICompatibleChatConfig(
                provider: "vercel.chat",
                headers: headersClosure,
                url: { options in "\(baseURL)\(options.path)" },
                fetch: fetch
            )
        )
    }

    return VercelProvider(chatFactory: chatFactory)
}

/// Alias matching upstream naming (`createVercel`).
public func createVercel(settings: VercelProviderSettings = .init()) -> VercelProvider {
    createVercelProvider(settings: settings)
}

/// Default Vercel provider instance (`export const vercel = createVercel()`).
public let vercel: VercelProvider = createVercelProvider()
