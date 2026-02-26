import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/elevenlabs/src/elevenlabs-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct ElevenLabsProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class ElevenLabsProvider: ProviderV3 {
    private let transcriptionFactory: @Sendable (ElevenLabsTranscriptionModelId) -> ElevenLabsTranscriptionModel
    private let speechFactory: @Sendable (ElevenLabsSpeechModelId) -> ElevenLabsSpeechModel

    init(
        transcriptionFactory: @escaping @Sendable (ElevenLabsTranscriptionModelId) -> ElevenLabsTranscriptionModel,
        speechFactory: @escaping @Sendable (ElevenLabsSpeechModelId) -> ElevenLabsSpeechModel
    ) {
        self.transcriptionFactory = transcriptionFactory
        self.speechFactory = speechFactory
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
        transcription(modelId: ElevenLabsTranscriptionModelId(rawValue: modelId))
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV3)? {
        speech(modelId: ElevenLabsSpeechModelId(rawValue: modelId))
    }

    public func transcription(modelId: ElevenLabsTranscriptionModelId) -> ElevenLabsTranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func speech(modelId: ElevenLabsSpeechModelId) -> ElevenLabsSpeechModel {
        speechFactory(modelId)
    }

    public func callAsFunction(_ modelId: ElevenLabsTranscriptionModelId) -> ElevenLabsTranscriptionModel {
        transcription(modelId: modelId)
    }
}

private func defaultElevenLabsFetchFunction() -> FetchFunction {
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

private func createElevenLabsAuthFetch(apiKey: String?, customFetch: FetchFunction?) -> FetchFunction {
    let baseFetch = customFetch ?? defaultElevenLabsFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasApiKey = headers.keys.contains { $0.lowercased() == "xi-api-key" }
        if !hasApiKey {
            let resolved = try loadAPIKey(
                apiKey: apiKey,
                environmentVariableName: "ELEVENLABS_API_KEY",
                description: "ElevenLabs"
            )
            headers["xi-api-key"] = resolved
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createElevenLabsProvider(settings: ElevenLabsProviderSettings = .init()) -> ElevenLabsProvider {
    let fetch = createElevenLabsAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]
        if let custom = settings.headers {
            for (key, value) in custom {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed, "ai-sdk/elevenlabs/\(ELEVENLABS_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let makeConfig: @Sendable (_ provider: String) -> ElevenLabsConfig = { provider in
        ElevenLabsConfig(
            provider: provider,
            url: { options in
                "https://api.elevenlabs.io\(options.path)"
            },
            headers: headersClosure,
            fetch: fetch,
            currentDate: { Date() }
        )
    }

    let transcriptionFactory: @Sendable (ElevenLabsTranscriptionModelId) -> ElevenLabsTranscriptionModel = { modelId in
        ElevenLabsTranscriptionModel(modelId: modelId, config: makeConfig("elevenlabs.transcription"))
    }

    let speechFactory: @Sendable (ElevenLabsSpeechModelId) -> ElevenLabsSpeechModel = { modelId in
        ElevenLabsSpeechModel(modelId: modelId, config: makeConfig("elevenlabs.speech"))
    }

    return ElevenLabsProvider(
        transcriptionFactory: transcriptionFactory,
        speechFactory: speechFactory
    )
}

/// Alias matching upstream naming (`createElevenLabs`).
public func createElevenLabs(settings: ElevenLabsProviderSettings = .init()) -> ElevenLabsProvider {
    createElevenLabsProvider(settings: settings)
}

public let elevenlabs = createElevenLabsProvider()
