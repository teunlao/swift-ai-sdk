/**
 Detect media type (MIME type) from file signatures.

 Port of `@ai-sdk/ai/src/util/detect-media-type.ts`.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Represents a media type signature for file format detection.
public struct MediaTypeSignature: Sendable {
    /// The IANA media type (e.g., "image/png").
    public let mediaType: String

    /// The byte prefix signature. Use `nil` for variable bytes that should be skipped.
    public let bytesPrefix: [UInt8?]

    public init(mediaType: String, bytesPrefix: [UInt8?]) {
        self.mediaType = mediaType
        self.bytesPrefix = bytesPrefix
    }
}

/// Known image media type signatures for detection.
public let imageMediaTypeSignatures: [MediaTypeSignature] = [
    MediaTypeSignature(mediaType: "image/gif", bytesPrefix: [0x47, 0x49, 0x46]), // GIF
    MediaTypeSignature(mediaType: "image/png", bytesPrefix: [0x89, 0x50, 0x4E, 0x47]), // PNG
    MediaTypeSignature(mediaType: "image/jpeg", bytesPrefix: [0xFF, 0xD8]), // JPEG
    MediaTypeSignature(
        mediaType: "image/webp",
        bytesPrefix: [
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            nil, nil, nil, nil,       // file size (variable)
            0x57, 0x45, 0x42, 0x50,  // "WEBP"
        ]
    ),
    MediaTypeSignature(mediaType: "image/bmp", bytesPrefix: [0x42, 0x4D]),
    MediaTypeSignature(mediaType: "image/tiff", bytesPrefix: [0x49, 0x49, 0x2A, 0x00]),
    MediaTypeSignature(mediaType: "image/tiff", bytesPrefix: [0x4D, 0x4D, 0x00, 0x2A]),
    MediaTypeSignature(
        mediaType: "image/avif",
        bytesPrefix: [
            0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66,
        ]
    ),
    MediaTypeSignature(
        mediaType: "image/heic",
        bytesPrefix: [
            0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63,
        ]
    ),
]

/// Known audio media type signatures for detection.
public let audioMediaTypeSignatures: [MediaTypeSignature] = [
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xFB]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xFA]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xF3]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xF2]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xE3]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xE2]),
    MediaTypeSignature(
        mediaType: "audio/wav",
        bytesPrefix: [
            0x52, // R
            0x49, // I
            0x46, // F
            0x46, // F
            nil, nil, nil, nil,
            0x57, // W
            0x41, // A
            0x56, // V
            0x45, // E
        ]
    ),
    MediaTypeSignature(mediaType: "audio/ogg", bytesPrefix: [0x4F, 0x67, 0x67, 0x53]),
    MediaTypeSignature(mediaType: "audio/flac", bytesPrefix: [0x66, 0x4C, 0x61, 0x43]),
    MediaTypeSignature(mediaType: "audio/aac", bytesPrefix: [0x40, 0x15, 0x00, 0x00]),
    MediaTypeSignature(mediaType: "audio/mp4", bytesPrefix: [0x66, 0x74, 0x79, 0x70]),
    MediaTypeSignature(mediaType: "audio/webm", bytesPrefix: [0x1A, 0x45, 0xDF, 0xA3]),
]

/// Known video media type signatures for detection.
public let videoMediaTypeSignatures: [MediaTypeSignature] = [
    MediaTypeSignature(
        mediaType: "video/mp4",
        bytesPrefix: [
            0x00, 0x00, 0x00, nil,
            0x66, 0x74, 0x79, 0x70, // ftyp
        ]
    ),
    MediaTypeSignature(mediaType: "video/webm", bytesPrefix: [0x1A, 0x45, 0xDF, 0xA3]), // EBML
    MediaTypeSignature(
        mediaType: "video/quicktime",
        bytesPrefix: [
            0x00, 0x00, 0x00, 0x14,
            0x66, 0x74, 0x79, 0x70,
            0x71, 0x74, // ftypqt
        ]
    ),
    MediaTypeSignature(mediaType: "video/x-msvideo", bytesPrefix: [0x52, 0x49, 0x46, 0x46]), // RIFF (AVI)
]

/// Strips ID3 tags from MP3 data if present.
///
/// - Parameter data: The data to process (either bytes or base64 string).
/// - Returns: The data with ID3 tags stripped, or original data if no ID3 tags present.
func stripID3TagsIfPresent(_ data: DataOrBase64) -> DataOrBase64 {
    let bytes: Data

    switch data {
    case .data(let d):
        bytes = d
    case .base64(let str):
        // Check for ID3 header in base64: "SUQz" = "ID3" in base64
        guard str.hasPrefix("SUQz") else {
            return data
        }
        guard let decoded = Data(base64Encoded: str) else {
            return data
        }
        bytes = decoded
    }

    // Check for ID3v2 tag: "ID3"
    guard bytes.count > 10,
          bytes[0] == 0x49,  // 'I'
          bytes[1] == 0x44,  // 'D'
          bytes[2] == 0x33   // '3'
    else {
        return data
    }

    // Calculate ID3 tag size
    let id3Size = ((Int(bytes[6]) & 0x7F) << 21)
        | ((Int(bytes[7]) & 0x7F) << 14)
        | ((Int(bytes[8]) & 0x7F) << 7)
        | (Int(bytes[9]) & 0x7F)

    // Return stripped data (skip ID3 header + tag size)
    let strippedData = bytes.dropFirst(id3Size + 10)

    switch data {
    case .data:
        return .data(Data(strippedData))
    case .base64:
        return .base64(Data(strippedData).base64EncodedString())
    }
}

/// Represents either raw data or base64-encoded string.
enum DataOrBase64 {
    case data(Data)
    case base64(String)
}

/**
 Detect the media IANA media type of a file using a list of signatures.

 - Parameters:
   - data: The file data (either raw bytes or base64-encoded string).
   - signatures: The signatures to use for detection.
 - Returns: The detected media type, or `nil` if no match found.
 */
