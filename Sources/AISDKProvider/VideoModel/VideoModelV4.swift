import Foundation

/**
 Video generation model specification version 4.

 Generation itself is an optional capability, as upstream: a model conforms to
 `VideoModelV4Generator` (`doGenerate`), to `VideoModelV4Operations`
 (`doStart`/`doStatus`), or to both. `VideoModelV4WebhookHandler` signals native
 webhook support for the start/status flow.

 Port of `@ai-sdk/provider/src/video-model/v4/video-model-v4.ts`.
 */
public protocol VideoModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }
    var maxVideosPerCall: VideoModelV4MaxVideosPerCall { get }
}

extension VideoModelV4 {
    public var specificationVersion: String { "v4" }
}

/// A video model that generates videos in one call.
public protocol VideoModelV4Generator: VideoModelV4 {
    func doGenerate(options: VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult
}

/**
 A video model that supports the asynchronous start/status flow, so the SDK
 core can orchestrate polling or webhook completion.
 */
public protocol VideoModelV4Operations: VideoModelV4 {
    /// Starts a generation and returns an opaque operation reference for `doStatus`.
    /// When `webhookUrl` is set, the provider registers it for a completion notification.
    func doStart(
        options: VideoModelV4CallOptions,
        webhookUrl: String?
    ) async throws -> VideoModelV4OperationStartResult

    /// Checks the status of a generation started with `doStart`.
    func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult
}

/**
 A video model whose API natively supports webhooks. The SDK invokes the user's
 webhook factory only for such models and falls back to polling otherwise, so no
 webhook endpoint is created for providers that would ignore it.
 */
public protocol VideoModelV4WebhookHandler: VideoModelV4 {
    func handleWebhookOption(
        webhook: @escaping @Sendable () async throws -> VideoModelV4Webhook
    ) async throws -> VideoModelV4WebhookRegistration
}

/// A webhook endpoint created by the user's webhook factory.
public struct VideoModelV4Webhook: Sendable {
    public let url: String
    /// Completes when the endpoint receives the provider's notification.
    public let received: Task<VideoModelV4OperationWebhook, Error>

    public init(url: String, received: Task<VideoModelV4OperationWebhook, Error>) {
        self.url = url
        self.received = received
    }
}

/// The webhook URL forwarded to `doStart`, and the notification the SDK awaits instead of polling.
public struct VideoModelV4WebhookRegistration: Sendable {
    public let webhookUrl: String
    public let received: Task<VideoModelV4OperationWebhook, Error>

    public init(webhookUrl: String, received: Task<VideoModelV4OperationWebhook, Error>) {
        self.webhookUrl = webhookUrl
        self.received = received
    }
}

/**
 A webhook notification received for a video operation.

 Port of `@ai-sdk/provider/src/video-model/v4/video-model-v4-operation-webhook.ts`.
 */
public struct VideoModelV4OperationWebhook: Sendable, Equatable {
    public let headers: [String: String]
    public let body: JSONValue

    public init(headers: [String: String], body: JSONValue) {
        self.headers = headers
        self.body = body
    }
}

/// Options for `VideoModelV4Operations.doStatus`.
public struct VideoModelV4StatusCallOptions: Sendable {
    /// The JSON-serializable operation reference returned by `doStart`.
    public let operation: JSONValue
    public let abortSignal: (@Sendable () -> Bool)?
    public let headers: SharedV4Headers?

    public init(
        operation: JSONValue,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil
    ) {
        self.operation = operation
        self.abortSignal = abortSignal
        self.headers = headers
    }
}

/**
 Result of starting an asynchronous video generation.

 Port of `@ai-sdk/provider/src/video-model/v4/video-model-v4-operation-start-result.ts`.
 */
public struct VideoModelV4OperationStartResult: Sendable {
    /// Opaque, JSON-serializable operation reference passed back to `doStatus`.
    public let operation: JSONValue
    public let warnings: [SharedV4Warning]
    public let providerMetadata: SharedV4ProviderMetadata?
    public let response: VideoModelV4ResponseInfo

    public init(
        operation: JSONValue,
        warnings: [SharedV4Warning] = [],
        providerMetadata: SharedV4ProviderMetadata? = nil,
        response: VideoModelV4ResponseInfo
    ) {
        self.operation = operation
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.response = response
    }
}

/**
 Status of an asynchronous video generation.

 Port of `@ai-sdk/provider/src/video-model/v4/video-model-v4-operation-status-result.ts`.
 */
public enum VideoModelV4OperationStatusResult: Sendable {
    case pending(
        warnings: [SharedV4Warning]?,
        providerMetadata: SharedV4ProviderMetadata?,
        response: VideoModelV4ResponseInfo
    )
    case completed(
        videos: [VideoModelV4VideoData],
        warnings: [SharedV4Warning],
        providerMetadata: SharedV4ProviderMetadata?,
        response: VideoModelV4ResponseInfo
    )
    case error(
        error: String,
        providerMetadata: SharedV4ProviderMetadata?,
        response: VideoModelV4ResponseInfo
    )
}

public enum VideoModelV4MaxVideosPerCall: Sendable {
    case value(Int)
    case `default`
    case function(@Sendable (String) async throws -> Int?)
}

public enum VideoModelV4VideoData: Sendable, Equatable {
    case url(url: String, mediaType: String)
    case base64(data: String, mediaType: String)
    case binary(data: Data, mediaType: String)
}

public struct VideoModelV4GenerateResult: Sendable {
    public let videos: [VideoModelV4VideoData]
    public let warnings: [SharedV4Warning]
    public let providerMetadata: SharedV4ProviderMetadata?
    public let response: VideoModelV4ResponseInfo

    public init(
        videos: [VideoModelV4VideoData],
        warnings: [SharedV4Warning] = [],
        providerMetadata: SharedV4ProviderMetadata? = nil,
        response: VideoModelV4ResponseInfo
    ) {
        self.videos = videos
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.response = response
    }
}

public struct VideoModelV4ResponseInfo: Sendable {
    public let timestamp: Date
    public let modelId: String
    public let headers: SharedV4Headers?

    public init(timestamp: Date, modelId: String, headers: SharedV4Headers? = nil) {
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
    }
}
