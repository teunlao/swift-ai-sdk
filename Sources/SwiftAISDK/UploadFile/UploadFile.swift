import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Uploads a file using a files API interface.

 Port of `@ai-sdk/ai/src/upload-file/upload-file.ts`.
 */
@_disfavoredOverload
public func uploadFile(
    api: any FilesV4,
    data: DataContentOrURL,
    mediaType: String? = nil,
    filename: String? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    let uploadData = try normalizeUploadData(data)
    return try await uploadFile(
        api: api, data: uploadData, mediaType: mediaType,
        filename: filename, abortSignal: abortSignal, headers: headers, providerOptions: providerOptions
    )
}

@_disfavoredOverload
public func uploadFile(
    api: any FilesV4,
    data: DataContent,
    mediaType: String? = nil,
    filename: String? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    try await uploadFile(
        api: api,
        data: toDataContentOrURL(data),
        mediaType: mediaType,
        filename: filename,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions
    )
}

@_disfavoredOverload
public func uploadFile(
    api: any ProviderV4,
    data: DataContentOrURL,
    mediaType: String? = nil,
    filename: String? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    guard let filesAPI = try api.files() else {
        throw UploadCapabilityError(message: "The provider does not support file uploads. Make sure it exposes a files() method.")
    }

    return try await uploadFile(
        api: filesAPI,
        data: data,
        mediaType: mediaType,
        filename: filename,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions
    )
}

@_disfavoredOverload
public func uploadFile(
    api: any ProviderV4,
    data: DataContent,
    mediaType: String? = nil,
    filename: String? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    try await uploadFile(
        api: api,
        data: toDataContentOrURL(data),
        mediaType: mediaType,
        filename: filename,
        abortSignal: abortSignal,
        headers: headers,
        providerOptions: providerOptions
    )
}

public func uploadFile(
    api: any FilesV4,
    data: FilesV4UploadFileData,
    mediaType: String? = nil,
    filename: String? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    do {
        let result = try await api.uploadFile(options: .init(
            data: data, mediaType: mediaType ?? detectUploadMediaType(data),
            filename: filename, abortSignal: abortSignal,
            headers: headers, providerOptions: providerOptions
        ))
        return DefaultUploadFileResult(
            providerReference: result.providerReference,
            mediaType: result.mediaType, filename: result.filename,
            byteSize: result.byteSize, createdAt: result.createdAt, expiresAt: result.expiresAt,
            providerMetadata: result.providerMetadata, warnings: result.warnings
        )
    } catch {
        await cancelUploadStream(data)
        throw error
    }
}

public func uploadFile(
    api: any ProviderV4,
    data: FilesV4UploadFileData,
    mediaType: String? = nil,
    filename: String? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil
) async throws -> DefaultUploadFileResult {
    let files: any FilesV4
    do {
        guard let resolved = try api.files() else {
            throw UploadCapabilityError(message: "The provider does not support file uploads. Make sure it exposes a files() method.")
        }
        files = resolved
    } catch {
        await cancelUploadStream(data)
        throw error
    }
    return try await uploadFile(
        api: files, data: data, mediaType: mediaType, filename: filename,
        abortSignal: abortSignal, headers: headers, providerOptions: providerOptions
    )
}

struct UploadCapabilityError: Error, LocalizedError, CustomStringConvertible {
    let message: String
    var errorDescription: String? { message }
    var description: String { message }
}

private func cancelUploadStream(_ data: FilesV4UploadFileData) async {
    guard case .stream(let stream) = data else { return }
    await cancelStream(stream)
}

private func normalizeUploadData(_ data: DataContentOrURL) throws -> FilesV4UploadFileData {
    switch try convertToFileData(data).data {
    case .text(let text): return .text(text)
    case .data(let bytes): return .data(bytes)
    case .base64(let base64): return .base64(base64)
    case .reference:
        throw InvalidArgumentError(argument: "data", message: "Provider reference data cannot be uploaded again. Pass the original file bytes or text.")
    case .url:
        throw InvalidArgumentError(argument: "data", message: "URL data is not supported for file uploads. Fetch the URL content first and pass the bytes.")
    }
}

private func detectUploadMediaType(_ data: FilesV4UploadFileData) -> String {
    switch data {
    case .data(let bytes):
        return detectMediaType(data: bytes)
            ?? (isLikelyTextUploadData(bytes) ? "text/plain" : "application/octet-stream")
    case .base64(let base64):
        return detectMediaType(data: base64)
            ?? (isLikelyTextUploadData(base64) ? "text/plain" : "application/octet-stream")
    case .text:
        return "text/plain"
    case .stream:
        return "application/octet-stream"
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
