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
}
