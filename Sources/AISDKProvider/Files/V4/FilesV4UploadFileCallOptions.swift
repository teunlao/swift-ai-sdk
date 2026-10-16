import Foundation

/**
 File data accepted by `FilesV4.uploadFile`.

 Swift adaptation of upstream `SharedV4FileDataData | SharedV4FileDataText | FilesV4UploadFileStreamData`.
 */
public enum FilesV4UploadFileData: Sendable {
    /// Raw bytes.
    case data(Data)
    /// Base64-encoded bytes.
    case base64(String)
    /// Inline UTF-8 text.
    case text(String)
    /// A byte stream. Providers that support streaming uploads send it without
    /// buffering the whole file in memory.
    case stream(AsyncThrowingStream<Data, Error>)
}

/**
 Options for uploading a file via the files interface.

 Port of `@ai-sdk/provider/src/files/v4/files-v4-upload-file-call-options.ts`.
 */
public struct FilesV4UploadFileCallOptions: Sendable {
    public let data: FilesV4UploadFileData
    public let mediaType: String
    public let filename: String?
    public let abortSignal: (@Sendable () -> Bool)?
    /// Additional HTTP headers. Only applicable for HTTP-based providers.
    public let headers: SharedV4Headers?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        data: FilesV4UploadFileData,
        mediaType: String,
        filename: String? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
        self.abortSignal = abortSignal
        self.headers = headers
        self.providerOptions = providerOptions
    }
}
