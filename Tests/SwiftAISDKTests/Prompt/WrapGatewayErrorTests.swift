import Testing
import Foundation
@testable import SwiftAISDK

/**
 Tests for wrapGatewayError function.

 Note: Upstream (@ai-sdk/ai/src/prompt/wrap-gateway-error.ts) has no tests.
 These tests verify basic functionality and error wrapping behavior.
 */

@Suite("wrapGatewayError")
struct WrapGatewayErrorTests {

    @Test("should wrap GatewayAuthenticationError in AISDKError")
    func wrapsGatewayAuthenticationError() {
        let gatewayError = GatewayAuthenticationError(
            message: "Invalid API key",
            statusCode: 401
        )

        let result = wrapGatewayError(gatewayError)

        // Should be wrapped in GatewayErrorWrapper
        #expect(result is GatewayErrorWrapper)

        if let wrapped = result as? GatewayErrorWrapper {
            #expect(wrapped.name == "GatewayError")
            #expect(wrapped.message.contains("Vercel AI Gateway access failed"))
            #expect(wrapped.message.contains("@ai-sdk/openai"))
            #expect(wrapped.cause is GatewayAuthenticationError)
        }
    }

    @Test("should wrap GatewayModelNotFoundError in AISDKError")
    func wrapsGatewayModelNotFoundError() {
        let gatewayError = GatewayModelNotFoundError(
            message: "Model xyz not found",
            modelId: "xyz"
        )

        let result = wrapGatewayError(gatewayError)

        // Should be wrapped in GatewayErrorWrapper
        #expect(result is GatewayErrorWrapper)

        if let wrapped = result as? GatewayErrorWrapper {
            #expect(wrapped.name == "GatewayError")
            #expect(wrapped.message.contains("Vercel AI Gateway access failed"))
            #expect(wrapped.cause is GatewayModelNotFoundError)
        }
    }

    @Test("should not wrap non-Gateway errors")
    func doesNotWrapNonGatewayErrors() {
        struct SomeOtherError: Error {}
        let otherError = SomeOtherError()

        let result = wrapGatewayError(otherError)

        // Should return original error unchanged
        #expect(result is SomeOtherError)
    }

    @Test("should not wrap nil")
    func doesNotWrapNil() {
        let result = wrapGatewayError(nil)
        #expect(result == nil)
    }

    @Test("should not wrap AISDKError")
    func doesNotWrapAISDKError() {
        struct CustomAISDKError: AISDKError {
            static let errorDomain = "test.error"
            let name = "TestError"
            let message = "Test message"
            let cause: Error? = nil
        }

        let error = CustomAISDKError()
        let result = wrapGatewayError(error)

        // Should return original error unchanged
        #expect(result is CustomAISDKError)
    }

    @Test("wrapped error should conform to AISDKError protocol")
    func wrappedErrorConformsToAISDKError() {
        let gatewayError = GatewayAuthenticationError()
        let result = wrapGatewayError(gatewayError)

        guard let wrapped = result as? GatewayErrorWrapper else {
            Issue.record("Expected GatewayErrorWrapper")
            return
        }

        // Verify AISDKError protocol conformance
        #expect(wrapped is AISDKError)
        #expect(GatewayErrorWrapper.errorDomain == "vercel.ai.GatewayError")
        #expect(wrapped.name == "GatewayError")
        #expect(!wrapped.message.isEmpty)
    }
}
