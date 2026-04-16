import Foundation

/**
 Result of uploading a file via the files interface.

 Port of `@ai-sdk/provider/src/files/v4/files-v4-upload-file-result.ts`.
 */
public struct FilesV4UploadFileResult: Sendable, Equatable {
    public let providerReference: SharedV4ProviderReference
    public let mediaType: String?
    public let filename: String?
    public let providerMetadata: SharedV4ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        providerReference: SharedV4ProviderReference,
        mediaType: String? = nil,
        filename: String? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.providerReference = providerReference
        self.mediaType = mediaType
        self.filename = filename
        self.providerMetadata = providerMetadata
        self.warnings = warnings
    }
}
