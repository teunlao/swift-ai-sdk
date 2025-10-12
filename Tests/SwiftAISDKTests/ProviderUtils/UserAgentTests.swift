import Testing
@testable import SwiftAISDK

/**
 Tests for User Agent utilities.
 Port of tests from:
 - get-runtime-environment-user-agent.test.ts
 - with-user-agent-suffix.test.ts
 - remove-undefined-entries implicit tests
 */
struct UserAgentTests {
    // MARK: - GetRuntimeEnvironmentUserAgent

    @Test("getRuntimeEnvironmentUserAgent returns platform-specific runtime")
    func testGetRuntimeEnvironmentUserAgent() {
        let userAgent = getRuntimeEnvironmentUserAgent()

        #if os(macOS)
        #expect(userAgent == "runtime/swift-macos")
        #elseif os(iOS)
        #expect(userAgent == "runtime/swift-ios")
        #elseif os(Linux)
        #expect(userAgent == "runtime/swift-linux")
        #else
        #expect(userAgent.hasPrefix("runtime/swift"))
        #endif
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
}
