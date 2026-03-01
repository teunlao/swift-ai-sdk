import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – concurrency & control")
struct StreamTextConcurrencyTests {
    private let defaultUsage = LanguageModelV3Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 2))

    actor Flag { private var v = false; func set() { v = true }; func get() -> Bool { v } }
    actor StringCollector {
        private var values: [String] = []
        func append(_ value: String) { values.append(value) }
        func snapshot() -> [String] { values }
    }

    private func waitUntil(_ deadline: TimeInterval = 1.0, _ predicate: @Sendable @escaping () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(deadline)
        while Date() < end {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await predicate()
    }

    @Test("two subscribers receive identical deltas")
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
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(model: .v3(model), prompt: "hello")

        let collector1 = StringCollector()
        let collector2 = StringCollector()
        async let c1: Void = {
            for try await d in result.textStream { await collector1.append(d) }
        }()
        async let c2: Void = {
            for try await d in result.textStream { await collector2.append(d) }
        }()
        _ = try await result.content // wait for finish
        _ = try? await (c1, c2)
        let snapshot1 = await collector1.snapshot()
        let snapshot2 = await collector2.snapshot()
        #expect(snapshot1 == ["X","Y"])
        #expect(snapshot2 == ["X","Y"])
    }

    @Test("stop() emits abort before finish")
    func stopEmitsAbortBeforeFinish() async throws {
        let yielded = Flag()
        // Build a slow stream to allow stop() to interleave
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            _ = Task {
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
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
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

    actor EventLog {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
    }

    @Test("two tool calls in one response execute concurrently, not sequentially",
          .timeLimit(.minutes(1)))
    func twoToolCallsExecuteConcurrently() async throws {
        let log = EventLog()

        // Provider stream emits two toolCalls before .finish — mimics a model
        // requesting parallel tool use in one response
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "step-1", modelId: "mock-model", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-A",
                toolName: "slow_tool",
                input: "{\"id\":\"A\"}",
                providerExecuted: false,
                providerMetadata: nil
            )),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-B",
                toolName: "slow_tool",
                input: "{\"id\":\"B\"}",
                providerExecuted: false,
                providerMetadata: nil
            )),
            .finish(
                finishReason: LanguageModelV3FinishReason(unified: .toolCalls),
                usage: defaultUsage,
                providerMetadata: nil
            ),
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }

        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        let tools: ToolSet = [
            "slow_tool": Tool(
                description: "Sleeps then returns",
                inputSchema: FlexibleSchema(jsonSchema(.object([
                    "type": .string("object"),
                    "properties": .object(["id": .object(["type": .string("string")])]),
                    "required": .array([.string("id")])
                ]))),
                needsApproval: .never,
                execute: { input, _ in
                    let id: String
                    if case .object(let obj) = input, case .string(let s) = obj["id"] {
                        id = s
                    } else {
                        id = "unknown"
                    }
                    await log.record("start-\(id)")
                    try await Task.sleep(for: .seconds(1))
                    await log.record("end-\(id)")
                    return .value(.object(["id": .string(id), "done": .bool(true)]))
                }
            )
        ]

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            tools: tools
        )

        _ = try await result.collectFullStream()

        // If concurrent: [start-A, start-B, end-A, end-B] (both starts before any end)
        // If sequential: [start-A, end-A, start-B, end-B] (an end appears before the second start)
        let events = await log.events
        let starts = events.filter { $0.hasPrefix("start-") }
        let firstEnd = events.firstIndex { $0.hasPrefix("end-") }
        let lastStart = events.lastIndex { $0.hasPrefix("start-") }

        #expect(starts.count == 2, "Expected 2 starts, got \(starts.count). Events: \(events)")
        #expect(
            lastStart! < firstEnd!,
            "Tool calls ran sequentially — an end arrived before both starts. Events: \(events)"
        )
    }
}
