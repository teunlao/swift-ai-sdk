import Foundation

/**
 Options for operations on a previously uploaded file: metadata reads,
 content downloads and deletion.

 Port of `files-v4-get-file-metadata-call-options.ts`,
 `files-v4-download-file-call-options.ts` and `files-v4-delete-file-call-options.ts`,
 which share one shape upstream.
 */
public struct FilesV4FileCallOptions: Sendable {
    /// Provider reference of the file, as returned by `uploadFile`.
    public let file: SharedV4ProviderReference
    public let abortSignal: (@Sendable () -> Bool)?
    /// Additional HTTP headers. Only applicable for HTTP-based providers.
    public let headers: SharedV4Headers?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        file: SharedV4ProviderReference,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.file = file
        self.abortSignal = abortSignal
        self.headers = headers
        self.providerOptions = providerOptions
    }
}

public typealias FilesV4GetFileMetadataCallOptions = FilesV4FileCallOptions
public typealias FilesV4DownloadFileCallOptions = FilesV4FileCallOptions
public typealias FilesV4DeleteFileCallOptions = FilesV4FileCallOptions

/**
 Metadata of a previously uploaded file.

 Port of `@ai-sdk/provider/src/files/v4/files-v4-get-file-metadata-result.ts`.
 */
public struct FilesV4GetFileMetadataResult: Sendable, Equatable {
    public let providerReference: SharedV4ProviderReference
    public let filename: String?
    public let mediaType: String?
    public let byteSize: Int?
    public let createdAt: Date?
    public let expiresAt: Date?
    public let providerMetadata: SharedV4ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        providerReference: SharedV4ProviderReference,
        filename: String? = nil,
        mediaType: String? = nil,
        byteSize: Int? = nil,
        createdAt: Date? = nil,
        expiresAt: Date? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.providerReference = providerReference
        self.filename = filename
        self.mediaType = mediaType
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.providerMetadata = providerMetadata
        self.warnings = warnings
    }
}

/**
 Content of a previously uploaded file. The consumer drains or drops `content`.

 Port of `@ai-sdk/provider/src/files/v4/files-v4-download-file-result.ts`.
 */
public struct FilesV4DownloadFileResult: Sendable {
    public let content: AsyncThrowingStream<Data, Error>
    public let mediaType: String?
    public let providerMetadata: SharedV4ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        content: AsyncThrowingStream<Data, Error>,
        mediaType: String? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.content = content
        self.mediaType = mediaType
        self.providerMetadata = providerMetadata
        self.warnings = warnings
    }
}

/**
 Result of deleting a previously uploaded file.

 Port of `@ai-sdk/provider/src/files/v4/files-v4-delete-file-result.ts`.
 */
public struct FilesV4DeleteFileResult: Sendable, Equatable {
    public let providerReference: SharedV4ProviderReference
    public let deleted: Bool
    public let providerMetadata: SharedV4ProviderMetadata?
    public let warnings: [SharedV4Warning]

    public init(
        providerReference: SharedV4ProviderReference,
        deleted: Bool,
        providerMetadata: SharedV4ProviderMetadata? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.providerReference = providerReference
        self.deleted = deleted
        self.providerMetadata = providerMetadata
        self.warnings = warnings
    }
}
