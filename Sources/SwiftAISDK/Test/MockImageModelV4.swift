/**
 Mock implementation of ImageModelV4 for testing.

 Port direction: `@ai-sdk/ai/src/test/mock-image-model-v4.ts`.
 */

import Foundation
import AISDKProvider

public final class MockImageModelV4: ImageModelV4, @unchecked Sendable {
    public let specificationVersion: String = "v4"
    public let provider: String
    public let modelId: String
    public let maxImagesPerCall: ImageModelV4MaxImagesPerCall

    public private(set) var doGenerateCalls: [ImageModelV4CallOptions] = []

    private let doGenerateHandler: @Sendable (ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult

    public init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        maxImagesPerCall: ImageModelV4MaxImagesPerCall = .value(1),
        doGenerate: (@Sendable (ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult)? = nil
    ) {
        self.provider = provider
        self.modelId = modelId
        self.maxImagesPerCall = maxImagesPerCall
        self.doGenerateHandler = doGenerate ?? { _ in try notImplemented() }
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        doGenerateCalls.append(options)
        return try await doGenerateHandler(options)
    }
}
