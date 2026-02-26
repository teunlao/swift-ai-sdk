import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/luma/src/luma-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct LumaProviderSettings: Sendable {
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

public final class LumaProvider: ProviderV3 {
    private let imageFactory: @Sendable (LumaImageModelId) -> LumaImageModel

    init(imageFactory: @escaping @Sendable (LumaImageModelId) -> LumaImageModel) {
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        image(modelId: LumaImageModelId(rawValue: modelId))
    }

    public func image(modelId: LumaImageModelId) -> LumaImageModel {
        imageFactory(modelId)
    }
}

private let defaultLumaBaseURL = "https://api.lumalabs.ai"

private func defaultLumaFetchFunction() -> FetchFunction {
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

private func createLumaAuthFetch(apiKey: String?, customFetch: FetchFunction?) -> FetchFunction {
    let baseFetch = customFetch ?? defaultLumaFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            let resolved = try loadAPIKey(
                apiKey: apiKey,
                environmentVariableName: "LUMA_API_KEY",
                description: "Luma"
            )
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createLumaProvider(settings: LumaProviderSettings = .init()) -> LumaProvider {
    let normalizedBaseURL = withoutTrailingSlash(settings.baseURL ?? defaultLumaBaseURL) ?? defaultLumaBaseURL
    let fetch = createLumaAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let headersClosure: @Sendable () -> [String: String?] = {
        var baseHeaders: [String: String?] = [:]

        if let headers = settings.headers {
            for (key, value) in headers {
                baseHeaders[key] = value
            }
        }

        let withUA = withUserAgentSuffix(baseHeaders, "ai-sdk/luma/\(LUMA_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let imageFactory: @Sendable (LumaImageModelId) -> LumaImageModel = { modelId in
        LumaImageModel(
            modelId: modelId,
            config: LumaImageModelConfig(
                provider: "luma.image",
                baseURL: normalizedBaseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    return LumaProvider(imageFactory: imageFactory)
}

/// Alias matching upstream naming (`createLuma`).
public func createLuma(settings: LumaProviderSettings = .init()) -> LumaProvider {
    createLumaProvider(settings: settings)
}

public let luma = createLumaProvider()
