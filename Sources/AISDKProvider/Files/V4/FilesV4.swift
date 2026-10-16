/**
 Specification for a file management interface that implements files interface version 4.

 Only `uploadFile` is required. Metadata reads, downloads and deletion are
 optional capabilities: conforming to `FilesV4MetadataReader`, `FilesV4Downloader`
 or `FilesV4Deleter` signals that the provider supports them, mirroring the
 optional methods of the upstream interface.

 Port of `@ai-sdk/provider/src/files/v4/files-v4.ts`.
 */
public protocol FilesV4: Sendable {
    /// Files interface version discriminator.
    var specificationVersion: String { get }

    /// Provider identifier.
    var provider: String { get }

    /// Uploads a file and returns a provider reference.
    func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult
}

/// A files interface that can read the metadata of a previously uploaded file.
public protocol FilesV4MetadataReader: FilesV4 {
    func getFileMetadata(options: FilesV4GetFileMetadataCallOptions) async throws -> FilesV4GetFileMetadataResult
}

/// A files interface that can download the content of a previously uploaded file.
public protocol FilesV4Downloader: FilesV4 {
    func downloadFile(options: FilesV4DownloadFileCallOptions) async throws -> FilesV4DownloadFileResult
}

/// A files interface that can delete a previously uploaded file.
public protocol FilesV4Deleter: FilesV4 {
    func deleteFile(options: FilesV4DeleteFileCallOptions) async throws -> FilesV4DeleteFileResult
}

/**
 Provider capability marker for providers that expose a v4 files interface.
 */
public protocol FilesProvider: Sendable {
    func files() -> any FilesV4
}
