import Foundation
import Testing
import AISDKProvider
@testable import SwiftAISDK

@Suite("processUIMessageStream")
struct ProcessUIMessageStreamTests {
    @Test("stores separate call and result provider metadata for static tool outputs")
    func storesSeparateMetadataForStaticToolOutputs() async throws {
        let callMetadata: ProviderMetadata = [
            "testProvider": ["itemId": .string("call-item")]
        ]
        let resultMetadata: ProviderMetadata = [
            "testProvider": ["itemId": .string("result-item")]
        ]

        let state = try await process(chunks: [
            .start(messageId: "msg-123", messageMetadata: nil),
            .startStep,
            .toolInputAvailable(
                toolCallId: "tool-call-1",
                toolName: "tool-name",
                input: .object(["query": .string("test")]),
                providerExecuted: true,
                providerMetadata: callMetadata,
                dynamic: false,
                title: nil
            ),
            .toolOutputAvailable(
                toolCallId: "tool-call-1",
                output: .object(["result": .string("provider-result")]),
                providerExecuted: true,
                providerMetadata: resultMetadata,
                dynamic: false,
                preliminary: nil
            ),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ])

        guard case let .tool(toolPart)? = state.message.parts.first(where: {
            if case let .tool(part) = $0 {
                return part.toolCallId == "tool-call-1"
            }
            return false
        }) else {
            Issue.record("Expected static tool part")
            return
        }

        #expect(toolPart.callProviderMetadata == callMetadata)
        #expect(toolPart.resultProviderMetadata == resultMetadata)
    }

    @Test("stores separate call and result provider metadata for dynamic tool errors")
    func storesSeparateMetadataForDynamicToolErrors() async throws {
        let callMetadata: ProviderMetadata = [
            "testProvider": ["itemId": .string("call-item")]
        ]
        let resultMetadata: ProviderMetadata = [
            "testProvider": ["itemId": .string("result-item")]
        ]

        let state = try await process(chunks: [
            .start(messageId: "msg-123", messageMetadata: nil),
            .startStep,
            .toolInputStart(
                toolCallId: "tool-call-2",
                toolName: "tool-name",
                providerExecuted: true,
                providerMetadata: callMetadata,
                dynamic: true,
                title: nil
            ),
            .toolInputAvailable(
                toolCallId: "tool-call-2",
                toolName: "tool-name",
                input: .object(["query": .string("test")]),
                providerExecuted: true,
                providerMetadata: callMetadata,
                dynamic: true,
                title: nil
            ),
            .toolOutputError(
                toolCallId: "tool-call-2",
                errorText: "error-text",
                providerExecuted: true,
                providerMetadata: resultMetadata,
                dynamic: true
            ),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ])

        guard case let .dynamicTool(toolPart)? = state.message.parts.first(where: {
            if case let .dynamicTool(part) = $0 {
                return part.toolCallId == "tool-call-2"
            }
            return false
        }) else {
            Issue.record("Expected dynamic tool part")
            return
        }

        #expect(toolPart.callProviderMetadata == callMetadata)
        #expect(toolPart.resultProviderMetadata == resultMetadata)
    }

    @Test("tool input error with dynamic flag mismatch updates existing static part")
    func toolInputErrorWithDynamicFlagMismatchUpdatesExistingStaticPart() async throws {
        let rawInput = "{ \"foo\": \"bar\" }"

        let state = try await process(chunks: [
            .start(messageId: "msg-123", messageMetadata: nil),
            .startStep,
            .toolInputStart(
                toolCallId: "call-1",
                toolName: "nonExistentTool",
                providerExecuted: nil,
                providerMetadata: nil,
                dynamic: nil,
                title: nil
            ),
            .toolInputDelta(
                toolCallId: "call-1",
                inputTextDelta: rawInput
            ),
            .toolInputError(
                toolCallId: "call-1",
                toolName: "nonExistentTool",
                input: .string(rawInput),
                providerExecuted: nil,
                providerMetadata: nil,
                dynamic: true,
                errorText: "Model tried to call unavailable tool 'nonExistentTool'.",
                title: nil
            ),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ])

        #expect(state.message.parts.count == 2)

        let staticToolParts = state.message.parts.compactMap { part -> UIToolUIPart? in
            if case .tool(let toolPart) = part {
                return toolPart
            }
            return nil
        }

        let dynamicToolParts = state.message.parts.compactMap { part -> UIDynamicToolUIPart? in
            if case .dynamicTool(let toolPart) = part {
                return toolPart
            }
            return nil
        }

        #expect(staticToolParts.count == 1)
        #expect(dynamicToolParts.isEmpty)

        guard let toolPart = staticToolParts.first else {
            Issue.record("Expected static tool part")
            return
        }

        #expect(toolPart.toolCallId == "call-1")
        #expect(toolPart.toolName == "nonExistentTool")
        #expect(toolPart.state == .outputError)
        #expect(toolPart.input == nil)
        #expect(toolPart.rawInput == .string(rawInput))
        #expect(toolPart.errorText == "Model tried to call unavailable tool 'nonExistentTool'.")
    }

