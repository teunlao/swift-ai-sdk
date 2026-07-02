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
