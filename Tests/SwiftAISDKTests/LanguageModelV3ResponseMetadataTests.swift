import Testing
@testable import SwiftAISDK
import Foundation

@Suite("LanguageModelV3 ResponseMetadata")
struct LanguageModelV3ResponseMetadataTests {

    @Test("ResponseMetadata: encode/decode all fields")
    func v3_full_fields() throws {
        let ts = ISO8601DateFormatter().date(from: "2025-10-12T00:00:00Z")!
        let meta = LanguageModelV3ResponseMetadata(id: "r1", modelId: "gpt-x", timestamp: ts)
        let data = try JSONEncoder().encode(meta)
        let back = try JSONDecoder().decode(LanguageModelV3ResponseMetadata.self, from: data)
        #expect(back == meta)
    }

    @Test("ResponseMetadata: optional fields omitted")
    func v3_optional_omitted() throws {
        let meta = LanguageModelV3ResponseMetadata()
        let s = String(data: try JSONEncoder().encode(meta), encoding: .utf8)!
        #expect(s.contains("{}") || s == "{}" || s == "{\n}\n" || s == "{\n}\n")
    }
}

