import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamTextV2 – error & replay")
struct StreamTextV2ErrorAndReplayTests {
    private let defaultUsage = LanguageModelV3Usage(
        inputTokens: 1,
        outputTokens: 2,
        totalTokens: 3,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )

    @Test("provider error terminates with error and no finish (V2)")
    func providerErrorTerminates() async throws {
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            c.yield(.streamStart(warnings: []))
            c.yield(.responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)))
            c.yield(.textStart(id: "A", providerMetadata: nil))
            c.yield(.textDelta(id: "A", delta: "X", providerMetadata: nil))
            c.yield(.error(error: .string("boom")))
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(model: .v3(model), prompt: "hi")

        var gotError = false
        do {
            _ = try await result.collectFullStream()
        } catch { gotError = true }
        #expect(gotError)
    }

    @Test("late subscriber gets replay and terminal (V2)")
    func lateSubscriberGetsReplay() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "A", providerMetadata: nil),
            .textDelta(id: "A", delta: "X", providerMetadata: nil),
            .textEnd(id: "A", providerMetadata: nil),
            .finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(model: .v3(model), prompt: "hi")

        // Drain fully first
        _ = try await result.collectFullStream()
        // Late subscribe
        let replay = try await result.collectFullStream()
        // Expect full framing present
        let hasStart = replay.contains { if case .start = $0 { return true } else { return false } }
        let hasFinish = replay.contains { if case .finish = $0 { return true } else { return false } }
        #expect(hasStart && hasFinish)
    }
}

