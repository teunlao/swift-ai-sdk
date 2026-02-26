import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("convertImageModelFileToDataURI")
struct ConvertImageModelFileToDataURITests {
    @Test("returns URL as-is for url files")
    func urlFile() throws {
        let file: ImageModelV3File = .url(url: "https://example.com/input.png", providerOptions: nil)
        #expect(convertImageModelFileToDataURI(file) == "https://example.com/input.png")
    }

    @Test("returns data URI for base64 file data")
    func base64File() throws {
        let file: ImageModelV3File = .file(
            mediaType: "image/png",
            data: .base64("iVBORw0KGgoAAAANSUhEUgAAAAE="),
            providerOptions: nil
        )
        #expect(
            convertImageModelFileToDataURI(file) ==
                "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAE="
        )
    }

    @Test("returns data URI for binary file data (base64-encoded)")
    func binaryFile() throws {
        let bytes = Data([137, 80, 78, 71]) // "\x89PNG"
        let file: ImageModelV3File = .file(
            mediaType: "image/png",
            data: .binary(bytes),
            providerOptions: nil
        )
        #expect(convertImageModelFileToDataURI(file) == "data:image/png;base64,iVBORw==")
    }
}

