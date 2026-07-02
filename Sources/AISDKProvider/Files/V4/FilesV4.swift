/**
 Specification for a file management interface that implements files interface version 4.

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

/**
 Provider capability marker for providers that expose a v4 files interface.
 */
public protocol FilesProvider: Sendable {
    func files() -> any FilesV4
}
