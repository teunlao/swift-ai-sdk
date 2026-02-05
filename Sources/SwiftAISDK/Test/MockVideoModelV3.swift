/**
 Mock implementation of VideoModelV3 for testing.

 Port of `@ai-sdk/ai/src/test/mock-video-model-v3.ts`.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class MockVideoModelV3: VideoModelV3, @unchecked Sendable {
    public let provider: String
    public let modelId: String
    public let maxVideosPerCall: VideoModelV3MaxVideosPerCall

    public private(set) var doGenerateCalls: [VideoModelV3CallOptions] = []

    private let doGenerateHandler: @Sendable (VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult

    public init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        maxVideosPerCall: VideoModelV3MaxVideosPerCall = .value(1),
        doGenerate: (@Sendable (VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult)? = nil
    ) {
        self.provider = provider
        self.modelId = modelId
        self.maxVideosPerCall = maxVideosPerCall
        self.doGenerateHandler = doGenerate ?? { _ in try notImplemented() }
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        doGenerateCalls.append(options)
        return try await doGenerateHandler(options)
    }
}

