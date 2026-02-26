import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/revai/src/revai-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct RevAIProviderSettings: Sendable {
    /// API key for authenticating requests.
    public var apiKey: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation (useful for tests / middleware).
    public var fetch: FetchFunction?

    public init(
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class RevAIProvider: ProviderV3 {
    public struct Models: Sendable {
        public let transcription: RevAITranscriptionModel
    }

    private let transcriptionFactory: @Sendable (RevAITranscriptionModelId) -> RevAITranscriptionModel

    init(transcriptionFactory: @escaping @Sendable (RevAITranscriptionModelId) -> RevAITranscriptionModel) {
        self.transcriptionFactory = transcriptionFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .languageModel,
            message: "Rev.ai does not provide language models"
        )
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .textEmbeddingModel,
            message: "Rev.ai does not provide text embedding models"
        )
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .imageModel,
            message: "Rev.ai does not provide image models"
        )
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        let identifier = RevAITranscriptionModelId(rawValue: modelId)
        guard identifier == .machine || identifier == .lowCost || identifier == .fusion else {
            throw NoSuchModelError(modelId: modelId, modelType: .transcriptionModel)
        }
        return transcription(modelId: identifier)
    }

    public func transcription(modelId: RevAITranscriptionModelId = .machine) -> RevAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func transcription(_ modelId: RevAITranscriptionModelId = .machine) -> RevAITranscriptionModel {
        transcription(modelId: modelId)
    }

    public func callAsFunction(_ modelId: RevAITranscriptionModelId = .machine) -> Models {
        Models(transcription: transcription(modelId: modelId))
    }
}

private func defaultRevAIFetchFunction() -> FetchFunction {
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

private func createRevAIAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultRevAIFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "REVAI_API_KEY",
            description: "Rev.ai"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createRevAIProvider(settings: RevAIProviderSettings = .init()) -> RevAIProvider {
    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk/revai/\(REVAI_VERSION)"
        )
        return withUA.mapValues { Optional($0) }
    }

    let fetch = createRevAIAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let transcriptionFactory: @Sendable (RevAITranscriptionModelId) -> RevAITranscriptionModel = { modelId in
        RevAITranscriptionModel(
            modelId: modelId,
            config: RevAIConfig(
                provider: "revai.transcription",
                url: { options in "https://api.rev.ai\(options.path)" },
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    return RevAIProvider(transcriptionFactory: transcriptionFactory)
}

/// Alias matching upstream naming (`createRevai`).
public func createRevai(settings: RevAIProviderSettings = .init()) -> RevAIProvider {
    createRevAIProvider(settings: settings)
}

public let revai = createRevAIProvider()
