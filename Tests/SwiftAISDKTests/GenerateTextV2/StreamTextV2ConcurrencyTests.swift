import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamTextV2 – concurrency & control")
struct StreamTextV2ConcurrencyTests {
    private let defaultUsage = LanguageModelV3Usage(
        inputTokens: 1,
        outputTokens: 2,
        totalTokens: 3,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )

    actor Flag { private var v = false; func set() { v = true }; func get() -> Bool { v } }

    private func waitUntil(_ deadline: TimeInterval = 1.0, _ predicate: @Sendable @escaping () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(deadline)
        while Date() < end {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await predicate()
    }

    @Test("two subscribers receive identical deltas (V2)")
    func twoSubscribersReceiveIdenticalDeltas() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "A", providerMetadata: nil),
            .textDelta(id: "A", delta: "X", providerMetadata: nil),
            .textDelta(id: "A", delta: "Y", providerMetadata: nil),
            .textEnd(id: "A", providerMetadata: nil),
            .finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(model: .v3(model), prompt: "hello")

        var s1: [String] = []
        var s2: [String] = []
        async let c1: Void = {
            for try await d in result.textStream { s1.append(d) }
        }()
        async let c2: Void = {
            for try await d in result.textStream { s2.append(d) }
        }()
        _ = try await result.content // wait for finish
        _ = try? await (c1, c2)
        #expect(s1 == ["X","Y"]) 
        #expect(s2 == ["X","Y"]) 
    }

    @Test("stop() emits abort before finish (V2)")
    func stopEmitsAbortBeforeFinish() async throws {
        let yielded = Flag()
        // Build a slow stream to allow stop() to interleave
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            Task {
                c.yield(.streamStart(warnings: []))
                c.yield(.responseMetadata(id: "id-0", modelId: "mock-model", timestamp: Date(timeIntervalSince1970: 0)))
                c.yield(.textStart(id: "A", providerMetadata: nil))
                c.yield(.textDelta(id: "A", delta: "X", providerMetadata: nil))
                await yielded.set()
                // leave some time for stop() to be requested
                try? await Task.sleep(nanoseconds: 60_000_000)
                c.yield(.textEnd(id: "A", providerMetadata: nil))
                c.yield(.finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil))
                c.finish()
            }
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hello"
        )

        // Wait until first delta observed from provider, then stop
        _ = await waitUntil(0.5) { await yielded.get() }
        result.stop()

        let partsCollected = try await result.collectFullStream()
        // Ensure .abort appears before .finish
        let idxAbort = partsCollected.firstIndex { if case .abort = $0 { return true } else { return false } }
        let idxFinish = partsCollected.firstIndex { if case .finish = $0 { return true } else { return false } }
        #expect(idxAbort != nil && idxFinish != nil && idxAbort! < idxFinish!)
    }
}
