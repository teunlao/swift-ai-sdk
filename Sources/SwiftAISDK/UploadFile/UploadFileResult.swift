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
    var byteSize: Double? { get }
    var createdAt: Date? { get }
    var expiresAt: Date? { get }
    var providerMetadata: ProviderMetadata? { get }
    var warnings: [SharedV4Warning] { get }
}

public struct DefaultUploadFileResult: UploadFileResult, Equatable {
    public let providerReference: ProviderReference
    public let mediaType: String?
    public let filename: String?
    public let byteSize: Double?
    public let createdAt: Date?
    public let expiresAt: Date?
    public let providerMetadata: ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        providerReference: ProviderReference,
        mediaType: String? = nil,
        filename: String? = nil,
        byteSize: Double? = nil,
        createdAt: Date? = nil,
        expiresAt: Date? = nil,
        providerMetadata: ProviderMetadata? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.providerReference = providerReference
        self.mediaType = mediaType
        self.filename = filename
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.providerMetadata = providerMetadata
        self.warnings = warnings
    }
}
