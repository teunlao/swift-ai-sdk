import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private let AI_GATEWAY_PROTOCOL_VERSION = "0.0.1"

public struct GatewayProviderSettings: Sendable {
    public struct InternalSettings: Sendable {
        public var currentDate: @Sendable () -> Date

        public init(currentDate: @escaping @Sendable () -> Date = { Date() }) {
            self.currentDate = currentDate
        }
    }

    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var metadataCacheRefreshMillis: Int?
    public var _internal: InternalSettings?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        metadataCacheRefreshMillis: Int? = nil,
        _internal: InternalSettings? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.metadataCacheRefreshMillis = metadataCacheRefreshMillis
        self._internal = _internal
    }
}

private struct GatewayAuthToken: Sendable {
    let token: String
    let authMethod: GatewayAuthMethod
}

private struct GatewayAuthContext: Sendable {
    let apiKeyProvided: Bool
    let oidcTokenProvided: Bool
}

actor GatewayMetadataCache {
    private var pendingTask: Task<GatewayFetchMetadataResponse, Error>?
    private var cached: GatewayFetchMetadataResponse?
    private var lastFetch: Date?

    func fetch(
        refreshInterval: TimeInterval,
        currentDate: Date,
        fetcher: @escaping @Sendable () async throws -> GatewayFetchMetadataResponse
    ) async throws -> GatewayFetchMetadataResponse {
        if refreshInterval > 0,
           let cached,
           let lastFetch,
           currentDate.timeIntervalSince(lastFetch) <= refreshInterval {
            return cached
        }

        if let task = pendingTask {
            return try await task.value
        }

        let task = Task { try await fetcher() }
        pendingTask = task

        do {
            let result = try await task.value
            cached = result
            lastFetch = currentDate
            pendingTask = nil
            return result
        } catch {
            pendingTask = nil
            throw error
        }
    }
}

public final class GatewayProvider: ProviderV3 {
    private let languageFactory: @Sendable (GatewayModelId) -> GatewayLanguageModel
    private let embeddingFactory: @Sendable (GatewayEmbeddingModelId) -> GatewayEmbeddingModel
    private let metadataFetcher: GatewayFetchMetadata
    private let metadataCache: GatewayMetadataCache
    private let metadataRefreshInterval: TimeInterval
    private let currentDate: @Sendable () -> Date

