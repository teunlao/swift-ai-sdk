import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("detectMediaType")
struct ProviderUtilsDetectMediaTypeTests {
    @Test("detects image signatures from bytes and base64")
    func detectsImageSignatures() {
        #expect(detectMediaType(data: Data("GIF89a".utf8), topLevelType: "image") == "image/gif")
        // Plain text starting with "GIF" or "BM" is not an image.
        #expect(detectMediaType(data: Data("GIF is a format".utf8), topLevelType: "image") == nil)
        #expect(detectMediaType(data: Data("BMW owners manual".utf8), topLevelType: "image") == nil)
        #expect(detectMediaType(data: "iVBORwabc123", topLevelType: "image") == "image/png")
        #expect(detectMediaType(data: Data([0xFF, 0xD8, 0xFF]), topLevelType: "image") == "image/jpeg")
    }

    @Test("does not detect RIFF audio as WebP under image signatures")
    func doesNotDetectRiffAudioAsWebP() {
        let wavBytes = Data([
            0x52, 0x49, 0x46, 0x46,
            0x24, 0x00, 0x00, 0x00,
            0x57, 0x41, 0x56, 0x45,
        ])

        #expect(detectMediaType(data: wavBytes, topLevelType: "image") == nil)
    }

    @Test("detects PDF under application signatures")
    func detectsPDF() {
        #expect(detectMediaType(data: Data([0x25, 0x50, 0x44, 0x46]), topLevelType: "application") == "application/pdf")
    }

    @Test("detects audio signatures and strips ID3 tags")
    func detectsAudioSignaturesAndStripsID3() {
        let mp3WithID3Bytes = Data([
            0x49, 0x44, 0x33,
            0x03, 0x00,
            0x00,
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00,
            0xFF, 0xFB, 0x00, 0x00,
        ])

        #expect(detectMediaType(data: Data([0xFF, 0xFB]), topLevelType: "audio") == "audio/mpeg")
        #expect(detectMediaType(data: mp3WithID3Bytes, topLevelType: "audio") == "audio/mpeg")
    }

    @Test("detects ADTS AAC, ftyp boxes of any size, and MP4 as audio or video by top-level type")
    func detectsAacAndVariableFtypBoxes() {
        #expect(detectMediaType(data: Data([0xFF, 0xF1, 0x50, 0x80]), topLevelType: "audio") == "audio/aac")

        let avif = Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66])
        #expect(detectMediaType(data: avif, topLevelType: "image") == "image/avif")

        let m4a = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20])
        #expect(detectMediaType(data: m4a, topLevelType: "audio") == "audio/mp4")
        #expect(detectMediaType(data: m4a) == "video/mp4")
    }

    @Test("detects video signatures")
    func detectsVideoSignatures() {
        #expect(detectMediaType(data: Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]), topLevelType: "video") == "video/mp4")
        #expect(detectMediaType(data: Data([0x1A, 0x45, 0xDF, 0xA3]), topLevelType: "video") == "video/webm")
    }

    @Test("detects across all known signatures when topLevelType is omitted")
    func detectsAcrossAllKnownSignatures() {
        #expect(detectMediaType(data: Data([0x25, 0x50, 0x44, 0x46])) == "application/pdf")
        #expect(detectMediaType(data: Data([0x89, 0x50, 0x4E, 0x47])) == "image/png")
    }

    @Test("returns nil for unsupported top-level type and unknown bytes")
    func returnsNilForUnsupportedOrUnknownInput() {
        #expect(detectMediaType(data: Data([0x00, 0x01, 0x02]), topLevelType: "text") == nil)
        #expect(detectMediaType(data: Data([0x00, 0x01, 0x02]), topLevelType: "image") == nil)
        #expect(detectMediaType(data: "invalid123", topLevelType: "image") == nil)
    }

    @Test("getTopLevelMediaType returns segment before slash")
    func getTopLevelMediaTypeReturnsSegmentBeforeSlash() {
        #expect(getTopLevelMediaType("image/png") == "image")
        #expect(getTopLevelMediaType("image/*") == "image")
        #expect(getTopLevelMediaType("image") == "image")
        #expect(getTopLevelMediaType("image/") == "image")
        #expect(getTopLevelMediaType("") == "")
        #expect(getTopLevelMediaType("/") == "")
    }

    @Test("isFullMediaType requires non-empty non-wildcard subtype")
    func isFullMediaTypeRequiresSubtype() {
        #expect(isFullMediaType("image/png"))
        #expect(!isFullMediaType("image/*"))
        #expect(!isFullMediaType("image"))
        #expect(!isFullMediaType("image/"))
        #expect(!isFullMediaType(""))
        #expect(!isFullMediaType("/"))
    }
}
