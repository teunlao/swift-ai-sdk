import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("convertInlineFileDataToData")
struct ConvertInlineFileDataToDataTests {
    @Test("encodes text as UTF-8 bytes")
    func encodesTextAsUTF8Bytes() throws {
        let data = try convertInlineFileDataToData(.text("hello"))
        #expect(data == Data("hello".utf8))
    }

    @Test("returns raw data unchanged")
    func returnsRawData() throws {
        let bytes = Data([0x00, 0x01, 0xFF])
        let data = try convertInlineFileDataToData(.data(bytes))
        #expect(data == bytes)
    }

    @Test("decodes base64 and base64url data")
    func decodesBase64Data() throws {
        #expect(try convertInlineFileDataToData(.base64("aGVsbG8=")) == Data("hello".utf8))
        #expect(try convertInlineFileDataToData(.base64("SGVsbG8td29ybGRf")) == Data("Hello-world_".utf8))
    }

    @Test("throws for invalid base64")
    func throwsForInvalidBase64() {
        #expect(throws: DecodingError.self) {
            _ = try convertInlineFileDataToData(.base64("not valid base64"))
        }
    }
}
