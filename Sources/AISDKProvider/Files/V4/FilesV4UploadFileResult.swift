import Foundation

/**
 Result of uploading a file via the files interface.

 Port of `@ai-sdk/provider/src/files/v4/files-v4-upload-file-result.ts`.
 */
public struct FilesV4UploadFileResult: Sendable, Equatable {
    /// Maps the canonical provider name (e.g. `openai`, which may differ from the
    /// interface's `provider` id such as `openai.files`) to the provider's file id.
    public let providerReference: SharedV4ProviderReference
    public let mediaType: String?
    public let filename: String?
    /// Size of the uploaded file in bytes, if reported.
    public let byteSize: Int?
    /// When the file was created, if reported.
    public let createdAt: Date?
    /// When the provider will delete the file (retention expiry), if reported.
    public let expiresAt: Date?
    public let providerMetadata: SharedV4ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        providerReference: SharedV4ProviderReference,
        mediaType: String? = nil,
        filename: String? = nil,
        byteSize: Int? = nil,
        createdAt: Date? = nil,
        expiresAt: Date? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil,
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
