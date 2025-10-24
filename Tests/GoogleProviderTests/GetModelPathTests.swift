import Foundation
import Testing
@testable import GoogleProvider

/**
 Tests for getGoogleModelPath function.

 Port of `@ai-sdk/google/src/get-model-path.test.ts`.
 */

@Suite("GetModelPath")
struct GetModelPathTests {
    @Test("should pass through model path for models/*")
    func passThroughModelsPath() throws {
        let result = getGoogleModelPath("models/some-model")
        #expect(result == "models/some-model")
    }

    @Test("should pass through model path for tunedModels/*")
    func passThroughTunedModelsPath() throws {
        let result = getGoogleModelPath("tunedModels/some-model")
        #expect(result == "tunedModels/some-model")
    }

    @Test("should add model path prefix to models without slash")
    func addModelPathPrefix() throws {
        let result = getGoogleModelPath("some-model")
        #expect(result == "models/some-model")
    }
}
