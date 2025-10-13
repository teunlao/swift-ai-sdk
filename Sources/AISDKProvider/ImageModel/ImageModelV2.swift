import Foundation

/**
 Image generation model specification version 2.

 Port of `@ai-sdk/provider/src/image-model/v2/image-model-v2.ts`.
 */
public protocol ImageModelV2: Sendable {
    /**
     The image model must specify which image model interface
     version it implements. This will allow us to evolve the image
     model interface and retain backwards compatibility. The different
     implementation versions can be handled as a discriminated union
     on our side.
     */
    var specificationVersion: String { get }

    /**
     Name of the provider for logging purposes.
     */
    var provider: String { get }

    /**
     Provider-specific model ID for logging purposes.
     */
    var modelId: String { get }

    /**
     Limit of how many images can be generated in a single API call.
     Can be set to a number for a fixed limit, to undefined to use
     the global limit, or a function that returns a number or undefined,
     optionally as a promise.
     */
    var maxImagesPerCall: ImageModelV2MaxImagesPerCall { get }

    /**
     Generates an array of images.

     - Parameter options: Call options for image generation
     - Returns: Result containing generated images, warnings, and metadata
     - Throws: Errors during image generation
     */
    func doGenerate(options: ImageModelV2CallOptions) async throws -> ImageModelV2GenerateResult
}

extension ImageModelV2 {
    /// Default implementation returns "v2"
    public var specificationVersion: String { "v2" }
}

// MARK: - Supporting Types

/// Maximum images per call configuration
public enum ImageModelV2MaxImagesPerCall: Sendable {
    /// Fixed limit
    case value(Int)

    /// Use global/default limit
    case `default`

    /// Function that returns limit (can be sync or async)
    case function(@Sendable (String) async throws -> Int?)
}

/// Generated images representation (either base64 strings or binary data)
public enum ImageModelV2GeneratedImages: Sendable {
    /// Base64 encoded strings
    case base64([String])

    /// Binary data
    case binary([Data])
}

/// Provider-specific metadata for image generation
/// Keyed by provider name, with image-specific metadata including "images" key
public typealias ImageModelV2ProviderMetadata = [String: ImageModelV2ProviderMetadataValue]

/// Provider metadata value with images array and additional data
public struct ImageModelV2ProviderMetadataValue: Sendable {
    /// Image-specific metadata array
    public let images: [JSONValue]

    /// Additional provider-specific data
    public let additionalData: JSONValue?

    public init(images: [JSONValue], additionalData: JSONValue? = nil) {
        self.images = images
        self.additionalData = additionalData
    }
}

/// Result from ImageModelV2 doGenerate call
public struct ImageModelV2GenerateResult: Sendable {
    /// Generated images as base64 encoded strings or binary data
    /// The images should be returned without any unnecessary conversion.
    /// If the API returns base64 encoded strings, return as base64.
    /// If the API returns binary data, return as binary.
    public let images: ImageModelV2GeneratedImages

    /// Warnings for the call, e.g. unsupported settings
    public let warnings: [ImageModelV2CallWarning]

    /// Additional provider-specific metadata
    public let providerMetadata: ImageModelV2ProviderMetadata?

    /// Response information for telemetry and debugging purposes
    public let response: ImageModelV2ResponseInfo

    public init(
        images: ImageModelV2GeneratedImages,
        warnings: [ImageModelV2CallWarning] = [],
        providerMetadata: ImageModelV2ProviderMetadata? = nil,
        response: ImageModelV2ResponseInfo
    ) {
        self.images = images
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.response = response
    }
}

/// Response information for telemetry and debugging
public struct ImageModelV2ResponseInfo: Sendable {
    /// Timestamp for the start of the generated response
    public let timestamp: Date

    /// The ID of the response model that was used to generate the response
    public let modelId: String

    /// Response headers
    public let headers: [String: String]?

    public init(
        timestamp: Date,
        modelId: String,
        headers: [String: String]? = nil
    ) {
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
    }
}
