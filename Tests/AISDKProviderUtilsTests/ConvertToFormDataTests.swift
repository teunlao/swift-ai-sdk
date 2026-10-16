import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("convertToFormData")
struct ConvertToFormDataTests {
    @Test("adds scalar values as multipart fields")
    func addsScalarValues() throws {
        let formData = convertToFormData(
            [
                "model": .value("gpt-image-1"),
                "prompt": .value("A cute cat"),
                "n": 2,
            ],
            boundary: "test-boundary"
        )

        let multipart = formData.build()
        let body = try #require(String(data: multipart.data, encoding: .utf8))

        #expect(multipart.contentType == "multipart/form-data; boundary=test-boundary")
        #expect(body.contains("Content-Disposition: form-data; name=\"model\""))
        #expect(body.contains("gpt-image-1"))
        #expect(body.contains("Content-Disposition: form-data; name=\"prompt\""))
        #expect(body.contains("A cute cat"))
        #expect(body.contains("Content-Disposition: form-data; name=\"n\""))
        #expect(body.contains("2"))
    }

    @Test("skips nil and empty array values")
    func skipsNilAndEmptyArrays() throws {
        let formData = convertToFormData(
            [
                "model": "test",
                "mask": nil,
                "images": .array([]),
            ],
            boundary: "test-boundary"
        )

        let body = try #require(String(data: formData.build().data, encoding: .utf8))

        #expect(body.contains("name=\"model\""))
        #expect(!body.contains("name=\"mask\""))
        #expect(!body.contains("name=\"images\""))
        #expect(!body.contains("name=\"images[]\""))
    }

    @Test("uses base key for single-element arrays")
    func usesBaseKeyForSingleElementArrays() throws {
        let formData = convertToFormData(
            [
                "image": .array([
                    .data(Data("image data".utf8), filename: "image.png", contentType: "image/png"),
                ]),
            ],
            boundary: "test-boundary"
        )

        let body = try #require(String(data: formData.build().data, encoding: .utf8))

        #expect(body.contains("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\""))
        #expect(body.contains("Content-Type: image/png"))
        #expect(!body.contains("name=\"image[]\""))
    }

    @Test("uses bracket suffix for multi-element arrays by default")
    func usesBracketSuffixForMultiElementArrays() throws {
        let formData = convertToFormData(
            [
                "tags": .array(["cat", "cute", "animal"]),
            ],
            boundary: "test-boundary"
        )

        let body = try #require(String(data: formData.build().data, encoding: .utf8))

        #expect(!body.contains("name=\"tags\""))
        #expect(body.components(separatedBy: "name=\"tags[]\"").count - 1 == 3)
        #expect(body.contains("cat"))
        #expect(body.contains("cute"))
        #expect(body.contains("animal"))
    }

    @Test("can omit bracket suffix for multi-element arrays")
    func canOmitBracketSuffixForMultiElementArrays() throws {
        let formData = convertToFormData(
            [
                "image": .array([
                    .data(Data("one".utf8), filename: "one.png", contentType: "image/png"),
                    .data(Data("two".utf8), filename: "two.jpg", contentType: "image/jpeg"),
                ]),
            ],
            useArrayBrackets: false,
            boundary: "test-boundary"
        )

        let body = try #require(String(data: formData.build().data, encoding: .utf8))

        #expect(!body.contains("name=\"image[]\""))
        #expect(body.components(separatedBy: "name=\"image\"").count - 1 == 2)
        #expect(body.contains("filename=\"one.png\""))
        #expect(body.contains("filename=\"two.jpg\""))
    }
}

@Suite("MultipartFormDataBuilder")
struct MultipartFormDataBuilderTests {
    @Test("unnamed files retain file semantics and binary bytes")
    func unnamedFile() {
        var builder = MultipartFormDataBuilder(boundary: "test-boundary")
        builder.appendField(name: "field", value: "value")
        let bytes = Data([0x00, 0xFF, 0x0D, 0x0A])
        builder.appendFile(name: "file", filename: nil, data: bytes)

        let multipart = builder.build()
        var expected = Data((
            "--test-boundary\r\nContent-Disposition: form-data; name=\"field\"\r\n\r\nvalue\r\n" +
            "--test-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"blob\"\r\n" +
            "Content-Type: application/octet-stream\r\n\r\n"
        ).utf8)
        expected.append(bytes)
        expected.append(Data("\r\n--test-boundary--\r\n".utf8))

        #expect(multipart.contentType == "multipart/form-data; boundary=test-boundary")
        #expect(multipart.data == expected)
    }

    @Test("disposition parameters use native FormData escaping")
    func dispositionEscaping() {
        var builder = MultipartFormDataBuilder(boundary: "test-boundary")
        builder.appendField(name: "field\rname\nline\r\npair\"quote\\slash%", value: "value")
        builder.appendFile(
            name: "file\rname\nline\r\npair\"quote\\slash%",
            filename: "path/quo\"te\\slash\rname\nline\r\npair",
            contentType: "IMAGE/PNG;X=Y",
            data: Data("binary".utf8)
        )

        let expected = Data((
            "--test-boundary\r\n" +
            "Content-Disposition: form-data; name=\"field%0D%0Aname%0D%0Aline%0D%0Apair%22quote\\slash%\"\r\n\r\nvalue\r\n" +
            "--test-boundary\r\n" +
            "Content-Disposition: form-data; name=\"file%0D%0Aname%0D%0Aline%0D%0Apair%22quote\\slash%\"; " +
            "filename=\"path/quo%22te\\slash%0Dname%0Aline%0D%0Apair\"\r\n" +
            "Content-Type: image/png;x=y\r\n\r\nbinary\r\n" +
            "--test-boundary--\r\n"
        ).utf8)

        #expect(builder.build().data == expected)
    }

    @Test("invalid Blob MIME types use the binary default", arguments: [
        "", "text/plain\r\nX-Injected: yes", "text/pläin"
    ])
    func invalidContentType(_ contentType: String) {
        var builder = MultipartFormDataBuilder(boundary: "test-boundary")
        builder.appendFile(name: "file", filename: "payload.bin", contentType: contentType, data: Data([0x01]))

        var expected = Data((
            "--test-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"payload.bin\"\r\n" +
            "Content-Type: application/octet-stream\r\n\r\n"
        ).utf8)
        expected.append(0x01)
        expected.append(Data("\r\n--test-boundary--\r\n".utf8))

        #expect(builder.build().data == expected)
    }
}
