import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for mediaTypeToExtension function.

 Port of `@ai-sdk/provider-utils/src/media-type-to-extension.test.ts`.
 */
@Suite("MediaTypeToExtension")
struct MediaTypeToExtensionTests {
    @Test(
        "maps media types to extensions",
        arguments: [
            // Most common
            ("audio/mpeg", "mp3"),
            ("audio/mp3", "mp3"),
            ("audio/wav", "wav"),
            ("audio/x-wav", "wav"),
            ("audio/webm", "webm"),
            ("audio/ogg", "ogg"),
            ("audio/opus", "ogg"),
            ("audio/mp4", "m4a"),
            ("audio/x-m4a", "m4a"),
            ("audio/flac", "flac"),
            ("audio/aac", "aac"),
            // Upper case
            ("AUDIO/MPEG", "mp3"),
            ("AUDIO/MP3", "mp3"),
            // Invalid
            ("nope", ""),
        ]
    )
    func mapsMediaTypeToExtension(mediaType: String, expectedExtension: String) {
        let result = mediaTypeToExtension(mediaType)
        #expect(result == expectedExtension)
    }
}
