/**
 Mock implementation of ImageModelV3 for testing.

 Port of `@ai-sdk/ai/src/test/mock-image-model-v3.ts`.

 Provides configurable behavior for `doGenerate` and exposes recorded calls.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class MockImageModelV3: ImageModelV3, @unchecked Sendable {
    public let provider: String
    public let modelId: String
    public let maxImagesPerCall: ImageModelV3MaxImagesPerCall

    public private(set) var doGenerateCalls: [ImageModelV3CallOptions] = []

    private let doGenerateHandler: @Sendable (ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult

    /**
     Create a mock image model.

     - Parameters:
       - provider: Provider identifier (default: `"mock-provider"`).
       - modelId: Model identifier (default: `"mock-model-id"`).
       - maxImagesPerCall: Maximum images per call configuration (default: `.value(1)`).
       - doGenerate: Custom behavior for `doGenerate`. Defaults to throwing `NotImplementedError`.
     */
    public init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        maxImagesPerCall: ImageModelV3MaxImagesPerCall = .value(1),
        doGenerate: (@Sendable (ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult)? = nil
    ) {
        self.provider = provider
        self.modelId = modelId
        self.maxImagesPerCall = maxImagesPerCall
        self.doGenerateHandler = doGenerate ?? { _ in try notImplemented() }
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        doGenerateCalls.append(options)
        return try await doGenerateHandler(options)
    }
}
