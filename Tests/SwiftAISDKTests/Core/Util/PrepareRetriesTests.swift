/**
 Tests for prepareRetries function.

 Port of `@ai-sdk/ai/src/util/prepare-retries.test.ts`.
 */

import Testing
@testable import SwiftAISDK

@Suite("PrepareRetries Tests")
struct PrepareRetriesTests {
    @Test("should set default values correctly when no input is provided")
    func defaultValues() throws {
        let defaultResult = try prepareRetries(
            maxRetries: nil,
            abortSignal: nil
        )

        #expect(defaultResult.maxRetries == 2)
    }
}
