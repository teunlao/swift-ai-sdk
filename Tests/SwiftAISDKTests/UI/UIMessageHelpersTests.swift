import Testing
@testable import SwiftAISDK

@Suite("UIMessage helpers")
struct UIMessageHelpersTests {
    @Test("returns tool name without prefix")
    func returnsToolName() {
        let part = UIToolUIPart(
            toolName: "getLocation",
            toolCallId: "tool1",
            state: .outputAvailable,
            input: .object([:]),
            output: .string("result")
        )

        #expect(getToolName(part) == "getLocation")
    }

    @Test("returns tool name with dash preserved")
    func returnsToolNameWithDash() {
        let part = UIToolUIPart(
            toolName: "get-location",
            toolCallId: "tool1",
            state: .outputAvailable,
            input: .object([:]),
            output: .string("result")
        )

        #expect(getToolName(part) == "get-location")
    }
}
