import Foundation
import AISDKProvider

/**
 Result of uploading a file through the AI SDK.

 Port of `@ai-sdk/ai/src/upload-file/upload-file-result.ts`.
 */
public protocol UploadFileResult: Sendable {
    var providerReference: ProviderReference { get }
    var mediaType: String? { get }
    var filename: String? { get }
    var providerMetadata: ProviderMetadata? { get }
    var warnings: [SharedV4Warning] { get }
}

public struct DefaultUploadFileResult: UploadFileResult, Equatable {
    public let providerReference: ProviderReference
    public let mediaType: String?
    public let filename: String?
    public let providerMetadata: ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        providerReference: ProviderReference,
        mediaType: String? = nil,
        filename: String? = nil,
        providerMetadata: ProviderMetadata? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.providerReference = providerReference
        self.mediaType = mediaType
        self.filename = filename
        self.providerMetadata = providerMetadata
        self.warnings = warnings
    }
}
