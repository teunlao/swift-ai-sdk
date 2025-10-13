import Testing
@testable import AISDKProvider
import Foundation

@Test("DataContent encode: base64 string is plain string (no wrapper)")
func dataContent_encode_base64_plainString() throws {
    let dc = LanguageModelV2DataContent.base64("QUJD")
    let data = try JSONEncoder().encode(dc)
    let s = String(data: data, encoding: .utf8)!
    #expect(s == "\"QUJD\"")
}

@Test("DataContent encode: url is plain string (no wrapper)")
func dataContent_encode_url_plainString() throws {
    let url = URL(string: "https://example.com/a.png")!
    let dc = LanguageModelV2DataContent.url(url)
    let data = try JSONEncoder().encode(dc)

    // Decode back to verify it's a plain string (not wrapped object)
    let decoded = try JSONDecoder().decode(LanguageModelV2DataContent.self, from: data)
    #expect(decoded == dc)
}

@Test("DataContent encode: Data uses base64 string")
func dataContent_encode_data_base64() throws {
    let bytes = Data([0x00, 0x01, 0x02])
    let dc = LanguageModelV2DataContent.data(bytes)
    let data = try JSONEncoder().encode(dc)
    let s = String(data: data, encoding: .utf8)!
    #expect(s == "\"AAEC\"")
}

@Test("DataContent decode: legacy wrapped base64 object")
func dataContent_decode_legacy_base64_wrapper() throws {
    let json = "{\"type\":\"base64\",\"data\":\"QUJD\"}".data(using: .utf8)!
    let dc = try JSONDecoder().decode(LanguageModelV2DataContent.self, from: json)
    #expect(dc == .base64("QUJD"))
}

@Test("DataContent decode: legacy wrapped url object")
func dataContent_decode_legacy_url_wrapper() throws {
    let json = "{\"type\":\"url\",\"url\":\"https://example.com/a.png\"}".data(using: .utf8)!
    let dc = try JSONDecoder().decode(LanguageModelV2DataContent.self, from: json)
    #expect(dc == .url(URL(string: "https://example.com/a.png")!))
}
