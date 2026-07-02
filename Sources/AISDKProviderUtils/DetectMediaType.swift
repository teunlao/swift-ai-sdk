import Foundation

private struct ProviderUtilsMediaTypeSignature: Sendable {
    let mediaType: String
    let bytesPrefix: [UInt8?]
}

private let providerUtilsImageMediaTypeSignatures: [ProviderUtilsMediaTypeSignature] = [
    .init(mediaType: "image/gif", bytesPrefix: [0x47, 0x49, 0x46]),
    .init(mediaType: "image/png", bytesPrefix: [0x89, 0x50, 0x4E, 0x47]),
    .init(mediaType: "image/jpeg", bytesPrefix: [0xFF, 0xD8]),
    .init(
        mediaType: "image/webp",
        bytesPrefix: [
            0x52, 0x49, 0x46, 0x46,
            nil, nil, nil, nil,
            0x57, 0x45, 0x42, 0x50,
        ]
    ),
    .init(mediaType: "image/bmp", bytesPrefix: [0x42, 0x4D]),
    .init(mediaType: "image/tiff", bytesPrefix: [0x49, 0x49, 0x2A, 0x00]),
    .init(mediaType: "image/tiff", bytesPrefix: [0x4D, 0x4D, 0x00, 0x2A]),
    .init(
        mediaType: "image/avif",
        bytesPrefix: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66]
    ),
    .init(
        mediaType: "image/heic",
        bytesPrefix: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]
    ),
]

private let providerUtilsDocumentMediaTypeSignatures: [ProviderUtilsMediaTypeSignature] = [
    .init(mediaType: "application/pdf", bytesPrefix: [0x25, 0x50, 0x44, 0x46]),
]

private let providerUtilsAudioMediaTypeSignatures: [ProviderUtilsMediaTypeSignature] = [
    .init(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xFB]),
    .init(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xFA]),
    .init(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xF3]),
    .init(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xF2]),
    .init(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xE3]),
    .init(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xE2]),
    .init(
        mediaType: "audio/wav",
        bytesPrefix: [
            0x52, 0x49, 0x46, 0x46,
            nil, nil, nil, nil,
            0x57, 0x41, 0x56, 0x45,
        ]
    ),
    .init(mediaType: "audio/ogg", bytesPrefix: [0x4F, 0x67, 0x67, 0x53]),
    .init(mediaType: "audio/flac", bytesPrefix: [0x66, 0x4C, 0x61, 0x43]),
    .init(mediaType: "audio/aac", bytesPrefix: [0x40, 0x15, 0x00, 0x00]),
    .init(mediaType: "audio/mp4", bytesPrefix: [0x66, 0x74, 0x79, 0x70]),
    .init(mediaType: "audio/webm", bytesPrefix: [0x1A, 0x45, 0xDF, 0xA3]),
]

private let providerUtilsVideoMediaTypeSignatures: [ProviderUtilsMediaTypeSignature] = [
    .init(
        mediaType: "video/mp4",
        bytesPrefix: [0x00, 0x00, 0x00, nil, 0x66, 0x74, 0x79, 0x70]
    ),
    .init(mediaType: "video/webm", bytesPrefix: [0x1A, 0x45, 0xDF, 0xA3]),
    .init(
        mediaType: "video/quicktime",
        bytesPrefix: [0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74]
    ),
    .init(mediaType: "video/x-msvideo", bytesPrefix: [0x52, 0x49, 0x46, 0x46]),
]

/**
 Detects the IANA media type of a file from raw bytes.

 Swift port of `@ai-sdk/provider-utils/src/detect-media-type.ts`.
 */
public func detectMediaType(
    data: Data,
    topLevelType: String? = nil
) -> String? {
    detectMediaTypeInternal(data: .data(data), topLevelType: topLevelType)
}

/**
 Detects the IANA media type of a file from a base64 or base64url string.

 Swift port of `@ai-sdk/provider-utils/src/detect-media-type.ts`.
 */
public func detectMediaType(
    data base64: String,
    topLevelType: String? = nil
) -> String? {
    detectMediaTypeInternal(data: .base64(base64), topLevelType: topLevelType)
}

