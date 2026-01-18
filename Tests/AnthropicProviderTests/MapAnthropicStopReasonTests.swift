import Testing
@testable import AnthropicProvider
import AISDKProvider

@Suite("mapAnthropicStopReason")
struct MapAnthropicStopReasonTests {
    @Test("maps model_context_window_exceeded to length")
    func modelContextWindowExceeded() {
        #expect(mapAnthropicStopReason(finishReason: "model_context_window_exceeded") == .length)
    }

    @Test("maps unknown stop reason to other")
    func unknownStopReason() {
        #expect(mapAnthropicStopReason(finishReason: "some_future_reason") == .other)
    }

    @Test("maps tool_use to tool-calls unless JSON tool response")
    func toolUse() {
        #expect(mapAnthropicStopReason(finishReason: "tool_use", isJsonResponseFromTool: false) == .toolCalls)
        #expect(mapAnthropicStopReason(finishReason: "tool_use", isJsonResponseFromTool: true) == .stop)
    }
}

