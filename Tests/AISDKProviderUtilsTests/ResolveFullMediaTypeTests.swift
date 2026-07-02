import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("resolveFullMediaType")
struct ResolveFullMediaTypeTests {
    private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private let pdfBytes = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34])

    @Test("returns full media type as-is")
    func returnsFullMediaTypeAsIs() throws {
        let part = LanguageModelV4FilePart(data: .data(pngBytes), mediaType: "image/jpeg")
        #expect(try resolveFullMediaType(part: part) == "image/jpeg")
    }

    @Test("detects image subtype from inline bytes for top-level-only media type")
    func detectsImageSubtypeFromInlineBytes() throws {
        let part = LanguageModelV4FilePart(data: .data(pngBytes), mediaType: "image")
        #expect(try resolveFullMediaType(part: part) == "image/png")
    }

    @Test("treats wildcard subtype as top-level and runs detection")
    func treatsWildcardSubtypeAsTopLevel() throws {
        let part = LanguageModelV4FilePart(data: .data(pngBytes), mediaType: "image/*")
        #expect(try resolveFullMediaType(part: part) == "image/png")
    }

    @Test("detects application subtype from inline bytes")
    func detectsApplicationSubtype() throws {
        let part = LanguageModelV4FilePart(data: .data(pdfBytes), mediaType: "application")
        #expect(try resolveFullMediaType(part: part) == "application/pdf")
    }

    @Test("throws when URL source has top-level-only media type")
    func throwsForURLSourceWithTopLevelOnlyMediaType() {
        let part = LanguageModelV4FilePart(
            data: .url(URL(string: "https://example.com/x")!),
            mediaType: "image"
        )

        #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try resolveFullMediaType(part: part)
        }
    }

    @Test("throws when bytes are present but unrecognized")
    func throwsWhenBytesCannotBeDetected() {
        let part = LanguageModelV4FilePart(data: .data(Data([0x00, 0x01, 0x02])), mediaType: "image")

        #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try resolveFullMediaType(part: part)
        }
    }

    @Test("throws when top-level segment is unsupported")
    func throwsWhenTopLevelSegmentIsUnsupported() {
        let part = LanguageModelV4FilePart(data: .base64("aGVsbG8="), mediaType: "text")

        #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try resolveFullMediaType(part: part)
        }
    }

    @Test("accepts base64 string data")
    func acceptsBase64StringData() throws {
        let part = LanguageModelV4FilePart(data: .base64(pngBytes.base64EncodedString()), mediaType: "image")
        #expect(try resolveFullMediaType(part: part) == "image/png")
    }
}
