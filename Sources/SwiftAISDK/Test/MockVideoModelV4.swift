/**
 Mock implementation of VideoModelV4 for testing.

 Port direction: `@ai-sdk/ai/src/test/mock-video-model-v4.ts`.
 */

import Foundation
import AISDKProvider

public final class MockVideoModelV4: VideoModelV4, @unchecked Sendable {
    public let specificationVersion: String = "v4"
    public let provider: String
    public let modelId: String
    public let maxVideosPerCall: VideoModelV4MaxVideosPerCall

    public private(set) var doGenerateCalls: [VideoModelV4CallOptions] = []

    private let doGenerateHandler: @Sendable (VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult

    public init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        maxVideosPerCall: VideoModelV4MaxVideosPerCall = .value(1),
        doGenerate: (@Sendable (VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult)? = nil
    ) {
        self.provider = provider
        self.modelId = modelId
        self.maxVideosPerCall = maxVideosPerCall
        self.doGenerateHandler = doGenerate ?? { _ in try notImplemented() }
    }

    public func doGenerate(options: VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult {
        doGenerateCalls.append(options)
        return try await doGenerateHandler(options)
    }
}
