import Testing
@testable import SwiftAISDK

/**
 Tests for combineHeaders utility function.

 Port of behavior tests for `@ai-sdk/provider-utils/src/combine-headers.ts`

 Note: The original TypeScript file has no dedicated test file, but the function is
 extensively used throughout the codebase. These tests verify expected behavior
 based on usage patterns.
 */
struct CombineHeadersTests {
    @Test("combineHeaders: empty input returns empty dictionary")
    func testEmptyInput() {
        let result = combineHeaders()
        #expect(result.isEmpty)
    }

    @Test("combineHeaders: single dictionary returns same dictionary")
    func testSingleDictionary() {
        let headers = ["Content-Type": "application/json"]
        let result = combineHeaders(headers)

        #expect(result["Content-Type"] == "application/json")
        #expect(result.count == 1)
    }

    @Test("combineHeaders: combines multiple dictionaries")
    func testMultipleDictionaries() {
        let headers1 = ["Content-Type": "application/json"]
        let headers2 = ["Authorization": "Bearer token"]
        let headers3 = ["User-Agent": "SwiftAISDK"]

        let result = combineHeaders(headers1, headers2, headers3)

        #expect(result["Content-Type"] == "application/json")
        #expect(result["Authorization"] == "Bearer token")
        #expect(result["User-Agent"] == "SwiftAISDK")
        #expect(result.count == 3)
    }

    @Test("combineHeaders: later values override earlier ones")
    func testOverrideValues() {
        let headers1 = ["Content-Type": "text/plain", "X-Custom": "value1"]
        let headers2 = ["Content-Type": "application/json"]

        let result = combineHeaders(headers1, headers2)

        #expect(result["Content-Type"] == "application/json") // Overridden
        #expect(result["X-Custom"] == "value1") // Preserved
        #expect(result.count == 2)
    }

    @Test("combineHeaders: handles nil dictionaries")
    func testNilDictionaries() {
        let headers1: [String: String?]? = ["Content-Type": "application/json"]
        let headers2: [String: String?]? = nil
        let headers3: [String: String?]? = ["Authorization": "Bearer token"]

        let result = combineHeaders(headers1, headers2, headers3)

        #expect(result["Content-Type"] == "application/json")
        #expect(result["Authorization"] == "Bearer token")
        #expect(result.count == 2)
    }

    @Test("combineHeaders: handles nil values in dictionaries")
    func testNilValues() {
        let headers1: [String: String?] = ["Content-Type": "application/json"]
        let headers2: [String: String?] = ["Authorization": nil]

        let result = combineHeaders(headers1, headers2)

        #expect(result["Content-Type"] == "application/json")
        // Check that key exists but value is nil (double optional handling)
        #expect(result.keys.contains("Authorization"))
        #expect(result["Authorization"] as? String == nil)
        #expect(result.count == 2)
    }

    @Test("combineHeaders: nil value can override non-nil value")
    func testNilOverridesValue() {
        let headers1: [String: String?] = ["Content-Type": "application/json"]
        let headers2: [String: String?] = ["Content-Type": nil]

        let result = combineHeaders(headers1, headers2)

        // Check that key exists but value is nil (overridden)
        #expect(result.keys.contains("Content-Type"))
        #expect(result["Content-Type"] as? String == nil)
        #expect(result.count == 1)
    }

    @Test("combineHeaders: all nil dictionaries returns empty")
    func testAllNilDictionaries() {
        let headers1: [String: String?]? = nil
        let headers2: [String: String?]? = nil
        let headers3: [String: String?]? = nil

        let result = combineHeaders(headers1, headers2, headers3)

        #expect(result.isEmpty)
    }

    @Test("combineHeaders: empty dictionaries returns empty")
    func testEmptyDictionaries() {
        let headers1: [String: String?] = [:]
        let headers2: [String: String?] = [:]

        let result = combineHeaders(headers1, headers2)

        #expect(result.isEmpty)
    }

    @Test("combineHeaders: complex merge scenario")
    func testComplexMerge() {
        let baseHeaders: [String: String?] = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        let customHeaders: [String: String?]? = [
            "Authorization": "Bearer token",
            "X-Custom-Header": "custom-value"
        ]
        let overrideHeaders: [String: String?] = [
            "Content-Type": "text/plain",
            "X-Override": nil
        ]

        let result = combineHeaders(baseHeaders, customHeaders, overrideHeaders)

        #expect(result["Content-Type"] == "text/plain") // Overridden
        #expect(result["Accept"] == "application/json") // Preserved
        #expect(result["Authorization"] == "Bearer token") // Added
        #expect(result["X-Custom-Header"] == "custom-value") // Added
        // Check that X-Override key exists but value is nil
        #expect(result.keys.contains("X-Override"))
        #expect(result["X-Override"] as? String == nil)
        #expect(result.count == 5)
    }
}
