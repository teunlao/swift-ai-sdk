import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for User Agent utilities.
 Port of tests from:
 - get-runtime-environment-user-agent.test.ts
 - with-user-agent-suffix.test.ts
 - remove-undefined-entries implicit tests
 */
struct UserAgentTests {
    // MARK: - GetRuntimeEnvironmentUserAgent

    @Test("getRuntimeEnvironmentUserAgent defaults to unknown runtime")
    func testRuntimeEnvironmentUnknown() {
        let userAgent = getRuntimeEnvironmentUserAgent()
        #expect(userAgent == "runtime/unknown")
    }

    @Test("getRuntimeEnvironmentUserAgent detects browser")
    func testRuntimeEnvironmentBrowser() {
        let snapshot = RuntimeEnvironmentSnapshot(hasWindow: true)
        #expect(getRuntimeEnvironmentUserAgent(snapshot) == "runtime/browser")
    }

    @Test("getRuntimeEnvironmentUserAgent uses navigator user agent")
    func testRuntimeEnvironmentNavigator() {
        let snapshot = RuntimeEnvironmentSnapshot(navigatorUserAgent: "Test-UA")
        #expect(getRuntimeEnvironmentUserAgent(snapshot) == "runtime/test-ua")
    }

    @Test("getRuntimeEnvironmentUserAgent detects Node.js")
    func testRuntimeEnvironmentNode() {
        let snapshot = RuntimeEnvironmentSnapshot(
            processVersionsNode: "v20.0.0",
            processVersion: "v20.0.0"
        )
        #expect(getRuntimeEnvironmentUserAgent(snapshot) == "runtime/node.js/v20.0.0")
    }

    @Test("getRuntimeEnvironmentUserAgent detects Edge runtime")
    func testRuntimeEnvironmentEdgeRuntime() {
        let snapshot = RuntimeEnvironmentSnapshot(edgeRuntime: true)
        #expect(getRuntimeEnvironmentUserAgent(snapshot) == "runtime/vercel-edge")
    }

    // MARK: - WithUserAgentSuffix

    @Test("withUserAgentSuffix creates new user-agent when none exists")
    func testCreateUserAgent() {
        let headers = [
            "content-type": "application/json",
            "authorization": "Bearer token123"
        ]

        let result = withUserAgentSuffix(headers, "ai-sdk/0.0.0", "provider/test")

        #expect(result["user-agent"] == "ai-sdk/0.0.0 provider/test")
        #expect(result["content-type"] == "application/json")
        #expect(result["authorization"] == "Bearer token123")
    }

    @Test("withUserAgentSuffix appends to existing user-agent")
    func testAppendUserAgent() {
        let headers = [
            "user-agent": "TestApp/1.0",
            "accept": "application/json"
        ]

        let result = withUserAgentSuffix(headers, "ai-sdk/0.0.0", "provider/anthropic")

        #expect(result["user-agent"] == "TestApp/1.0 ai-sdk/0.0.0 provider/anthropic")
        #expect(result["accept"] == "application/json")
    }

    @Test("withUserAgentSuffix removes undefined entries")
    func testRemoveUndefinedEntries() {
        let headers: [String: String?] = [
            "content-type": "application/json",
            "authorization": nil,
            "user-agent": "TestApp/1.0",
            "accept": "application/json"
        ]

        let result = withUserAgentSuffix(headers, "ai-sdk/0.0.0")

        #expect(result["user-agent"] == "TestApp/1.0 ai-sdk/0.0.0")
        #expect(result["content-type"] == "application/json")
        #expect(result["accept"] == "application/json")
        #expect(result["authorization"] == nil)
    }

    @Test("withUserAgentSuffix handles nil headers")
    func testNilHeaders() {
        let result = withUserAgentSuffix(nil, "ai-sdk/0.0.0", "provider/test")

        #expect(result["user-agent"] == "ai-sdk/0.0.0 provider/test")
        #expect(result.count == 1)
    }

    @Test("withUserAgentSuffix handles empty suffix parts")
    func testEmptySuffixParts() {
        let headers = ["user-agent": "TestApp/1.0"]

        let result = withUserAgentSuffix(headers, "", "ai-sdk/0.0.0", "")

        #expect(result["user-agent"] == "TestApp/1.0 ai-sdk/0.0.0")
    }

    // MARK: - RemoveUndefinedEntries

    @Test("removeUndefinedEntries filters nil values")
    func testRemoveUndefined() {
        let input: [String: String?] = [
            "a": "value1",
            "b": nil,
            "c": "value2",
            "d": nil
        ]

        let result = removeUndefinedEntries(input)

        #expect(result["a"] == "value1")
        #expect(result["c"] == "value2")
        #expect(result["b"] == nil)
        #expect(result["d"] == nil)
        #expect(result.count == 2)
    }

    @Test("removeUndefinedEntries handles empty dict")
    func testRemoveUndefinedEmpty() {
        let input: [String: String?] = [:]
        let result = removeUndefinedEntries(input)
        #expect(result.isEmpty)
    }

    @Test("removeUndefinedEntries handles all nil values")
    func testRemoveUndefinedAllNil() {
        let input: [String: String?] = [
            "a": nil,
            "b": nil
        ]
        let result = removeUndefinedEntries(input)
        #expect(result.isEmpty)
    }

    @Test("removeUndefinedEntries preserves falsy string values (empty string)")
    func testPreserveFalsyValues() {
        // In TypeScript, "", 0, false are falsy but should be preserved.
        // In Swift, we test that empty string (falsy in JS) is preserved.
        let input: [String: String?] = [
            "empty": "",           // Empty string (falsy in JavaScript)
            "value": "test",
            "undefined": nil       // Should be removed
        ]

        let result = removeUndefinedEntries(input)

        #expect(result["empty"] == "")     // Empty string preserved
        #expect(result["value"] == "test")
        #expect(result["undefined"] == nil) // Removed
        #expect(result.count == 2)
    }

    // MARK: - WithUserAgentSuffix - Case Sensitivity

    @Test("withUserAgentSuffix handles case-sensitive header keys")
    func testCaseSensitiveHeaders() {
        // Note: HTTP headers are case-insensitive per RFC 2616, but Swift Dictionary is case-sensitive.
        // This test documents the behavior: we use lowercase "user-agent" convention.

        let headersLowercase = ["user-agent": "TestApp/1.0"]
        let resultLower = withUserAgentSuffix(headersLowercase, "ai-sdk/0.0.0")
        #expect(resultLower["user-agent"] == "TestApp/1.0 ai-sdk/0.0.0")

        // If someone uses capitalized "User-Agent", it won't be found (dictionary is case-sensitive)
        let headersCapitalized = ["User-Agent": "TestApp/1.0"]
        let resultCap = withUserAgentSuffix(headersCapitalized, "ai-sdk/0.0.0")

        #expect(resultCap["User-Agent"] == nil)  // Headers normalized to lowercase keys
        #expect(resultCap["user-agent"] == "TestApp/1.0 ai-sdk/0.0.0")
        #expect(resultCap.count == 1)
    }
}
