import Testing
@testable import SwiftAISDK
import Foundation

@Suite("LanguageModelV2 ResponseMetadata")
struct LanguageModelV2ResponseMetadataTests {

    @Test("ResponseMetadata: encode/decode all fields")
    func full_fields() throws {
        let ts = ISO8601DateFormatter().date(from: "2025-10-12T00:00:00Z")!
        let meta = LanguageModelV2ResponseMetadata(id: "r1", modelId: "gpt-x", timestamp: ts)
        let data = try JSONEncoder().encode(meta)
        let back = try JSONDecoder().decode(LanguageModelV2ResponseMetadata.self, from: data)
        #expect(back == meta)
    }

    @Test("ResponseMetadata: optional fields omitted")
    func optional_omitted() throws {
        let meta = LanguageModelV2ResponseMetadata()
        let s = String(data: try JSONEncoder().encode(meta), encoding: .utf8)!
        // Should be an empty JSON object or object without fields
        #expect(s.contains("{}") || s == "{}" || s == "{\n}\n" || s == "{\n}\n")
    }
}

