import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

/**
 Tests for prepare headers utility.

 Port of tests from `@ai-sdk/ai/src/util/prepare-headers.test.ts`.

 - Note: Upstream uses JavaScript `Headers` API which is case-insensitive.
         Our Swift implementation uses dictionaries but performs case-insensitive
         matching to preserve the same behavior.
 */
@Suite("PrepareHeaders Tests")
struct PrepareHeadersTests {

    @Test("should set Content-Type header if not present")
    func testSetHeaderIfNotPresent() {
        let headers = prepareHeaders(
            [:],
            defaultHeaders: ["content-type": "application/json"]
        )

        // Case-insensitive check: our function preserves the default key casing
        #expect(headers["content-type"] == "application/json")
    }

    @Test("should not overwrite existing Content-Type header")
    func testDoNotOverwriteExisting() {
        let headers = prepareHeaders(
            ["Content-Type": "text/html"],
            defaultHeaders: ["content-type": "application/json"]
        )

        // Original header should be preserved (with its original casing)
        #expect(headers["Content-Type"] == "text/html")
        // Default header should NOT be added
        #expect(headers["content-type"] == nil)
    }

    @Test("should handle nil headers init")
    func testHandleNilInit() {
        let headers = prepareHeaders(
            nil,
            defaultHeaders: ["content-type": "application/json"]
        )

        #expect(headers["content-type"] == "application/json")
    }

    @Test("should preserve existing headers and add defaults")
    func testPreserveExistingAndAddDefaults() {
        let headers = prepareHeaders(
            ["init": "foo"],
            defaultHeaders: ["content-type": "application/json"]
        )

        #expect(headers["init"] == "foo")
        #expect(headers["content-type"] == "application/json")
    }

    @Test("should handle multiple existing and default headers")
    func testMultipleHeaders() {
        let headers = prepareHeaders(
            ["init": "foo", "extra": "bar"],
            defaultHeaders: ["content-type": "application/json", "user-agent": "SDK/1.0"]
        )

        #expect(headers["init"] == "foo")
        #expect(headers["extra"] == "bar")
        #expect(headers["content-type"] == "application/json")
        #expect(headers["user-agent"] == "SDK/1.0")
    }

    @Test("should handle case-insensitive header matching")
    func testCaseInsensitiveMatching() {
        // Existing header with different casing should prevent default from being added
        let headers = prepareHeaders(
            ["Content-Type": "text/html"],
            defaultHeaders: ["content-type": "application/json", "User-Agent": "SDK/1.0"]
        )

        // Original casing preserved
        #expect(headers["Content-Type"] == "text/html")
        // Default not added (case-insensitive match)
        #expect(headers["content-type"] == nil)
        // Other default added with its casing
        #expect(headers["User-Agent"] == "SDK/1.0")
    }
}
