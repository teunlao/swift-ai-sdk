/**
 Tests for detectMediaType function.

 Port of `@ai-sdk/ai/src/util/detect-media-type.test.ts`.
 */

import Foundation
import Testing
@testable import SwiftAISDK

@Suite("DetectMediaType Tests")
struct DetectMediaTypeTests {
    // MARK: - GIF Tests

    @Test("should detect GIF from bytes")
    func testDetectGIFFromBytes() {
        let gifBytes = Data([0x47, 0x49, 0x46, 0xFF, 0xFF])
        let mediaType = detectMediaType(data: gifBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/gif")
    }

    @Test("should detect GIF from base64")
    func testDetectGIFFromBase64() {
        let gifBase64 = "R0lGabc123" // Base64 string starting with GIF signature
        let mediaType = detectMediaType(data: gifBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/gif")
    }

    // MARK: - PNG Tests

    @Test("should detect PNG from bytes")
    func testDetectPNGFromBytes() {
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFF])
        let mediaType = detectMediaType(data: pngBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/png")
    }

    @Test("should detect PNG from base64")
    func testDetectPNGFromBase64() {
        let pngBase64 = "iVBORwabc123" // Base64 string starting with PNG signature
        let mediaType = detectMediaType(data: pngBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/png")
    }

    // MARK: - JPEG Tests

    @Test("should detect JPEG from bytes")
    func testDetectJPEGFromBytes() {
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xFF])
        let mediaType = detectMediaType(data: jpegBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/jpeg")
    }

    @Test("should detect JPEG from base64")
    func testDetectJPEGFromBase64() {
        let jpegBase64 = "/9j/abc123" // Base64 string starting with JPEG signature
        let mediaType = detectMediaType(data: jpegBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/jpeg")
    }

    // MARK: - WebP Tests

    @Test("should detect WebP from bytes (positive webp image uint8)")
    func testDetectWebPFromBytes() {
        // WebP format: RIFF + 4 bytes file size + WEBP
        let webpBytes = Data([
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x24, 0x00, 0x00, 0x00,  // file size (example: 36 bytes)
            0x57, 0x45, 0x42, 0x50,  // "WEBP"
            0x56, 0x50, 0x38, 0x20,  // VP8 chunk (additional WebP data)
        ])
        let mediaType = detectMediaType(data: webpBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/webp")
    }

    @Test("should detect WebP from base64 (positive webp image base64)")
    func testDetectWebPFromBase64() {
        // WebP: RIFF + file size + WEBP encoded to base64
        let webpBytes = Data([
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x24, 0x00, 0x00, 0x00,  // file size
            0x57, 0x45, 0x42, 0x50,  // "WEBP"
            0x56, 0x50, 0x38, 0x20,  // VP8 chunk
        ])
        let webpBase64 = webpBytes.base64EncodedString()
        let mediaType = detectMediaType(data: webpBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/webp")
    }

    @Test("should NOT detect RIFF audio as WebP from bytes (negative riff audio uint8)")
    func testNotDetectRIFFAudioAsWebPFromBytes() {
        // WAV format: RIFF + file size + WAVE (not WEBP)
        let wavBytes = Data([
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x24, 0x00, 0x00, 0x00,  // file size
            0x57, 0x41, 0x56, 0x45,  // "WAVE" (not "WEBP")
            0x66, 0x6D, 0x74, 0x20,  // fmt chunk
        ])
        let mediaType = detectMediaType(data: wavBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == nil) // Should not detect as WebP
    }

    @Test("should NOT detect RIFF audio as WebP from base64 (negative riff audio base64)")
    func testNotDetectRIFFAudioAsWebPFromBase64() {
        // WAV format encoded to base64
        let wavBytes = Data([
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x24, 0x00, 0x00, 0x00,  // file size
            0x57, 0x41, 0x56, 0x45,  // "WAVE" (not "WEBP")
            0x66, 0x6D, 0x74, 0x20,  // fmt chunk
        ])
        let wavBase64 = wavBytes.base64EncodedString()
        let mediaType = detectMediaType(data: wavBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == nil) // Should not detect as WebP
    }

    // MARK: - BMP Tests

    @Test("should detect BMP from bytes")
    func testDetectBMPFromBytes() {
        let bmpBytes = Data([0x42, 0x4D, 0xFF, 0xFF])
        let mediaType = detectMediaType(data: bmpBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/bmp")
    }

    @Test("should detect BMP from base64")
    func testDetectBMPFromBase64() {
        let bmpBytes = Data([0x42, 0x4D, 0xFF, 0xFF])
        let bmpBase64 = bmpBytes.base64EncodedString()
        let mediaType = detectMediaType(data: bmpBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/bmp")
    }

    // MARK: - TIFF Tests

    @Test("should detect TIFF (little endian) from bytes")
    func testDetectTIFFLEFromBytes() {
        let tiffLEBytes = Data([0x49, 0x49, 0x2A, 0x00, 0xFF])
        let mediaType = detectMediaType(data: tiffLEBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/tiff")
    }

    @Test("should detect TIFF (little endian) from base64")
    func testDetectTIFFLEFromBase64() {
        let tiffLEBase64 = "SUkqAAabc123" // Base64 string starting with TIFF LE signature
        let mediaType = detectMediaType(data: tiffLEBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/tiff")
    }

    @Test("should detect TIFF (big endian) from bytes")
    func testDetectTIFFBEFromBytes() {
        let tiffBEBytes = Data([0x4D, 0x4D, 0x00, 0x2A, 0xFF])
        let mediaType = detectMediaType(data: tiffBEBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/tiff")
    }

    @Test("should detect TIFF (big endian) from base64")
    func testDetectTIFFBEFromBase64() {
        let tiffBEBase64 = "TU0AKgabc123" // Base64 string starting with TIFF BE signature
        let mediaType = detectMediaType(data: tiffBEBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/tiff")
    }

    // MARK: - AVIF Tests

    @Test("should detect AVIF from bytes")
    func testDetectAVIFFromBytes() {
        let avifBytes = Data([
            0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66,
            0xFF,
        ])
        let mediaType = detectMediaType(data: avifBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/avif")
    }

    @Test("should detect AVIF from base64")
    func testDetectAVIFFromBase64() {
        let avifBase64 = "AAAAIGZ0eXBhdmlmabc123" // Base64 string starting with AVIF signature
        let mediaType = detectMediaType(data: avifBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/avif")
    }

    // MARK: - HEIC Tests

    @Test("should detect HEIC from bytes")
    func testDetectHEICFromBytes() {
        let heicBytes = Data([
            0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63,
            0xFF,
        ])
        let mediaType = detectMediaType(data: heicBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/heic")
    }

    @Test("should detect HEIC from base64")
    func testDetectHEICFromBase64() {
        let heicBase64 = "AAAAIGZ0eXBoZWljabc123" // Base64 string starting with HEIC signature
        let mediaType = detectMediaType(data: heicBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == "image/heic")
    }

    // MARK: - MP3 Tests

    @Test("should detect MP3 from bytes")
    func testDetectMP3FromBytes() {
        let mp3Bytes = Data([0xFF, 0xFB])
        let mediaType = detectMediaType(data: mp3Bytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/mpeg")
    }

    @Test("should detect MP3 from base64")
    func testDetectMP3FromBase64() {
        let mp3Base64 = "//s=" // Base64 string starting with MP3 signature
        let mediaType = detectMediaType(data: mp3Base64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/mpeg")
    }

    @Test("should detect MP3 with ID3v2 tags from bytes")
    func testDetectMP3WithID3FromBytes() {
        let mp3WithID3Bytes = Data([
            0x49, 0x44, 0x33,  // 'ID3'
            0x03, 0x00,        // version
            0x00,              // flags
            0x00, 0x00, 0x00, 0x0A,  // size (10 bytes)
            // 10 bytes of ID3 data
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            // MP3 frame header
            0xFF, 0xFB, 0x00, 0x00,
        ])
        let mediaType = detectMediaType(data: mp3WithID3Bytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/mpeg")
    }

    @Test("should detect MP3 with ID3v2 tags from base64")
    func testDetectMP3WithID3FromBase64() {
        let mp3WithID3Bytes = Data([
            0x49, 0x44, 0x33,  // 'ID3'
            0x03, 0x00,        // version
            0x00,              // flags
            0x00, 0x00, 0x00, 0x0A,  // size (10 bytes)
            // 10 bytes of ID3 data
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            // MP3 frame header
            0xFF, 0xFB, 0x00, 0x00,
        ])
        let mp3WithID3Base64 = mp3WithID3Bytes.base64EncodedString()
        let mediaType = detectMediaType(data: mp3WithID3Base64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/mpeg")
    }

    // MARK: - WAV Tests

    @Test("should detect WAV from bytes")
    func testDetectWAVFromBytes() {
        let wavBytes = Data([
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x24, 0x00, 0x00, 0x00,  // file size (example: 36 bytes)
            0x57, 0x41, 0x56, 0x45,  // "WAVE" (not "WEBP")
            0x66, 0x6D, 0x74, 0x20,  // fmt chunk
        ])
        let mediaType = detectMediaType(data: wavBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/wav")
    }

    @Test("should detect WAV from base64")
    func testDetectWAVFromBase64() {
        let wavBytes = Data([
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x24, 0x00, 0x00, 0x00,  // file size (example: 36 bytes)
            0x57, 0x41, 0x56, 0x45,  // "WAVE" (not "WEBP")
            0x66, 0x6D, 0x74, 0x20,  // fmt chunk
        ])
        let wavBase64 = wavBytes.base64EncodedString()
        let mediaType = detectMediaType(data: wavBase64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/wav")
    }

    @Test("should NOT detect WebP as WAV from bytes (negative webp image uint8)")
    func testNotDetectWebPAsWAVFromBytes() {
        let webpBytes = Data([
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x24, 0x00, 0x00, 0x00,  // file size (example: 36 bytes)
            0x57, 0x45, 0x42, 0x50,  // "WEBP"
            0x56, 0x50, 0x38, 0x20,  // VP8 chunk (additional WebP data)
        ])
        let mediaType = detectMediaType(data: webpBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == nil) // Should not detect as WAV
    }

    @Test("should NOT detect WebP as WAV from base64 (negative webp image base64)")
    func testNotDetectWebPAsWAVFromBase64() {
        let webpBytes = Data([
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x24, 0x00, 0x00, 0x00,  // file size (example: 36 bytes)
            0x57, 0x45, 0x42, 0x50,  // "WEBP"
            0x56, 0x50, 0x38, 0x20,  // VP8 chunk (additional WebP data)
        ])
        let webpBase64 = webpBytes.base64EncodedString()
        let mediaType = detectMediaType(data: webpBase64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == nil) // Should not detect as WAV
    }

    // MARK: - OGG Tests

    @Test("should detect OGG from bytes")
    func testDetectOGGFromBytes() {
        let oggBytes = Data([0x4F, 0x67, 0x67, 0x53])
        let mediaType = detectMediaType(data: oggBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/ogg")
    }

    @Test("should detect OGG from base64")
    func testDetectOGGFromBase64() {
        let oggBase64 = "T2dnUw" // Base64 string starting with OGG signature
        let mediaType = detectMediaType(data: oggBase64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/ogg")
    }

    // MARK: - FLAC Tests

    @Test("should detect FLAC from bytes")
    func testDetectFLACFromBytes() {
        let flacBytes = Data([0x66, 0x4C, 0x61, 0x43])
        let mediaType = detectMediaType(data: flacBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/flac")
    }

    @Test("should detect FLAC from base64")
    func testDetectFLACFromBase64() {
        let flacBase64 = "ZkxhQw" // Base64 string starting with FLAC signature
        let mediaType = detectMediaType(data: flacBase64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/flac")
    }

    // MARK: - AAC Tests

    @Test("should detect AAC from bytes")
    func testDetectAACFromBytes() {
        let aacBytes = Data([0x40, 0x15, 0x00, 0x00])
        let mediaType = detectMediaType(data: aacBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/aac")
    }

    @Test("should detect AAC from base64")
    func testDetectAACFromBase64() {
        let aacBytes = Data([0x40, 0x15, 0x00, 0x00])
        let aacBase64 = aacBytes.base64EncodedString()
        let mediaType = detectMediaType(data: aacBase64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/aac")
    }

    // MARK: - MP4 Tests

    @Test("should detect MP4 from bytes")
    func testDetectMP4FromBytes() {
        let mp4Bytes = Data([0x66, 0x74, 0x79, 0x70])
        let mediaType = detectMediaType(data: mp4Bytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/mp4")
    }

    @Test("should detect MP4 from base64")
    func testDetectMP4FromBase64() {
        let mp4Base64 = "ZnR5cA" // Base64 string starting with MP4 signature
        let mediaType = detectMediaType(data: mp4Base64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/mp4")
    }

    // MARK: - WEBM Tests

    @Test("should detect WEBM from bytes")
    func testDetectWEBMFromBytes() {
        let webmBytes = Data([0x1A, 0x45, 0xDF, 0xA3])
        let mediaType = detectMediaType(data: webmBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/webm")
    }

    @Test("should detect WEBM from base64")
    func testDetectWEBMFromBase64() {
        let webmBase64 = "GkXfow==" // Base64 string starting with WEBM signature
        let mediaType = detectMediaType(data: webmBase64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == "audio/webm")
    }

    // MARK: - Error Cases

    @Test("should return nil for unknown image formats")
    func testUnknownImageFormat() {
        let unknownBytes = Data([0x00, 0x01, 0x02, 0x03])
        let mediaType = detectMediaType(data: unknownBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == nil)
    }

    @Test("should return nil for unknown audio formats")
    func testUnknownAudioFormat() {
        let unknownBytes = Data([0x00, 0x01, 0x02, 0x03])
        let mediaType = detectMediaType(data: unknownBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == nil)
    }

    @Test("should return nil for empty arrays for image")
    func testEmptyBytesImage() {
        let emptyBytes = Data([])
        let mediaType = detectMediaType(data: emptyBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == nil)
    }

    @Test("should return nil for empty arrays for audio")
    func testEmptyBytesAudio() {
        let emptyBytes = Data([])
        let mediaType = detectMediaType(data: emptyBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == nil)
    }

    @Test("should return nil for arrays shorter than signature length for image")
    func testShortBytesImage() {
        let shortBytes = Data([0x89, 0x50]) // Incomplete PNG signature
        let mediaType = detectMediaType(data: shortBytes, signatures: imageMediaTypeSignatures)
        #expect(mediaType == nil)
    }

    @Test("should return nil for arrays shorter than signature length for audio")
    func testShortBytesAudio() {
        let shortBytes = Data([0x4F, 0x67]) // Incomplete OGG signature
        let mediaType = detectMediaType(data: shortBytes, signatures: audioMediaTypeSignatures)
        #expect(mediaType == nil)
    }

    @Test("should return nil for invalid base64 strings for image")
    func testInvalidBase64Image() {
        let invalidBase64 = "invalid123"
        let mediaType = detectMediaType(data: invalidBase64, signatures: imageMediaTypeSignatures)
        #expect(mediaType == nil)
    }

    @Test("should return nil for invalid base64 strings for audio")
    func testInvalidBase64Audio() {
        let invalidBase64 = "invalid123"
        let mediaType = detectMediaType(data: invalidBase64, signatures: audioMediaTypeSignatures)
        #expect(mediaType == nil)
    }
}