public func detectMediaType(
    data: Data,
    signatures: [MediaTypeSignature]
) -> String? {
    return detectMediaTypeInternal(data: .data(data), signatures: signatures)
}

/**
 Detect the media IANA media type of a file using a list of signatures.

 - Parameters:
   - data: The file data as a base64-encoded string.
   - signatures: The signatures to use for detection.
 - Returns: The detected media type, or `nil` if no match found.
 */
public func detectMediaType(
    data: String,
    signatures: [MediaTypeSignature]
) -> String? {
    return detectMediaTypeInternal(data: .base64(data), signatures: signatures)
}

/// Internal implementation of media type detection.
private func detectMediaTypeInternal(
    data: DataOrBase64,
    signatures: [MediaTypeSignature]
) -> String? {
    // Strip ID3 tags if present (for MP3 files)
    let processedData = stripID3TagsIfPresent(data)

    // Convert to bytes for detection
    let bytes: Data

    switch processedData {
    case .data(let d):
        bytes = d
    case .base64(let str):
        // Decode first ~18 bytes (24 base64 chars) for consistent detection
        let substring = String(str.prefix(min(str.count, 24)))

        // Swift's base64 decoder requires proper padding, add it if needed
        let paddedSubstring: String
        let remainder = substring.count % 4
        if remainder > 0 {
            paddedSubstring = substring + String(repeating: "=", count: 4 - remainder)
        } else {
            paddedSubstring = substring
        }

        guard let decoded = Data(base64Encoded: paddedSubstring) else {
            return nil
        }
        bytes = decoded
    }

    // Match against signatures
    for signature in signatures {
        guard bytes.count >= signature.bytesPrefix.count else {
            continue
        }

        let matches = signature.bytesPrefix.enumerated().allSatisfy { index, byte in
            // nil means variable byte (skip comparison)
            guard let byte else { return true }
            return bytes[index] == byte
        }

        if matches {
            return signature.mediaType
        }
    }

    return nil
}
