import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Uploads a file using a files API interface.

 Port of `@ai-sdk/ai/src/upload-file/upload-file.ts`.
 */
public func uploadFile(
    api: any FilesV4,
    data: DataContentOrURL,
    mediaType: String? = nil,
    filename: String? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    let uploadData = try normalizeUploadData(data)
    let resolvedMediaType = mediaType ?? detectUploadMediaType(uploadData)

    let result = try await api.uploadFile(
        options: .init(
            data: uploadData,
            mediaType: resolvedMediaType,
            filename: filename,
            providerOptions: providerOptions
        )
    )

    return DefaultUploadFileResult(
        providerReference: result.providerReference,
        mediaType: result.mediaType,
        filename: result.filename,
        providerMetadata: result.providerMetadata,
        warnings: result.warnings
    )
}

public func uploadFile(
    api: any FilesV4,
    data: DataContent,
    mediaType: String? = nil,
    filename: String? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    try await uploadFile(
        api: api,
        data: toDataContentOrURL(data),
        mediaType: mediaType,
        filename: filename,
        providerOptions: providerOptions
    )
}

public func uploadFile(
    api: any ProviderV3,
    data: DataContentOrURL,
    mediaType: String? = nil,
    filename: String? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    guard let filesProvider = api as? any FilesProvider else {
        throw InvalidArgumentError(
            argument: "api",
            message: "The provider does not support file uploads. Make sure it exposes a files() method."
        )
    }

    return try await uploadFile(
        api: filesProvider.files(),
        data: data,
        mediaType: mediaType,
        filename: filename,
        providerOptions: providerOptions
    )
}

public func uploadFile(
    api: any ProviderV3,
    data: DataContent,
    mediaType: String? = nil,
    filename: String? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    try await uploadFile(
        api: api,
        data: toDataContentOrURL(data),
        mediaType: mediaType,
        filename: filename,
        providerOptions: providerOptions
    )
}

private func normalizeUploadData(_ data: DataContentOrURL) throws -> SharedV4DataContent {
    let converted = try convertToLanguageModelV3DataContent(data)

    switch converted.data {
    case .data(let bytes):
        return .data(bytes)
    case .base64(let base64):
        return .base64(base64)
    case .url:
        throw InvalidArgumentError(
            argument: "data",
            message: "URL data is not supported for file uploads. Fetch the URL content first and pass the bytes."
        )
    }
}

private func detectUploadMediaType(_ data: SharedV4DataContent) -> String {
    let signatures = imageMediaTypeSignatures
        + documentMediaTypeSignatures
        + audioMediaTypeSignatures
        + videoMediaTypeSignatures

    switch data {
    case .data(let bytes):
        return detectMediaType(data: bytes, signatures: signatures)
            ?? (isLikelyTextUploadData(bytes) ? "text/plain" : "application/octet-stream")
    case .base64(let base64):
        return detectMediaType(data: base64, signatures: signatures)
            ?? (isLikelyTextUploadData(base64) ? "text/plain" : "application/octet-stream")
    case .text:
        return "text/plain"
    }
}

private func toDataContentOrURL(_ data: DataContent) -> DataContentOrURL {
    switch data {
    case .data(let bytes):
        return .data(bytes)
    case .string(let string):
        return .string(string)
    }
}

private func isLikelyTextUploadData(_ data: Data) -> Bool {
    let checkLength = min(data.count, 512)
    guard checkLength > 0 else { return false }

    for byte in data.prefix(checkLength) {
        if byte == 0x00 || (byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D) {
            return false
        }
    }

    return true
}

private func isLikelyTextUploadData(_ base64: String) -> Bool {
    let checkLength = 512
    let base64CheckLength = Int(ceil(Double(checkLength + 4) / 3.0) * 4.0)
    let truncated = String(base64.prefix(min(base64.count, base64CheckLength)))
    let remainder = truncated.count % 4
    let padded: String
    if remainder == 0 {
        padded = truncated
    } else {
        padded = truncated + String(repeating: "=", count: 4 - remainder)
    }

    guard let decoded = try? convertBase64ToData(padded) else {
        return false
    }

    return isLikelyTextUploadData(decoded)
}
