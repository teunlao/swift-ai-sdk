import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

@Suite("Tool titles – propagation")
struct ToolTitlePropagationTests {

    @Test("makeProviderToolResult forwards title from stored call (static)")
    func makeProviderToolResultForwardsTitleStatic() async throws {
        let stored: TypedToolCall = .static(StaticToolCall(
            toolCallId: "c1",
            toolName: "demo",
            title: "Demo Tool",
            input: .object(["x": .number(1)]),
            providerExecuted: false,
            providerMetadata: nil
        ))

        let result = makeProviderToolResult(
            storedCall: stored,
            fallbackToolName: "fallback",
            toolCallId: "c1",
            input: .null,
            output: .object(["ok": .bool(true)]),
            providerExecuted: false,
            preliminary: false,
            providerMetadata: nil
        )

        guard case .static(let value) = result else {
            Issue.record("expected static tool result")
            return
        }

        #expect(value.toolCallId == "c1")
        #expect(value.toolName == "demo")
        #expect(value.title == "Demo Tool")
        #expect(value.output == .object(["ok": .bool(true)]))
    }

    @Test("makeProviderToolResult forwards title from stored call (dynamic)")
    func makeProviderToolResultForwardsTitleDynamic() async throws {
        let stored: TypedToolCall = .dynamic(DynamicToolCall(
            toolCallId: "c2",
            toolName: "demoDyn",
            title: "Dynamic Demo",
            input: .object(["q": .string("hi")]),
            providerExecuted: false,
            providerMetadata: nil,
            invalid: false,
            error: nil
        ))

        let result = makeProviderToolResult(
            storedCall: stored,
            fallbackToolName: "fallback",
            toolCallId: "c2",
            input: .null,
            output: .string("done"),
            providerExecuted: false,
            preliminary: nil,
            providerMetadata: nil
        )

        guard case .dynamic(let value) = result else {
            Issue.record("expected dynamic tool result")
            return
        }

        #expect(value.toolCallId == "c2")
        #expect(value.toolName == "demoDyn")
        #expect(value.title == "Dynamic Demo")
        #expect(value.output == .string("done"))
    }

    @Test("makeProviderToolResult without stored call has no title")
    func makeProviderToolResultNoStoredCallHasNoTitle() async throws {
        let result = makeProviderToolResult(
            storedCall: nil,
            fallbackToolName: "fallback",
            toolCallId: "c3",
            input: .object(["x": .number(1)]),
            output: .string("ok"),
            providerExecuted: true,
            preliminary: nil,
            providerMetadata: nil
        )

        guard case .dynamic(let value) = result else {
            Issue.record("expected dynamic tool result")
            return
        }

        #expect(value.toolCallId == "c3")
        #expect(value.toolName == "fallback")
        #expect(value.title == nil)
    }

    @Test("makeProviderToolError forwards title from stored call")
    func makeProviderToolErrorForwardsTitle() async throws {
        let stored: TypedToolCall = .static(StaticToolCall(
            toolCallId: "c4",
            toolName: "boom",
            title: "Boom Tool",
            input: .object([:]),
            providerExecuted: false,
            providerMetadata: nil
        ))

        let err = NSError(domain: "test", code: 1)
        let toolError = makeProviderToolError(
            storedCall: stored,
            fallbackToolName: "fallback",
            toolCallId: "c4",
            input: .null,
            providerExecuted: true,
            error: err
        )

        guard case .static(let value) = toolError else {
            Issue.record("expected static tool error")
            return
        }

        #expect(value.toolCallId == "c4")
        #expect(value.toolName == "boom")
        #expect(value.title == "Boom Tool")
        #expect(!AISDKProvider.getErrorMessage(value.error).isEmpty)
    }

    @Test("makeInvalidToolCallError forwards title from invalid call")
    func makeInvalidToolCallErrorForwardsTitle() async throws {
        struct SampleError: Error {}

        let invalid: TypedToolCall = .dynamic(DynamicToolCall(
            toolCallId: "c5",
            toolName: "missing",
            title: "Missing Tool",
            input: .string("bad input"),
            providerExecuted: nil,
            providerMetadata: nil,
            invalid: true,
            error: SampleError()
        ))

        let toolError = makeInvalidToolCallError(from: invalid)
        guard case .dynamic(let value) = toolError else {
            Issue.record("expected dynamic tool error")
            return
        }

        #expect(value.toolCallId == "c5")
        #expect(value.toolName == "missing")
        #expect(value.title == "Missing Tool")
        #expect(value.input == .string("bad input"))
    }
}