    init(
        languageFactory: @escaping @Sendable (GatewayModelId) -> GatewayLanguageModel,
        embeddingFactory: @escaping @Sendable (GatewayEmbeddingModelId) -> GatewayEmbeddingModel,
        metadataFetcher: GatewayFetchMetadata,
        metadataCache: GatewayMetadataCache,
        metadataRefreshInterval: TimeInterval,
        currentDate: @escaping @Sendable () -> Date
    ) {
        self.languageFactory = languageFactory
        self.embeddingFactory = embeddingFactory
        self.metadataFetcher = metadataFetcher
        self.metadataCache = metadataCache
        self.metadataRefreshInterval = metadataRefreshInterval
        self.currentDate = currentDate
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageFactory(GatewayModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(GatewayEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    // MARK: - Convenience

    public func languageModel(modelId: GatewayModelId) -> GatewayLanguageModel {
        languageFactory(modelId)
    }

    public func textEmbedding(modelId: GatewayEmbeddingModelId) -> GatewayEmbeddingModel {
        embeddingFactory(modelId)
    }

    // MARK: - Metadata

    public func getAvailableModels() async throws -> GatewayFetchMetadataResponse {
        try await metadataCache.fetch(
            refreshInterval: metadataRefreshInterval,
            currentDate: currentDate(),
            fetcher: { [metadataFetcher] in try await metadataFetcher.getAvailableModels() }
        )
    }

    public func getCredits() async throws -> GatewayCreditsResponse {
        try await metadataFetcher.getCredits()
    }
}

public func createGatewayProvider(settings: GatewayProviderSettings = .init()) -> GatewayProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://ai-gateway.vercel.sh/v1/ai"
    let fetch = settings.fetch
    let currentDateClosure: @Sendable () -> Date
    if let custom = settings._internal?.currentDate {
        currentDateClosure = custom
    } else {
        currentDateClosure = { Date() }
    }
    let refreshInterval = TimeInterval(settings.metadataCacheRefreshMillis ?? (1000 * 60 * 5)) / 1000

    let getHeadersClosure = makeHeaderClosure(settings: settings)

    let o11yHeaders: @Sendable () async throws -> [String: String?] = {
        var headers: [String: String?] = [:]
        if let deploymentId = loadOptionalSetting(settingValue: nil, environmentVariableName: "VERCEL_DEPLOYMENT_ID") {
            headers["ai-o11y-deployment-id"] = deploymentId
        }
        if let environment = loadOptionalSetting(settingValue: nil, environmentVariableName: "VERCEL_ENV") {
            headers["ai-o11y-environment"] = environment
        }
        if let region = loadOptionalSetting(settingValue: nil, environmentVariableName: "VERCEL_REGION") {
            headers["ai-o11y-region"] = region
        }
        if let requestId = await getVercelRequestId() {
            headers["ai-o11y-request-id"] = requestId
        }
        return headers
    }

    let languageConfig = GatewayLanguageModelConfig(
        provider: "gateway",
        baseURL: baseURL,
        headers: getHeadersClosure,
        fetch: fetch,
        o11yHeaders: o11yHeaders
    )

    let embeddingConfig = GatewayEmbeddingModelConfig(
        provider: "gateway",
        baseURL: baseURL,
        headers: getHeadersClosure,
        fetch: fetch,
        o11yHeaders: o11yHeaders
    )

    let metadataConfig = GatewayConfig(
        baseURL: baseURL,
        headers: getHeadersClosure,
        fetch: fetch
    )

    let metadataFetcher = GatewayFetchMetadata(config: metadataConfig)
    let metadataCache = GatewayMetadataCache()

    let languageFactory: @Sendable (GatewayModelId) -> GatewayLanguageModel = { modelId in
        GatewayLanguageModel(modelId: modelId, config: languageConfig)
    }

    let embeddingFactory: @Sendable (GatewayEmbeddingModelId) -> GatewayEmbeddingModel = { modelId in
        GatewayEmbeddingModel(modelId: modelId, config: embeddingConfig)
    }

    return GatewayProvider(
        languageFactory: languageFactory,
        embeddingFactory: embeddingFactory,
        metadataFetcher: metadataFetcher,
        metadataCache: metadataCache,
        metadataRefreshInterval: refreshInterval,
        currentDate: currentDateClosure
    )
}

public let gateway = createGatewayProvider()

// MARK: - Header Helpers

private func makeHeaderClosure(settings: GatewayProviderSettings) -> (@Sendable () async throws -> [String: String?]) {
    @Sendable func headers() async throws -> [String: String?] {
        let (authToken, context, cause) = await resolveAuthToken(settings: settings)

        guard let authToken else {
            throw GatewayAuthenticationError.createContextualError(
                apiKeyProvided: context.apiKeyProvided,
                oidcTokenProvided: context.oidcTokenProvided,
                statusCode: 401,
                cause: cause
            )
        }

        var headerMap: [String: String?] = [
            "Authorization": "Bearer \(authToken.token)",
            "ai-gateway-protocol-version": AI_GATEWAY_PROTOCOL_VERSION,
            GATEWAY_AUTH_METHOD_HEADER: authToken.authMethod.rawValue
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                headerMap[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headerMap, "ai-sdk/gateway/\(GATEWAY_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    return headers
}

private func resolveAuthToken(settings: GatewayProviderSettings) async -> (GatewayAuthToken?, GatewayAuthContext, Error?) {
    var context = GatewayAuthContext(apiKeyProvided: false, oidcTokenProvided: false)

    if let apiKey = loadOptionalSetting(settingValue: settings.apiKey, environmentVariableName: "AI_GATEWAY_API_KEY"), !apiKey.isEmpty {
        context = GatewayAuthContext(apiKeyProvided: true, oidcTokenProvided: false)
        return (GatewayAuthToken(token: apiKey, authMethod: .apiKey), context, nil)
    }

    do {
        let token = try await getVercelOidcToken()
        context = GatewayAuthContext(apiKeyProvided: false, oidcTokenProvided: true)
        return (GatewayAuthToken(token: token, authMethod: .oidc), context, nil)
    } catch {
        return (nil, context, error)
    }
}
