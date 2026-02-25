import Testing
@testable import OpenResponsesProvider
import AISDKProvider

@Suite("mapOpenResponsesFinishReason", .serialized)
struct MapOpenResponsesFinishReasonTests {
    @Test("returns tool-calls when hasToolCalls is true and finishReason is nil")
    func toolCallsWhenNilAndHasTools() {
        #expect(mapOpenResponsesFinishReason(finishReason: nil, hasToolCalls: true) == .toolCalls)
    }

    @Test("returns stop when hasToolCalls is false and finishReason is nil")
    func stopWhenNilAndNoTools() {
        #expect(mapOpenResponsesFinishReason(finishReason: nil, hasToolCalls: false) == .stop)
    }

    @Test("returns length when finishReason is max_output_tokens")
    func lengthWhenMaxOutputTokens() {
        #expect(mapOpenResponsesFinishReason(finishReason: "max_output_tokens", hasToolCalls: false) == .length)
    }

    @Test("returns content-filter when finishReason is content_filter")
    func contentFilterWhenContentFilter() {
        #expect(mapOpenResponsesFinishReason(finishReason: "content_filter", hasToolCalls: false) == .contentFilter)
    }

    @Test("returns tool-calls when hasToolCalls is true and finishReason is unknown")
    func toolCallsWhenUnknownAndHasTools() {
        #expect(mapOpenResponsesFinishReason(finishReason: "completed", hasToolCalls: true) == .toolCalls)
    }

    @Test("returns other when hasToolCalls is false and finishReason is unknown")
    func otherWhenUnknownAndNoTools() {
        #expect(mapOpenResponsesFinishReason(finishReason: "completed", hasToolCalls: false) == .other)
    }
}

