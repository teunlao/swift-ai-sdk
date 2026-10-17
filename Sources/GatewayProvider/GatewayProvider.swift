import Foundation
import AISDKProvider
import AISDKProviderUtils

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
    public var teamIdOrSlug: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var webSocket: WebSocketConstructor?
    public var metadataCacheRefreshMillis: Int?
    public var _internal: InternalSettings?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        teamIdOrSlug: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        webSocket: WebSocketConstructor? = nil,
        metadataCacheRefreshMillis: Int? = nil,
        _internal: InternalSettings? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.teamIdOrSlug = teamIdOrSlug
        self.headers = headers
        self.fetch = fetch
        self.webSocket = webSocket
        self.metadataCacheRefreshMillis = metadataCacheRefreshMillis
        self._internal = _internal
    }
}

public struct GatewayAuthToken: Sendable {
    public let token: String
    public let authMethod: GatewayAuthMethod

    public init(token: String, authMethod: GatewayAuthMethod) {
        self.token = token
        self.authMethod = authMethod
    }
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
        if pendingTask == nil || currentDate.timeIntervalSince(lastFetch ?? .distantPast) > refreshInterval {
            lastFetch = currentDate
            pendingTask = Task {
                let result = try await fetcher()
                self.cached = result
                return result
            }
        }
        if let cached { return cached }
        return try await pendingTask!.value
    }
}

public final class GatewayProvider: ProviderV4, VideoProviderV4 {
    private let languageFactory: @Sendable (GatewayModelId) -> GatewayLanguageModel
    private let embeddingFactory: @Sendable (GatewayEmbeddingModelId) -> GatewayEmbeddingModel
    private let imageFactory: @Sendable (GatewayImageModelId) -> GatewayImageModel
    private let videoFactory: @Sendable (GatewayVideoModelId) -> GatewayVideoModel
    private let metadataFetcher: GatewayFetchMetadata
    private let metadataCache: GatewayMetadataCache
    private let metadataRefreshInterval: TimeInterval
    private let currentDate: @Sendable () -> Date
    private let modelConfig: @Sendable () -> GatewayModelConfig
    private let metadataConfig: GatewayConfig
    private let teamIdOrSlug: String?
    private let webSocket: WebSocketConstructor?
    public var experimental_transcription: GatewayTranscriptionFactory { .init(config: modelConfig, metadataConfig: metadataConfig, webSocket: webSocket) }
    public var experimental_realtime: GatewayRealtimeFactory { .init(config: metadataConfig, teamIdOrSlug: teamIdOrSlug) }
    public let tools: GatewayTools

