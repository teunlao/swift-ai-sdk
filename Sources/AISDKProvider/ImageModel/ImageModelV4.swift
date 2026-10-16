import Foundation

/**
 Image generation model specification version 4.

 Port of `@ai-sdk/provider/src/image-model/v4/image-model-v4.ts`.
 */
public protocol ImageModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }
    var maxImagesPerCall: ImageModelV4MaxImagesPerCall { get }

    /// Whether the model supports image file inputs for image editing.
    /// `nil` means support is unknown; callers route editing requests only on `true`.
    var supportsFileInputs: Bool? { get async throws }

    /// Whether the model supports mask inputs for image editing.
    /// `nil` means support is unknown.
    var supportsMaskInputs: Bool? { get async throws }

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult
}

extension ImageModelV4 {
    public var specificationVersion: String { "v4" }

    public var supportsFileInputs: Bool? {
        get async throws { nil }
    }

    public var supportsMaskInputs: Bool? {
        get async throws { nil }
    }
}

public enum ImageModelV4MaxImagesPerCall: Sendable {
    case value(Int)
    case `default`
    case function(@Sendable (String) async throws -> Int?)
}

public enum ImageModelV4GeneratedImages: Sendable, Equatable {
    case base64([String])
    case binary([Data])
}

public typealias ImageModelV4ProviderMetadata = [String: ImageModelV4ProviderMetadataValue]

public struct ImageModelV4ProviderMetadataValue: Sendable {
    public let images: [JSONValue]
    public let additionalData: JSONValue?

    public init(images: [JSONValue], additionalData: JSONValue? = nil) {
        self.images = images
        self.additionalData = additionalData
    }
}

public struct ImageModelV4GenerateResult: Sendable {
    public let images: ImageModelV4GeneratedImages
    /// Whether an unsuccessful result, such as an empty image result, can be
    /// retried. `nil` leaves the result unclassified.
    public let isRetryable: Bool?
    public let warnings: [SharedV4Warning]
    public let providerMetadata: ImageModelV4ProviderMetadata?
    public let response: ImageModelV4ResponseInfo
    public let usage: ImageModelV4Usage?

    public init(
        images: ImageModelV4GeneratedImages,
        isRetryable: Bool? = nil,
        warnings: [SharedV4Warning] = [],
        providerMetadata: ImageModelV4ProviderMetadata? = nil,
        response: ImageModelV4ResponseInfo,
        usage: ImageModelV4Usage? = nil
    ) {
        self.images = images
        self.isRetryable = isRetryable
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.response = response
        self.usage = usage
    }
}

public struct ImageModelV4ResponseInfo: Sendable {
    public let timestamp: Date
    public let modelId: String
    public let headers: SharedV4Headers?

    public init(timestamp: Date, modelId: String, headers: SharedV4Headers? = nil) {
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
    }
}
