import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Settings for configuring the LMNT provider.
/// Mirrors `packages/lmnt/src/lmnt-provider.ts`.
public struct LMNTProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class LMNTProvider: ProviderV3 {
    private let speechFactory: @Sendable (LMNTSpeechModelId) -> LMNTSpeechModel

    init(speechFactory: @escaping @Sendable (LMNTSpeechModelId) -> LMNTSpeechModel) {
        self.speechFactory = speechFactory
    }

    // ProviderV3
    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV3)? {
        speechFactory(LMNTSpeechModelId(rawValue: modelId))
    }

    // Convenience
    public func callAsFunction(_ modelId: LMNTSpeechModelId) -> LMNTSpeechModel {
        speechFactory(modelId)
    }

    public func speech(_ modelId: LMNTSpeechModelId) -> LMNTSpeechModel {
        speechFactory(modelId)
    }
}

/// Create an LMNT provider instance.
public func createLMNT(settings: LMNTProviderSettings = .init()) -> LMNTProvider {
    func defaultLMNTFetchFunction() -> FetchFunction {
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

    func createLMNTAuthFetch(apiKey: String?, customFetch: FetchFunction?) -> FetchFunction {
        let baseFetch = customFetch ?? defaultLMNTFetchFunction()

        return { request in
            var modified = request
            var headers = modified.allHTTPHeaderFields ?? [:]

            let hasAPIKey = headers.keys.contains { $0.lowercased() == "x-api-key" }
            if !hasAPIKey {
                let resolved = try loadAPIKey(
                    apiKey: apiKey,
                    environmentVariableName: "LMNT_API_KEY",
                    description: "LMNT"
                )
                headers["x-api-key"] = resolved
                modified.allHTTPHeaderFields = headers
            }

            return try await baseFetch(modified)
        }
    }

    let fetch = createLMNTAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let headersClosure: @Sendable () -> [String: String?] = {
        var base: [String: String?] = [:]
        if let custom = settings.headers {
            for (k, v) in custom { base[k] = v }
        }
        let withUA = withUserAgentSuffix(base, "ai-sdk/lmnt/\(LMNT_PROVIDER_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let factory: @Sendable (LMNTSpeechModelId) -> LMNTSpeechModel = { modelId in
        LMNTSpeechModel(
            modelId,
            config: LMNTConfig(
                provider: "lmnt.speech",
                url: { opts in "https://api.lmnt.com\(opts.path)" },
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    return LMNTProvider(speechFactory: factory)
}

/// Default LMNT provider instance.
public let lmnt = createLMNT()
