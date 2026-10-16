import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("convertInlineFileDataToData")
struct ConvertInlineFileDataToDataTests {
    @Test("encodes text as UTF-8 bytes")
    func encodesTextAsUTF8Bytes() throws {
        let data = try convertInlineFileDataToData(SharedV4DataContent.text("hello"))
        #expect(data == Data("hello".utf8))
    }

    @Test("returns raw data unchanged")
    func returnsRawData() throws {
        let bytes = Data([0x00, 0x01, 0xFF])
        let data = try convertInlineFileDataToData(SharedV4DataContent.data(bytes))
        #expect(data == bytes)
    }

    @Test("decodes base64 and base64url data")
    func decodesBase64Data() throws {
        #expect(try convertInlineFileDataToData(SharedV4DataContent.base64("aGVsbG8=")) == Data("hello".utf8))
        #expect(try convertInlineFileDataToData(SharedV4DataContent.base64("SGVsbG8td29ybGRf")) == Data("Hello-world_".utf8))
    }

    @Test("throws for invalid base64")
    func throwsForInvalidBase64() {
        #expect(throws: DecodingError.self) {
            _ = try convertInlineFileDataToData(SharedV4DataContent.base64("not valid base64"))
        }
    }

    @Test("rejects stream upload data as unsupported and cancels the stream")
    func rejectsStreamUploadData() async {
        let terminated = AsyncStream<Void>.makeStream()
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("unread".utf8))
            continuation.onTermination = { _ in terminated.continuation.yield() }
        }

        let error = #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try convertInlineFileDataToData(FilesV4UploadFileData.stream(stream))
        }
        #expect(error?.functionality == "streaming file upload")

        var terminations = terminated.stream.makeAsyncIterator()
        _ = await terminations.next()
    }
}
