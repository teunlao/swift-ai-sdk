import Foundation
import Testing

@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("StreamingToolCallTracker")
struct StreamingToolCallTrackerTests {
    @Test("handles a single tool call accumulated across multiple deltas")
    func handlesSingleToolCallAcrossDeltas() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "get_weather", arguments: #"{"ci"#)
        ))

        #expect(collector.take() == [
            .toolInputStart(id: "call_1", toolName: "get_weather", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputDelta(id: "call_1", delta: #"{"ci"#, providerMetadata: nil),
        ])

        try tracker.processDelta(.init(
            index: 0,
            function: .init(arguments: #"ty": "San"#)
        ))

        #expect(collector.take() == [
            .toolInputDelta(id: "call_1", delta: #"ty": "San"#, providerMetadata: nil),
        ])

        try tracker.processDelta(.init(
            index: 0,
            function: .init(arguments: #" Francisco"}"#)
        ))

        #expect(collector.take() == [
            .toolInputDelta(id: "call_1", delta: #" Francisco"}"#, providerMetadata: nil),
        ])

        tracker.flush()

        #expect(collector.take() == [
            .toolInputEnd(id: "call_1", providerMetadata: nil),
            .toolCall(.init(
                toolCallId: "call_1",
                toolName: "get_weather",
                input: #"{"city": "San Francisco"}"#
            )),
        ])
    }

    @Test("handles a full tool call in a single chunk")
    func handlesFullToolCallInSingleChunk() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "get_weather", arguments: #"{"city": "London"}"#)
        ))

        #expect(collector.take() == [
            .toolInputStart(id: "call_1", toolName: "get_weather", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputDelta(id: "call_1", delta: #"{"city": "London"}"#, providerMetadata: nil),
        ])

        tracker.flush()

        #expect(collector.take() == [
            .toolInputEnd(id: "call_1", providerMetadata: nil),
            .toolCall(.init(
                toolCallId: "call_1",
                toolName: "get_weather",
                input: #"{"city": "London"}"#
            )),
        ])
    }

    @Test("handles multiple concurrent tool calls")
    func handlesMultipleConcurrentToolCalls() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "get_weather", arguments: "")
        ))
        try tracker.processDelta(.init(
            index: 1,
            id: "call_2",
            type: "function",
            function: .init(name: "get_time", arguments: "")
        ))

        #expect(collector.take() == [
            .toolInputStart(id: "call_1", toolName: "get_weather", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputStart(id: "call_2", toolName: "get_time", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
        ])
    }

    @Test("skips deltas for already-finished tool calls")
    func skipsDeltasForFinishedToolCalls() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "fn", arguments: "{}")
        ))
        tracker.flush()
        _ = collector.take()

        try tracker.processDelta(.init(
            index: 0,
            function: .init(arguments: "extra")
        ))

        #expect(collector.take().isEmpty)
    }

    @Test("skips delta emission when arguments are nil")
    func skipsNilArgumentDeltas() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "fn", arguments: "")
        ))
        _ = collector.take()

        try tracker.processDelta(.init(
            index: 0,
            function: .init(arguments: nil)
        ))

        #expect(collector.take().isEmpty)
    }

    @Test("uses index fallback when index is not provided")
    func usesIndexFallback() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(
            id: "call_1",
            type: "function",
            function: .init(name: "fn1", arguments: "{}")
        ))
        try tracker.processDelta(.init(
            id: "call_2",
            type: "function",
            function: .init(name: "fn2", arguments: "{}")
        ))

        let starts = collector.take().compactMap { part -> LanguageModelV4StreamPart? in
            if case .toolInputStart = part { return part }
            return nil
        }

        #expect(starts == [
            .toolInputStart(id: "call_1", toolName: "fn1", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputStart(id: "call_2", toolName: "fn2", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
        ])
    }

    @Test("does not validate type when validation is disabled")
    func doesNotValidateTypeWhenDisabled() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(
            enqueue: collector.enqueue,
            options: .init(typeValidation: .none)
        )

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "custom",
            function: .init(name: "fn", arguments: "")
        ))

        #expect(collector.take() == [
            .toolInputStart(id: "call_1", toolName: "fn", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
        ])
    }

    @Test("generates unique ids for blank and missing wire ids")
    func generatesUniqueIdsForBlankAndMissingIds() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(
            enqueue: collector.enqueue,
            options: .init(generateId: { "generated" })
        )

        try tracker.processDelta(.init(index: 0, id: "", function: .init(name: "fn", arguments: "{}")))
        try tracker.processDelta(.init(index: 1, function: .init(name: "fn", arguments: "{}")))
        tracker.flush()

        #expect(collector.take() == [
            .toolInputStart(id: "generated", toolName: "fn", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputDelta(id: "generated", delta: "{}", providerMetadata: nil),
            .toolInputStart(id: "generated-1", toolName: "fn", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
            .toolInputDelta(id: "generated-1", delta: "{}", providerMetadata: nil),
            .toolInputEnd(id: "generated", providerMetadata: nil),
            .toolCall(.init(toolCallId: "generated", toolName: "fn", input: "{}")),
            .toolInputEnd(id: "generated-1", providerMetadata: nil),
            .toolCall(.init(toolCallId: "generated-1", toolName: "fn", input: "{}")),
        ])
    }

    @Test("keeps parallel calls apart when a provider reuses an index")
    func keepsParallelCallsApartOnReusedIndex() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(index: 0, id: "call_a", function: .init(name: "a", arguments: #"{"x":1}"#)))
        try tracker.processDelta(.init(index: 0, id: "call_b", function: .init(name: "b", arguments: #"{"y":2}"#)))
        tracker.flush()

        let toolCalls = collector.take().compactMap { part -> LanguageModelV4ToolCall? in
            if case .toolCall(let toolCall) = part { return toolCall }
            return nil
        }
        #expect(toolCalls == [
            .init(toolCallId: "call_a", toolName: "a", input: #"{"x":1}"#),
            .init(toolCallId: "call_b", toolName: "b", input: #"{"y":2}"#),
        ])
    }

    @Test("throws when function name is missing")
    func throwsWhenFunctionNameIsMissing() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        do {
            try tracker.processDelta(.init(
                index: 0,
                id: "call_1",
                type: "function",
                function: .init()
            ))
            Issue.record("Expected InvalidResponseDataError")
        } catch let error as InvalidResponseDataError {
            #expect(error.message == "Expected 'function.name' to be a string.")
        }
    }

    @Test("validates type when present")
    func validatesTypeWhenPresent() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(
            enqueue: collector.enqueue,
            options: .init(typeValidation: .ifPresent)
        )

        do {
            try tracker.processDelta(.init(
                index: 0,
                id: "call_1",
                type: "custom",
                function: .init(name: "fn", arguments: "")
            ))
            Issue.record("Expected InvalidResponseDataError")
        } catch let error as InvalidResponseDataError {
            #expect(error.message == "Expected 'function' type.")
        }

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            function: .init(name: "fn", arguments: "")
        ))
    }

    @Test("requires function type when configured")
    func requiresFunctionTypeWhenConfigured() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(
            enqueue: collector.enqueue,
            options: .init(typeValidation: .required)
        )

        do {
            try tracker.processDelta(.init(
                index: 0,
                id: "call_1",
                function: .init(name: "fn", arguments: "")
            ))
            Issue.record("Expected InvalidResponseDataError")
        } catch let error as InvalidResponseDataError {
            #expect(error.message == "Expected 'function' type.")
        }

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "fn", arguments: "")
        ))
    }

    @Test("finalizes unfinished tool calls on flush")
    func finalizesUnfinishedToolCallsOnFlush() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "fn", arguments: #"{"key": "val"#)
        ))
        _ = collector.take()

        tracker.flush()

        #expect(collector.take() == [
            .toolInputEnd(id: "call_1", providerMetadata: nil),
            .toolCall(.init(
                toolCallId: "call_1",
                toolName: "fn",
                input: #"{"key": "val"#
            )),
        ])
    }

    @Test("does not re-finalize already finished tool calls")
    func doesNotRefinalizeFinishedToolCalls() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(enqueue: collector.enqueue)

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "fn", arguments: "{}")
        ))
        tracker.flush()
        _ = collector.take()

        tracker.flush()

        #expect(collector.take().isEmpty)
    }

    @Test("includes provider metadata in finalized tool calls")
    func includesProviderMetadata() throws {
        let collector = StreamPartCollector()
        let tracker = StreamingToolCallTracker(
            enqueue: collector.enqueue,
            options: .init(
                extractMetadata: { delta in
                    delta.providerMetadata?["google"]?["thoughtSignature"].map {
                        ["thoughtSignature": ["value": $0]]
                    }
                },
                buildToolCallProviderMetadata: { metadata in
                    guard let thoughtSignature = metadata?["thoughtSignature"]?["value"] else {
                        return nil
                    }
                    return ["google": ["thoughtSignature": thoughtSignature]]
                }
            )
        )

        try tracker.processDelta(.init(
            index: 0,
            id: "call_1",
            type: "function",
            function: .init(name: "fn", arguments: "{}"),
            providerMetadata: ["google": ["thoughtSignature": "sig123"]]
        ))
        tracker.flush()

        let toolCall = collector.take().first { part in
            if case .toolCall = part { return true }
            return false
        }

        #expect(toolCall == .toolCall(.init(
            toolCallId: "call_1",
            toolName: "fn",
            input: "{}",
            providerMetadata: [
                "google": ["thoughtSignature": "sig123"]
            ]
        )))
    }
}

private final class StreamPartCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [LanguageModelV4StreamPart] = []

    func enqueue(_ part: LanguageModelV4StreamPart) {
        lock.lock()
        defer { lock.unlock() }
        parts.append(part)
    }

    func take() -> [LanguageModelV4StreamPart] {
        lock.lock()
        defer { lock.unlock() }
        let current = parts
        parts.removeAll()
        return current
    }
}
