/**
 Test helper for verifying NoObjectGeneratedError instances.

 Port of `@ai-sdk/ai/src/error/verify-no-object-generated-error.ts`.

 This helper function is used in tests to verify that a NoObjectGeneratedError
 contains the expected values.
 */

import Testing
import Foundation
@testable import SwiftAISDK
@testable import AISDKProvider

/**
 Expected values for NoObjectGeneratedError verification.

 Maps to the anonymous object type in TypeScript's `expected` parameter.
 */
public struct ExpectedNoObjectGeneratedError: Sendable {
    public let message: String
    public let response: LanguageModelResponseMetadata
    public let usage: LanguageModelUsage
    public let finishReason: FinishReason

    public init(
        message: String,
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        finishReason: FinishReason
    ) {
        self.message = message
        self.response = response
        self.usage = usage
        self.finishReason = finishReason
    }
}

/**
 Verify that an error is a NoObjectGeneratedError with expected properties.

 - Parameters:
   - error: The error to verify
   - expected: Expected values for the error
 */
public func verifyNoObjectGeneratedError(
    _ error: any Error,
    expected: ExpectedNoObjectGeneratedError
) {
    #expect(NoObjectGeneratedError.isInstance(error))

    guard let noObjectError = error as? NoObjectGeneratedError else {
        Issue.record("Expected NoObjectGeneratedError, got \(type(of: error))")
        return
    }

    #expect(noObjectError.message == expected.message)
    #expect(noObjectError.response == expected.response)
    #expect(noObjectError.usage == expected.usage)
    #expect(noObjectError.finishReason == expected.finishReason)
}
