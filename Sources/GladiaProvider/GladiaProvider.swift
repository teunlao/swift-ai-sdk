import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gladia/src/gladia-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GladiaTranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public extension GladiaTranscriptionModelId {
    static let `default`: Self = "default"
}

public struct GladiaProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
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

public final class GladiaProvider: ProviderV3 {
    public struct Models: Sendable {
        public let transcription: GladiaTranscriptionModel
    }

    private let transcriptionFactory: @Sendable (GladiaTranscriptionModelId) -> GladiaTranscriptionModel

    init(transcriptionFactory: @escaping @Sendable (GladiaTranscriptionModelId) -> GladiaTranscriptionModel) {
        self.transcriptionFactory = transcriptionFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .languageModel,
            message: "Gladia does not provide language models"
        )
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .textEmbeddingModel,
            message: "Gladia does not provide text embedding models"
        )
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(
            modelId: modelId,
            modelType: .imageModel,
            message: "Gladia does not provide image models"
        )
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        let identifier = GladiaTranscriptionModelId(rawValue: modelId)
        guard identifier == .default else {
            throw NoSuchModelError(modelId: modelId, modelType: .transcriptionModel)
        }
        return transcription(modelId: identifier)
    }

    public func transcription(modelId: GladiaTranscriptionModelId = .default) -> GladiaTranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func callAsFunction() -> Models {
        Models(transcription: transcription())
    }
}

private func defaultGladiaFetchFunction() -> FetchFunction {
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

private func createGladiaAuthFetch(apiKey: String?, customFetch: FetchFunction?) -> FetchFunction {
    let baseFetch = customFetch ?? defaultGladiaFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasAPIKey = headers.keys.contains { $0.lowercased() == "x-gladia-key" }
        if !hasAPIKey {
            let resolved = try loadAPIKey(
                apiKey: apiKey,
                environmentVariableName: "GLADIA_API_KEY",
                description: "Gladia"
            )
            headers["x-gladia-key"] = resolved
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createGladiaProvider(settings: GladiaProviderSettings = .init()) -> GladiaProvider {
    let fetch = createGladiaAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let headersClosure: @Sendable () -> [String: String?] = {
        var baseHeaders: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                baseHeaders[key] = value
            }
        }

        let withUA = withUserAgentSuffix(baseHeaders.compactMapValues { $0 }, "ai-sdk/gladia/\(GLADIA_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let transcriptionFactory: @Sendable (GladiaTranscriptionModelId) -> GladiaTranscriptionModel = { modelId in
        GladiaTranscriptionModel(
            modelId: modelId.rawValue,
            config: GladiaConfig(
                provider: "gladia.transcription",
                url: { options in
                    "https://api.gladia.io\(options.path)"
                },
                headers: headersClosure,
                fetch: fetch,
                currentDate: { Date() }
            )
        )
    }

    return GladiaProvider(transcriptionFactory: transcriptionFactory)
}

/// Alias matching upstream naming (`createGladia`).
public func createGladia(settings: GladiaProviderSettings = .init()) -> GladiaProvider {
    createGladiaProvider(settings: settings)
}

public let gladia = createGladiaProvider()
