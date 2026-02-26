import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/assemblyai/src/assemblyai-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct AssemblyAIProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class AssemblyAIProvider: ProviderV3 {
    private let transcriptionFactory: @Sendable (AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel

    init(transcriptionFactory: @escaping @Sendable (AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel) {
        self.transcriptionFactory = transcriptionFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        transcription(modelId: AssemblyAITranscriptionModelId(rawValue: modelId))
    }

    public func transcription(modelId: AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func callAsFunction(_ modelId: AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel {
        transcription(modelId: modelId)
    }
}

private func defaultAssemblyAIFetchFunction() -> FetchFunction {
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

private func createAssemblyAIAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultAssemblyAIFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "ASSEMBLYAI_API_KEY",
            description: "AssemblyAI"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["authorization"] = resolved
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createAssemblyAIProvider(settings: AssemblyAIProviderSettings = .init()) -> AssemblyAIProvider {
    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]
        if let custom = settings.headers {
            for (key, value) in custom {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed.compactMapValues { $0 }, "ai-sdk/assemblyai/\(ASSEMBLYAI_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let fetch = createAssemblyAIAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let transcriptionFactory: @Sendable (AssemblyAITranscriptionModelId) -> AssemblyAITranscriptionModel = { modelId in
        AssemblyAITranscriptionModel(
            modelId: modelId,
            config: AssemblyAITranscriptionModel.Config(
                provider: "assemblyai.transcription",
                url: { options in
                    "https://api.assemblyai.com\(options.path)"
                },
                headers: headersClosure,
                fetch: fetch,
                currentDate: { Date() }
            )
        )
    }

    return AssemblyAIProvider(transcriptionFactory: transcriptionFactory)
}

/// Alias matching the upstream naming (`createAssemblyAI`).
public func createAssemblyAI(settings: AssemblyAIProviderSettings = .init()) -> AssemblyAIProvider {
    createAssemblyAIProvider(settings: settings)
}

public let assemblyai = createAssemblyAIProvider()
