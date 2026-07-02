import Testing
@testable import AISDKProviderUtils

@Suite("normalizeHeaders")
struct NormalizeHeadersTests {
    @Test("returns empty dictionary for nil headers")
    func returnsEmptyDictionaryForNilHeaders() {
        let headers: [String: String?]? = nil
        #expect(normalizeHeaders(headers).isEmpty)
    }

    @Test("normalizes record keys and filters nil values")
    func normalizesRecordKeysAndFiltersNilValues() {
        let headers: [String: String?] = [
            "Authorization": "Bearer token",
            "X-Feature": nil,
            "Content-Type": "application/json"
        ]

        #expect(normalizeHeaders(headers) == [
            "authorization": "Bearer token",
            "content-type": "application/json"
        ])
    }

    @Test("normalizes tuple entries and filters nil values")
    func normalizesTupleEntriesAndFiltersNilValues() {
        let headers: [(String, String?)] = [
            ("Authorization", "Bearer token"),
            ("X-Feature", "beta"),
            ("X-Ignore", nil)
        ]

        #expect(normalizeHeaders(headers) == [
            "authorization": "Bearer token",
            "x-feature": "beta"
        ])
    }

    @Test("lowercases uppercase keys")
    func lowercasesUppercaseKeys() {
        #expect(normalizeHeaders([
            "CONTENT-TYPE": "application/json",
            "X-CUSTOM-HEADER": "test-value"
        ] as [String: String?]) == [
            "content-type": "application/json",
            "x-custom-header": "test-value"
        ])
    }
}
