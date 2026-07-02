import Foundation
import Testing
@testable import AISDKProvider

@Suite("SharedV4 Types")
struct SharedV4TypesTests {
    @Test("SharedV4FileData encodes raw bytes as upstream data variant")
    func fileDataEncodesRawBytesAsDataVariant() throws {
        let encoded = try JSONEncoder().encode(SharedV4FileData.data(Data("ABC".utf8)))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["type"] as? String == "data")
        #expect(object["data"] as? String == "QUJD")
    }

    @Test("SharedV4FileData decodes data variant string as base64 payload")
    func fileDataDecodesStringDataVariantAsBase64() throws {
        let json = #"{"type":"data","data":"QUJD"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SharedV4FileData.self, from: json)

        #expect(decoded == .base64("QUJD"))
    }

    @Test("SharedV4FileData round-trips url reference and text variants")
    func fileDataRoundTripsTaggedVariants() throws {
        let values: [SharedV4FileData] = [
            .url(URL(string: "https://example.com/file.pdf")!),
            .reference(["anthropic": "file-123"]),
            .text("inline document")
        ]

        for value in values {
            let encoded = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(SharedV4FileData.self, from: encoded)
            #expect(decoded == value)
        }
    }

    @Test("SharedV4Warning supports deprecated warning variant")
    func warningSupportsDeprecatedVariant() throws {
        let warning = SharedV4Warning.deprecated(
            setting: "maxTokens",
            message: "Use maxOutputTokens instead."
        )

        let encoded = try JSONEncoder().encode(warning)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(SharedV4Warning.self, from: encoded)

        #expect(object["type"] as? String == "deprecated")
        #expect(object["setting"] as? String == "maxTokens")
        #expect(object["message"] as? String == "Use maxOutputTokens instead.")
        #expect(decoded == warning)
    }

    @Test("SharedV4Warning preserves v3 warning variants")
    func warningPreservesExistingVariants() throws {
        let values: [SharedV4Warning] = [
            .unsupported(feature: "topK", details: nil),
            .compatibility(feature: "jsonMode", details: "translated"),
            .other(message: "provider warning")
        ]

        for value in values {
            let encoded = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(SharedV4Warning.self, from: encoded)
            #expect(decoded == value)
        }
    }
}