/**
 Returns the top-level segment of a media type.
 */
public func getTopLevelMediaType(_ mediaType: String) -> String {
    guard let slashIndex = mediaType.firstIndex(of: "/") else {
        return mediaType
    }

    return String(mediaType[..<slashIndex])
}

/**
 Returns true only when the given media type has a non-empty, non-wildcard subtype.
 */
public func isFullMediaType(_ mediaType: String) -> Bool {
    guard let slashIndex = mediaType.firstIndex(of: "/") else {
        return false
    }

    let subtypeStart = mediaType.index(after: slashIndex)
    let subtype = mediaType[subtypeStart...]
    return !subtype.isEmpty && subtype != "*"
}

private enum ProviderUtilsDataOrBase64 {
    case data(Data)
    case base64(String)
}

private func detectMediaTypeInternal(
    data: ProviderUtilsDataOrBase64,
    topLevelType: String?
) -> String? {
    let signatures: [ProviderUtilsMediaTypeSignature]
    switch topLevelType {
    case nil:
        signatures = providerUtilsImageMediaTypeSignatures
            + providerUtilsDocumentMediaTypeSignatures
            + providerUtilsAudioMediaTypeSignatures
            + providerUtilsVideoMediaTypeSignatures
    case "image":
        signatures = providerUtilsImageMediaTypeSignatures
    case "audio":
        signatures = providerUtilsAudioMediaTypeSignatures
    case "video":
        signatures = providerUtilsVideoMediaTypeSignatures
    case "application":
        signatures = providerUtilsDocumentMediaTypeSignatures
    default:
        return nil
    }

    return detectMediaTypeBySignatures(data: data, signatures: signatures)
}

private func detectMediaTypeBySignatures(
    data: ProviderUtilsDataOrBase64,
    signatures: [ProviderUtilsMediaTypeSignature]
) -> String? {
    let processedData = stripID3TagsIfPresent(data)
    let bytes: Data

    switch processedData {
    case .data(let data):
        bytes = data
    case .base64(let base64):
        guard let decoded = decodeBase64ForSignatureDetection(base64, maxEncodedLength: 24) else {
            return nil
        }
        bytes = decoded
    }

    for signature in signatures {
        guard bytes.count >= signature.bytesPrefix.count else {
            continue
        }

        let matches = signature.bytesPrefix.enumerated().allSatisfy { index, byte in
            guard let byte else { return true }
            return bytes[index] == byte
        }

        if matches {
            return signature.mediaType
        }
    }

    return nil
}

private func stripID3TagsIfPresent(_ data: ProviderUtilsDataOrBase64) -> ProviderUtilsDataOrBase64 {
    let bytes: Data

    switch data {
    case .data(let data):
        bytes = data
    case .base64(let base64):
        guard base64.hasPrefix("SUQz"),
              let decoded = decodeBase64ForSignatureDetection(base64)
        else {
            return data
        }
        bytes = decoded
    }

    guard bytes.count > 10,
          bytes[0] == 0x49,
          bytes[1] == 0x44,
          bytes[2] == 0x33
    else {
        return data
    }

    let id3Size = ((Int(bytes[6]) & 0x7F) << 21)
        | ((Int(bytes[7]) & 0x7F) << 14)
        | ((Int(bytes[8]) & 0x7F) << 7)
        | (Int(bytes[9]) & 0x7F)

    let strippedData = Data(bytes.dropFirst(id3Size + 10))

    switch data {
    case .data:
        return .data(strippedData)
    case .base64:
        return .base64(strippedData.base64EncodedString())
    }
}

private func decodeBase64ForSignatureDetection(
    _ string: String,
    maxEncodedLength: Int? = nil
) -> Data? {
    let truncated: String
    if let maxEncodedLength {
        truncated = String(string.prefix(min(string.count, maxEncodedLength)))
    } else {
        truncated = string
    }

    let normalized = truncated
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    let remainder = normalized.count % 4
    let padded = remainder == 0
        ? normalized
        : normalized + String(repeating: "=", count: 4 - remainder)

    return Data(base64Encoded: padded)
}