    @Test("text delta without text start throws descriptive error")
    func textDeltaWithoutTextStartThrowsDescriptiveError() async throws {
        let error = await processError(chunks: [
            .start(messageId: "msg-123", messageMetadata: nil),
            .textDelta(id: "text-1", delta: "Hello", providerMetadata: nil)
        ])

        guard let typed = error as? UIMessageStreamError else {
            Issue.record("Expected UIMessageStreamError")
            return
        }

        #expect(UIMessageStreamError.isInstance(typed))
        #expect(typed.chunkType == "text-delta")
        #expect(typed.chunkId == "text-1")
        #expect(typed.message == "Received text-delta for missing text part with ID \"text-1\". Ensure a \"text-start\" chunk is sent before any \"text-delta\" chunks.")
    }

    @Test("reasoning end without reasoning start throws descriptive error")
    func reasoningEndWithoutReasoningStartThrowsDescriptiveError() async throws {
        let error = await processError(chunks: [
            .start(messageId: "msg-123", messageMetadata: nil),
            .reasoningEnd(id: "reasoning-1", providerMetadata: nil)
        ])

        guard let typed = error as? UIMessageStreamError else {
            Issue.record("Expected UIMessageStreamError")
            return
        }

        #expect(UIMessageStreamError.isInstance(typed))
        #expect(typed.chunkType == "reasoning-end")
        #expect(typed.chunkId == "reasoning-1")
        #expect(typed.message == "Received reasoning-end for missing reasoning part with ID \"reasoning-1\". Ensure a \"reasoning-start\" chunk is sent before any \"reasoning-end\" chunks.")
    }

    @Test("tool input delta without tool input start throws descriptive error")
    func toolInputDeltaWithoutToolInputStartThrowsDescriptiveError() async throws {
        let error = await processError(chunks: [
            .start(messageId: "msg-123", messageMetadata: nil),
            .toolInputDelta(toolCallId: "tool-1", inputTextDelta: "{}")
        ])

        guard let typed = error as? UIMessageStreamError else {
            Issue.record("Expected UIMessageStreamError")
            return
        }

        #expect(UIMessageStreamError.isInstance(typed))
        #expect(typed.chunkType == "tool-input-delta")
        #expect(typed.chunkId == "tool-1")
        #expect(typed.message == "Received tool-input-delta for missing tool call with ID \"tool-1\". Ensure a \"tool-input-start\" chunk is sent before any \"tool-input-delta\" chunks.")
    }

    @Test("tool output available without tool invocation throws descriptive error")
    func toolOutputAvailableWithoutToolInvocationThrowsDescriptiveError() async throws {
        let error = await processError(chunks: [
            .start(messageId: "msg-123", messageMetadata: nil),
            .toolOutputAvailable(
                toolCallId: "tool-1",
                output: .object(["value": .string("ok")]),
                providerExecuted: nil,
                providerMetadata: nil,
                dynamic: false,
                preliminary: nil
            )
        ])

        guard let typed = error as? UIMessageStreamError else {
            Issue.record("Expected UIMessageStreamError")
            return
        }

        #expect(UIMessageStreamError.isInstance(typed))
        #expect(typed.chunkType == "tool-invocation")
        #expect(typed.chunkId == "tool-1")
        #expect(typed.message == "No tool invocation found for tool call ID \"tool-1\".")
    }

    @Test("tool output available with dynamic flag mismatch updates existing static part")
    func toolOutputAvailableWithDynamicFlagMismatchUpdatesExistingStaticPart() async throws {
        let state = try await process(chunks: [
            .start(messageId: "msg-123", messageMetadata: nil),
            .startStep,
            .toolInputAvailable(
                toolCallId: "call-9",
                toolName: "weather",
                input: .object(["city": .string("Tokyo")]),
                providerExecuted: nil,
                providerMetadata: nil,
                dynamic: false,
                title: nil
            ),
            .toolOutputAvailable(
                toolCallId: "call-9",
                output: .object(["weather": .string("Sunny")]),
                providerExecuted: nil,
                providerMetadata: nil,
                dynamic: true,
                preliminary: nil
            ),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ])

        let staticToolParts = state.message.parts.compactMap { part -> UIToolUIPart? in
            if case .tool(let toolPart) = part {
                return toolPart
            }
            return nil
        }

        let dynamicToolParts = state.message.parts.compactMap { part -> UIDynamicToolUIPart? in
            if case .dynamicTool(let toolPart) = part {
                return toolPart
            }
            return nil
        }

        #expect(staticToolParts.count == 1)
        #expect(dynamicToolParts.isEmpty)

        guard let toolPart = staticToolParts.first else {
            Issue.record("Expected static tool part")
            return
        }

        #expect(toolPart.state == .outputAvailable)
        #expect(toolPart.output == .object(["weather": .string("Sunny")]))
    }

    private func process(
        chunks: [AnyUIMessageChunk]
    ) async throws -> StreamingUIMessageState<UIMessage> {
        let state: StreamingUIMessageState<UIMessage> = createStreamingUIMessageState(
            lastMessage: nil,
            messageId: "msg-123"
        )

        let stream = makeAsyncStream(from: chunks)
        let processed = processUIMessageStream(
            stream: stream,
            runUpdateMessageJob: { job in
                try await job(
                    StreamingUIMessageJobContext(
                        state: state,
                        write: {}
                    )
                )
            },
            onError: nil
        )

        _ = try await collectStream(processed)
        return state
    }

    private func processError(
        chunks: [AnyUIMessageChunk]
    ) async -> Error? {
        do {
            _ = try await process(chunks: chunks)
            Issue.record("Expected processing to fail")
            return nil
        } catch {
            return error
        }
    }
}
