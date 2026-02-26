import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GroqProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class GroqProvider: ProviderV3 {
    private let languageModelFactory: @Sendable (GroqChatModelId) -> GroqChatLanguageModel
    private let transcriptionModelFactory: @Sendable (GroqTranscriptionModelId) -> GroqTranscriptionModel
    public let tools: GroqTools

    init(
        languageModelFactory: @escaping @Sendable (GroqChatModelId) -> GroqChatLanguageModel,
        transcriptionModelFactory: @escaping @Sendable (GroqTranscriptionModelId) -> GroqTranscriptionModel,
        tools: GroqTools
    ) {
        self.languageModelFactory = languageModelFactory
        self.transcriptionModelFactory = transcriptionModelFactory
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageModelFactory(GroqChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        languageModelFactory(GroqChatModelId(rawValue: modelId))
    }

    public func chat(modelId: GroqChatModelId) -> GroqChatLanguageModel {
        languageModelFactory(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func transcription(modelId: GroqTranscriptionModelId) -> GroqTranscriptionModel {
        transcriptionModelFactory(modelId)
    }

    public func transcriptionModel(modelId: String) throws -> any TranscriptionModelV3 {
        transcription(modelId: GroqTranscriptionModelId(rawValue: modelId))
    }
}

private func defaultGroqFetchFunction() -> FetchFunction {
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

private func createGroqAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultGroqFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "GROQ_API_KEY",
            description: "Groq"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}


public func createGroqProvider(settings: GroqProviderSettings = .init()) -> GroqProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.groq.com/openai/v1"

    let headersClosure: @Sendable () -> [String: String?] = {
        var baseHeaders: [String: String?] = [:]
        if let headers = settings.headers {
            for (key, value) in headers {
                baseHeaders[key] = value
            }
        }
        let withUA = withUserAgentSuffix(baseHeaders, "ai-sdk/groq/\(GROQ_PROVIDER_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let fetch = createGroqAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let languageModelFactory: @Sendable (GroqChatModelId) -> GroqChatLanguageModel = { modelId in
        GroqChatLanguageModel(
            modelId: modelId,
            config: GroqChatLanguageModel.Config(
                provider: "groq.chat",
                url: { options in "\(baseURL)\(options.path)" },
                headers: headersClosure,
                fetch: fetch,
                generateId: generateID
            )
        )
    }

    let transcriptionFactory: @Sendable (GroqTranscriptionModelId) -> GroqTranscriptionModel = { modelId in
        GroqTranscriptionModel(
            modelId: modelId,
            config: GroqTranscriptionModel.Config(
                provider: "groq.transcription",
                url: { options in "\(baseURL)\(options.path)" },
                headers: headersClosure,
                fetch: fetch,
                currentDate: { Date() }
            )
        )
    }

    return GroqProvider(
        languageModelFactory: languageModelFactory,
        transcriptionModelFactory: transcriptionFactory,
        tools: groqTools
    )
}

/// Alias matching the upstream naming (`createGroq`).
public func createGroq(settings: GroqProviderSettings = .init()) -> GroqProvider {
    createGroqProvider(settings: settings)
}

public let groq = createGroqProvider()
