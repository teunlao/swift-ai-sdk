import Foundation

/**
 Maps a media type (MIME type) to its corresponding file extension.

 Port of `@ai-sdk/provider-utils/src/media-type-to-extension.ts`.

 Originally introduced to set a filename for audio file uploads in upstream PR #8159.

 - Parameter mediaType: The media type to map (e.g., "audio/mpeg", "audio/x-wav")
 - Returns: The corresponding file extension (e.g., "mp3", "wav")

 ## Example
 ```swift
 mediaTypeToExtension("audio/mpeg")    // "mp3"
 mediaTypeToExtension("audio/x-wav")   // "wav"
 mediaTypeToExtension("audio/opus")    // "ogg"
 mediaTypeToExtension("audio/mp4")     // "m4a"
 mediaTypeToExtension("audio/x-m4a")   // "m4a"
 mediaTypeToExtension("audio/flac")    // "flac" (fallback to subtype)
 ```

 - SeeAlso: [MDN Common MIME types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types/Common_types)
 */
public func mediaTypeToExtension(_ mediaType: String) -> String {
    let parts = mediaType.lowercased().split(separator: "/", maxSplits: 1)
    let subtype = parts.count > 1 ? String(parts[1]) : ""

    // Map common audio subtypes to their extensions
    let extensionMap: [String: String] = [
        "mpeg": "mp3",
        "x-wav": "wav",
        "opus": "ogg",
        "mp4": "m4a",
        "x-m4a": "m4a"
    ]

    return extensionMap[subtype] ?? subtype
}
