import Foundation

/**
 Video generation model specification version 4.

 Port of `@ai-sdk/provider/src/video-model/v4/video-model-v4.ts`.
 */
public protocol VideoModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }
    var maxVideosPerCall: VideoModelV4MaxVideosPerCall { get }

    func doGenerate(options: VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult
}

extension VideoModelV4 {
    public var specificationVersion: String { "v4" }
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
