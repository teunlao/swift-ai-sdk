/**
 Mock implementation of TranscriptionModelV4 for testing.

 Port direction: `@ai-sdk/ai/src/test/mock-transcription-model-v4.ts`.
 */

import AISDKProvider

public final class MockTranscriptionModelV4: TranscriptionModelV4, @unchecked Sendable {
    public let specificationVersion: String = "v4"
    public let provider: String
    public let modelId: String

    public private(set) var doGenerateCalls: [TranscriptionModelV4CallOptions] = []
    public private(set) var doStreamCalls: [TranscriptionModelV4StreamOptions] = []

    private let doGenerateHandler: @Sendable (TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result
    private let doStreamHandler: @Sendable (TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult

    public init(
        provider: String = "mock-provider",
        modelId: String = "mock-model-id",
        doGenerate: (@Sendable (TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result)? = nil,
        doStream: (@Sendable (TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult)? = nil
    ) {
        self.provider = provider
        self.modelId = modelId
        self.doGenerateHandler = doGenerate ?? { _ in try notImplemented() }
        self.doStreamHandler = doStream ?? { _ in try notImplemented() }
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        doGenerateCalls.append(options)
        return try await doGenerateHandler(options)
    }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        doStreamCalls.append(options)
        return try await doStreamHandler(options)
    }
}