    init(
        languageFactory: @escaping @Sendable (GatewayModelId) -> GatewayLanguageModel,
        embeddingFactory: @escaping @Sendable (GatewayEmbeddingModelId) -> GatewayEmbeddingModel,
        imageFactory: @escaping @Sendable (GatewayImageModelId) -> GatewayImageModel,
        videoFactory: @escaping @Sendable (GatewayVideoModelId) -> GatewayVideoModel,
        tools: GatewayTools,
        metadataFetcher: GatewayFetchMetadata,
        metadataCache: GatewayMetadataCache,
        metadataRefreshInterval: TimeInterval,
        currentDate: @escaping @Sendable () -> Date,
        modelConfig: @escaping @Sendable () -> GatewayModelConfig,
        metadataConfig: GatewayConfig,
        teamIdOrSlug: String?,
        webSocket: WebSocketConstructor?
    ) {
        self.languageFactory = languageFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
        self.videoFactory = videoFactory
        self.tools = tools
        self.metadataFetcher = metadataFetcher
        self.metadataCache = metadataCache
        self.metadataRefreshInterval = metadataRefreshInterval
        self.currentDate = currentDate
        self.modelConfig = modelConfig
        self.metadataConfig = metadataConfig
        self.teamIdOrSlug = teamIdOrSlug
        self.webSocket = webSocket
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        languageFactory(GatewayModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embeddingFactory(GatewayEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        imageFactory(GatewayImageModelId(rawValue: modelId))
    }

    public func videoModel(modelId: String) throws -> any VideoModelV4 {
        videoFactory(GatewayVideoModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    // MARK: - Convenience

    public func languageModel(modelId: GatewayModelId) -> GatewayLanguageModel {
        languageFactory(modelId)
    }

    public func embeddingModel(modelId: GatewayEmbeddingModelId) -> GatewayEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func imageModel(modelId: GatewayImageModelId) -> GatewayImageModel {
        imageFactory(modelId)
    }

    public func videoModel(modelId: GatewayVideoModelId) -> GatewayVideoModel {
        videoFactory(modelId)
    }

    public func chat(modelId: String) -> GatewayLanguageModel {
        languageFactory(.init(rawValue: modelId))
    }

    public func embedding(modelId: String) -> GatewayEmbeddingModel {
        embeddingFactory(.init(rawValue: modelId))
    }

    public func image(modelId: String) -> GatewayImageModel {
        imageFactory(.init(rawValue: modelId))
    }

    public func video(modelId: String) -> GatewayVideoModel {
        videoFactory(.init(rawValue: modelId))
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        transcription(modelId: modelId)
    }

    public func transcriptionModel(modelId: GatewayTranscriptionModelId) -> GatewayTranscriptionModel {
        transcription(modelId: modelId.rawValue)
    }

    public func transcription(modelId: String) -> GatewayTranscriptionModel {
        experimental_transcription(modelId)
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        speech(modelId: modelId)
    }

    public func speechModel(modelId: GatewaySpeechModelId) -> GatewaySpeechModel {
        speech(modelId: modelId.rawValue)
    }

    public func speech(modelId: String) -> GatewaySpeechModel {
        GatewaySpeechModel(modelId: modelId, config: modelConfig())
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV4)? {
        reranking(modelId: modelId)
    }

    public func rerankingModel(modelId: GatewayRerankingModelId) -> GatewayRerankingModel {
        reranking(modelId: modelId.rawValue)
    }

    public func reranking(modelId: String) -> GatewayRerankingModel {
        GatewayRerankingModel(modelId: modelId, config: modelConfig())
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

    public func getSpendReport(_ params: GatewaySpendReportParams) async throws -> GatewaySpendReportResponse {
        try await GatewaySpendReport(config: metadataConfig).getSpendReport(params)
    }

    public func getGenerationInfo(_ params: GatewayGenerationInfoParams) async throws -> GatewayGenerationInfo {
        try await GatewayGenerationInfoFetcher(config: metadataConfig).getGenerationInfo(params)
    }
}

public func createGateway(settings: GatewayProviderSettings = .init()) -> GatewayProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://ai-gateway.vercel.sh/v4/ai"
    let fetch = settings.fetch
    let currentDateClosure: @Sendable () -> Date
    if let custom = settings._internal?.currentDate {
        currentDateClosure = custom
    } else {
        currentDateClosure = { Date() }
    }
    let refreshInterval = TimeInterval(settings.metadataCacheRefreshMillis ?? (1000 * 60 * 5)) / 1000

    let getHeadersClosure = makeHeaderClosure(settings: settings)

    @Sendable func o11yHeaders() -> (@Sendable () async throws -> [String: String?]) {
        let values = [
            ("ai-o11y-deployment-id", "VERCEL_DEPLOYMENT_ID"), ("ai-o11y-environment", "VERCEL_ENV"),
            ("ai-o11y-region", "VERCEL_REGION"), ("ai-o11y-project-id", "VERCEL_PROJECT_ID")
        ]
        let captured = values.reduce(into: [String: String?]()) { headers, entry in
            if let value = loadOptionalSetting(settingValue: nil, environmentVariableName: entry.1), !value.isEmpty {
                headers[entry.0] = value
            }
        }
        return {
            var headers = captured
            if let requestId = await getVercelRequestId(), !requestId.isEmpty { headers["ai-o11y-request-id"] = requestId }
            return headers
        }
    }

    let metadataConfig = GatewayConfig(
        baseURL: baseURL,
        headers: getHeadersClosure,
        fetch: fetch
    )

    let metadataFetcher = GatewayFetchMetadata(config: metadataConfig)
    let metadataCache = GatewayMetadataCache()

    let languageFactory: @Sendable (GatewayModelId) -> GatewayLanguageModel = { modelId in
        GatewayLanguageModel(modelId: modelId, config: .init(provider: "gateway", baseURL: baseURL, headers: getHeadersClosure, fetch: fetch, o11yHeaders: o11yHeaders()))
    }

    let embeddingFactory: @Sendable (GatewayEmbeddingModelId) -> GatewayEmbeddingModel = { modelId in
        GatewayEmbeddingModel(modelId: modelId, config: .init(provider: "gateway", baseURL: baseURL, headers: getHeadersClosure, fetch: fetch, o11yHeaders: o11yHeaders()))
    }

    let imageFactory: @Sendable (GatewayImageModelId) -> GatewayImageModel = { modelId in
        GatewayImageModel(modelId: modelId, config: .init(provider: "gateway", baseURL: baseURL, headers: getHeadersClosure, fetch: fetch, o11yHeaders: o11yHeaders()))
    }

    let videoFactory: @Sendable (GatewayVideoModelId) -> GatewayVideoModel = { modelId in
        GatewayVideoModel(modelId: modelId, config: .init(provider: "gateway", baseURL: baseURL, headers: getHeadersClosure, fetch: fetch, o11yHeaders: o11yHeaders()))
    }

    return GatewayProvider(
        languageFactory: languageFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory,
        videoFactory: videoFactory,
        tools: gatewayTools,
        metadataFetcher: metadataFetcher,
        metadataCache: metadataCache,
        metadataRefreshInterval: refreshInterval,
        currentDate: currentDateClosure,
        modelConfig: { GatewayModelConfig(provider: "gateway", baseURL: baseURL, headers: getHeadersClosure, fetch: fetch, o11yHeaders: o11yHeaders(), currentDate: currentDateClosure) },
        metadataConfig: metadataConfig,
        teamIdOrSlug: settings.teamIdOrSlug,
        webSocket: settings.webSocket
    )
}

public let gateway = createGateway()

/// Resolves the Gateway auth token using the same precedence as upstream:
/// 1) `settings.apiKey` / `AI_GATEWAY_API_KEY`
/// 2) Vercel OIDC token (`VERCEL_OIDC_TOKEN`)
public func getGatewayAuthToken(settings: GatewayProviderSettings) async throws -> GatewayAuthToken {
    if let apiKey = loadOptionalSetting(settingValue: settings.apiKey, environmentVariableName: "AI_GATEWAY_API_KEY"), !apiKey.isEmpty {
        return GatewayAuthToken(token: apiKey, authMethod: .apiKey)
    }

    let oidcToken = try await getVercelOidcToken()
    return GatewayAuthToken(token: oidcToken, authMethod: .oidc)
}

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

        if let teamIdOrSlug = settings.teamIdOrSlug {
            headerMap["x-vercel-ai-gateway-team"] = teamIdOrSlug
        }

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                headerMap[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headerMap, "ai-sdk-gateway/\(GATEWAY_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    return headers
}

private func resolveAuthToken(settings: GatewayProviderSettings) async -> (GatewayAuthToken?, GatewayAuthContext, Error?) {
    do {
        let token = try await getGatewayAuthToken(settings: settings)
        let context = GatewayAuthContext(
            apiKeyProvided: token.authMethod == .apiKey,
            oidcTokenProvided: token.authMethod == .oidc
        )
        return (token, context, nil)
    } catch {
        return (nil, GatewayAuthContext(apiKeyProvided: false, oidcTokenProvided: false), error)
    }
}
