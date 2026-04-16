import Foundation

/**
 Options for uploading a file via the files interface.

 Port of `@ai-sdk/provider/src/files/v4/files-v4-upload-file-call-options.ts`.
 */
public struct FilesV4UploadFileCallOptions: Sendable, Equatable {
    public let data: SharedV4DataContent
    public let mediaType: String
    public let filename: String?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        data: SharedV4DataContent,
        mediaType: String,
        filename: String? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
        self.providerOptions = providerOptions
    }
}
