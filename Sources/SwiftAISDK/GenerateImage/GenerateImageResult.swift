import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Result of an image generation call.

 Port of `@ai-sdk/ai/src/generate-image/generate-image-result.ts`.

 Exposes generated images, warnings, response metadata, and provider-specific
 metadata aggregated across all underlying model calls.
 */
public protocol GenerateImageResult: Sendable {
    /// The first generated image.
    var image: GeneratedFile { get }

    /// All generated images.
    var images: [GeneratedFile] { get }

    /// Provider warnings collected during generation.
    var warnings: [ImageGenerationWarning] { get }

    /// Response metadata for every model call.
    var responses: [ImageModelResponseMetadata] { get }

    /// Provider-specific metadata aggregated across calls.
    var providerMetadata: ImageModelProviderMetadata { get }

    /// Aggregated usage information (if reported by the provider).
    var usage: ImageModelUsage { get }
}

/**
 Default implementation of `GenerateImageResult`.

 Mirrors the upstream `DefaultGenerateImageResult` class.
 */
public final class DefaultGenerateImageResult: GenerateImageResult {
    public let images: [GeneratedFile]
    public let warnings: [ImageGenerationWarning]
    public let responses: [ImageModelResponseMetadata]
    public let providerMetadata: ImageModelProviderMetadata
    public let usage: ImageModelUsage

    /**
     Create a default image generation result.

     - Parameters:
       - images: Generated files.
       - warnings: Provider warnings.
       - responses: Response metadata for each call.
       - providerMetadata: Aggregated provider metadata.
     */
    public init(
        images: [GeneratedFile],
        warnings: [ImageGenerationWarning],
        responses: [ImageModelResponseMetadata],
        providerMetadata: ImageModelProviderMetadata,
        usage: ImageModelUsage = .init()
    ) {
        self.images = images
        self.warnings = warnings
        self.responses = responses
        self.providerMetadata = providerMetadata
        self.usage = usage
    }

    public var image: GeneratedFile {
        images[0]
    }
}
