import Foundation

private struct ProviderUtilsMediaTypeSignature: Sendable {
    let mediaType: String
    let bytesPrefix: [UInt8?]
}

private let providerUtilsImageMediaTypeSignatures: [ProviderUtilsMediaTypeSignature] = [
    .init(mediaType: "image/gif", bytesPrefix: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]), // GIF87a
    .init(mediaType: "image/gif", bytesPrefix: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]), // GIF89a
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
    .init(mediaType: "image/bmp", bytesPrefix: [0x42, 0x4D, nil, nil, nil, nil, 0x00, 0x00, 0x00, 0x00]),
    .init(mediaType: "image/tiff", bytesPrefix: [0x49, 0x49, 0x2A, 0x00]),
    .init(mediaType: "image/tiff", bytesPrefix: [0x4D, 0x4D, 0x00, 0x2A]),
    // ftyp box sizes vary, so the size byte is a wildcard.
    .init(
        mediaType: "image/avif",
        bytesPrefix: [0x00, 0x00, 0x00, nil, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66]
    ),
    .init(
        mediaType: "image/heic",
        bytesPrefix: [0x00, 0x00, 0x00, nil, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]
    ),
]

private let providerUtilsDocumentMediaTypeSignatures: [ProviderUtilsMediaTypeSignature] = [
    .init(mediaType: "application/pdf", bytesPrefix: [0x25, 0x50, 0x44, 0x46]),
]

private let providerUtilsAudioMediaTypeSignaturesWithoutMp4: [ProviderUtilsMediaTypeSignature] = [
    .init(mediaType: "audio/aac", bytesPrefix: [0xFF, 0xF0]), // MPEG-4 ADTS with CRC
    .init(mediaType: "audio/aac", bytesPrefix: [0xFF, 0xF1]), // MPEG-4 ADTS without CRC
    .init(mediaType: "audio/aac", bytesPrefix: [0xFF, 0xF8]), // MPEG-2 ADTS with CRC
    .init(mediaType: "audio/aac", bytesPrefix: [0xFF, 0xF9]), // MPEG-2 ADTS without CRC
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
    .init(mediaType: "audio/webm", bytesPrefix: [0x1A, 0x45, 0xDF, 0xA3]),
]

private let providerUtilsAudioMediaTypeSignatures: [ProviderUtilsMediaTypeSignature] =
    providerUtilsAudioMediaTypeSignaturesWithoutMp4 + [
        .init(mediaType: "audio/mp4", bytesPrefix: [0x00, 0x00, 0x00, nil, 0x66, 0x74, 0x79, 0x70]),
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

private let defaultSniffBytes = 18

// Longest signature prefix in the tables above.
private let maxSignatureBytes = 12

/// Largest ID3v2 tag (header and body) skipped to reach the audio frame. Bounds
/// the decode so it stays independent of the input size.
let maxID3TagBytes = 128 * 1024

// Prefix decoded when an ID3 tag is present: the tag plus room for the trailing signature.
private let id3ScanBytes = maxID3TagBytes + maxSignatureBytes

/**
 Detects the IANA media type of a file from raw bytes.

 When `topLevelType` is `nil`, every known signature is considered; MP4
 containers are reported as `video/mp4`, since `ftyp` cannot tell audio from
 video. Otherwise only signatures of that top-level segment are considered, and
 unsupported segments (e.g. `text`) return `nil`.

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
            + providerUtilsAudioMediaTypeSignaturesWithoutMp4
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
    var bytes = decodePrefix(data, maxBytes: defaultSniffBytes)

    // ID3v2-tagged MP3s carry the audio frame after the tag; scan a bounded
    // prefix past it rather than decoding the whole input.
    if hasID3(bytes) {
        bytes = stripID3(decodePrefix(data, maxBytes: id3ScanBytes))
    }

    for signature in signatures where bytes.count >= signature.bytesPrefix.count {
        let matches = signature.bytesPrefix.enumerated().allSatisfy { index, byte in
            guard let byte else { return true }
            return bytes[bytes.startIndex + index] == byte
        }

        if matches {
            return signature.mediaType
        }
    }

    return nil
}

/// Decodes exactly the first `maxBytes` bytes, so detection does not depend on
/// whether the input is raw bytes or base64.
private func decodePrefix(_ data: ProviderUtilsDataOrBase64, maxBytes: Int) -> Data {
    switch data {
    case .data(let data):
        return data.count > maxBytes ? data.prefix(maxBytes) : data
    case .base64(let base64):
        // 4 base64 characters decode to 3 bytes: decode whole groups, then trim.
        let maxChars = Int((Double(maxBytes) / 3).rounded(.up)) * 4
        let bytes = decodeBase64ForSignatureDetection(String(base64.prefix(maxChars))) ?? Data()
        return bytes.count > maxBytes ? bytes.prefix(maxBytes) : bytes
    }
}

private func hasID3(_ bytes: Data) -> Bool {
    let start = bytes.startIndex
    return bytes.count > 10
        && bytes[start] == 0x49 // 'I'
        && bytes[start + 1] == 0x44 // 'D'
        && bytes[start + 2] == 0x33 // '3'
}

private func stripID3(_ bytes: Data) -> Data {
    let start = bytes.startIndex
    let id3Size = ((Int(bytes[start + 6]) & 0x7F) << 21)
        | ((Int(bytes[start + 7]) & 0x7F) << 14)
        | ((Int(bytes[start + 8]) & 0x7F) << 7)
        | (Int(bytes[start + 9]) & 0x7F)

    return Data(bytes.dropFirst(id3Size + 10))
}

private func decodeBase64ForSignatureDetection(_ string: String) -> Data? {
    let normalized = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    let remainder = normalized.count % 4
    let padded = remainder == 0
        ? normalized
        : normalized + String(repeating: "=", count: 4 - remainder)

    return Data(base64Encoded: padded)
}
