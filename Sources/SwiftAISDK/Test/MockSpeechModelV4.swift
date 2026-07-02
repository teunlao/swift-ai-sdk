/**
 Mock implementation of SpeechModelV4 for testing.

 Port direction: `@ai-sdk/ai/src/test/mock-speech-model-v4.ts`.
 */

import AISDKProvider

public final class MockSpeechModelV4: SpeechModelV4, @unchecked Sendable {
    public let specificationVersion: String = "v4"
    public let provider: String
    public let modelId: String

    public private(set) var doGenerateCalls: [SpeechModelV4CallOptions] = []

    private let doGenerateHandler: @Sendable (SpeechModelV4CallOptions) async throws -> SpeechModelV4Result

    public init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        doGenerate: (@Sendable (SpeechModelV4CallOptions) async throws -> SpeechModelV4Result)? = nil
    ) {
        self.provider = provider
        self.modelId = modelId
        self.doGenerateHandler = doGenerate ?? { _ in try notImplemented() }
    }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        doGenerateCalls.append(options)
        return try await doGenerateHandler(options)
    }
}
