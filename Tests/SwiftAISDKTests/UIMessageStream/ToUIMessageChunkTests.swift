import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("streamText parts to UI message chunks")
struct ToUIMessageChunkTests {
    private let objectSchema = FlexibleSchema<JSONValue>(jsonSchema(.object(["type": .string("object")])))

    private func model(_ parts: [LanguageModelV4StreamPart]) -> MockLanguageModelV4 {
        MockLanguageModelV4(doStream: .singleValue(LanguageModelV4StreamResult(stream: AsyncThrowingStream { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        })))
    }

    private func finish(_ reason: LanguageModelV4FinishReason.Unified) -> LanguageModelV4StreamPart {
        .finish(finishReason: LanguageModelV4FinishReason(unified: reason), usage: LanguageModelV4Usage(), providerMetadata: nil)
    }

    private func uiChunks(_ result: DefaultStreamTextResult<String, String>) async throws -> [AnyUIMessageChunk] {
        var chunks: [AnyUIMessageChunk] = []
        for try await chunk in result.toUIMessageStream(options: UIMessageStreamOptions<UIMessage>()) { chunks.append(chunk) }
        return chunks
    }

    private func lastMessage(_ parts: [TextStreamPart]) async throws -> UIMessage? {
        let source = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let messages: AsyncIterableStream<UIMessage> = readUIMessageStream(
            stream: toUIMessageStream(stream: source, options: UIMessageStreamOptions<UIMessage>())
        )
        var last: UIMessage?
        for try await message in messages { last = message }
        return last
    }

    @Test("a signed approval request round-trips through UI messages and executes")
    func signedApprovalRoundTrip() async throws {
        let executions = LockedCount()
        let tools: ToolSet = ["deploy": tool(inputSchema: objectSchema, needsApproval: .always, execute: { _, _ in
            executions.increment()
            return .value(.string("deployed"))
        })]
        let result = try streamText(model: model([
            .toolCall(LanguageModelV4ToolCall(toolCallId: "call-1", toolName: "deploy", input: "{}")),
            finish(.toolCalls),
        ]), tools: tools, prompt: "deploy", toolApprovalSecret: "server-secret")
        let messages: AsyncIterableStream<UIMessage> = readUIMessageStream(
            stream: result.toUIMessageStream(options: UIMessageStreamOptions<UIMessage>())
        )
        var assistant: UIMessage?
        for try await message in messages { assistant = message }

        var message = try #require(assistant)
        let index = try #require(message.parts.firstIndex { if case .tool = $0 { true } else { false } })
        guard case .tool(var part) = message.parts[index], var approval = part.approval else {
            Issue.record("Expected an approval request on the tool part"); return
        }
        #expect(approval.signature != nil)
        approval.approved = true
        part.approval = approval
        part.state = .approvalResponded
        message.parts[index] = .tool(part)

        let history = try await convertToModelMessages(
            messages: [UIMessage(id: "user", role: .user, parts: [.text(TextUIPart(text: "deploy", state: .done))]), message],
            options: ConvertToModelMessagesOptions(tools: tools)
        )
        _ = try await generateText(
            model: MockLanguageModelV4(doGenerate: .singleValue(LanguageModelV4GenerateResult(
                content: [.text(LanguageModelV4Text(text: "done"))], finishReason: .stop, usage: LanguageModelV4Usage()
            ))),
            tools: tools, messages: history, toolApprovalSecret: "server-secret"
        )
        #expect(executions.value == 1)
    }

    @Test("approval request fields and a differing schema input reach the UI chunk")
    func approvalRequestFields() {
        let call = TypedToolCall.static(StaticToolCall(toolCallId: "call", toolName: "t", input: .object(["n": .number(1)])))
            .with(inputSchemaInput: .object(["n": .string("1")]))
        let request = ToolApprovalRequestOutput(approvalId: "a", toolCall: call, reason: "risky", isAutomatic: false, signature: "sig")
        #expect(toUIMessageChunk(.toolApprovalRequest(request)) == .toolApprovalRequest(
            approvalId: "a", toolCallId: "call", inputSchemaInput: .object(["n": .string("1")]),
            reason: "risky", isAutomatic: false, signature: "sig"
        ))
    }

    @Test("a server-side approval decision becomes the UI tool state and a model approval response")
    func approvalResponse() async throws {
        let call = TypedToolCall.static(StaticToolCall(toolCallId: "call", toolName: "t", input: .object([:])))
        let message = try #require(try await lastMessage([
            .start,
            .toolCall(call),
            .toolApprovalRequest(ToolApprovalRequestOutput(approvalId: "a", toolCall: call)),
            .toolApprovalResponse(ToolApprovalResponseOutput(approvalId: "a", toolCall: call, approved: false, reason: "policy")),
        ]))
        guard case .tool(let part)? = message.parts.last else { Issue.record("Expected a tool part"); return }
        #expect(part.state == .approvalResponded)
        #expect(part.approval?.approved == false)
        #expect(part.approval?.reason == "policy")

        let history = try await convertToModelMessages(messages: [message])
        let responses = history.flatMap { message -> [ToolApprovalResponse] in
            guard case .tool(let tool) = message else { return [] }
            return tool.content.compactMap { if case .toolApprovalResponse(let response) = $0 { response } else { nil } }
        }
        #expect(responses.map(\.approved) == [false])
        #expect(responses.map(\.reason) == ["policy"])
    }

    @Test("text-encoded tool input streams as a string")
    func textInputEncoding() async throws {
        let message = try #require(try await lastMessage([
            .start,
            .toolInputStart(id: "call", toolName: "shell", providerMetadata: nil, providerExecuted: nil,
                            dynamic: nil, title: nil, inputEncoding: .text),
            .toolInputDelta(id: "call", delta: "echo ", providerMetadata: nil),
            .toolInputDelta(id: "call", delta: "hello", providerMetadata: nil),
        ]))
        guard case .tool(let part)? = message.parts.last else { Issue.record("Expected a tool part"); return }
        #expect(part.input == .string("echo hello"))
    }

    @Test("tool metadata reaches the input and output chunks")
    func toolMetadata() async throws {
        let metadata: [String: JSONValue] = ["owner": .string("billing")]
        let result = try streamText(model: model([
            .toolCall(LanguageModelV4ToolCall(toolCallId: "call", toolName: "lookup", input: "{}")),
            finish(.toolCalls),
        ]), tools: ["lookup": tool(metadata: metadata, inputSchema: objectSchema, execute: { _, _ in .value(.string("found")) })],
            prompt: "look")
        let chunks = try await uiChunks(result)
        let inputMetadata = chunks.compactMap { chunk -> JSONObject? in
            if case .toolInputAvailable(_, _, _, _, _, _, _, let toolMetadata) = chunk { return toolMetadata }
            return nil
        }
        let outputMetadata = chunks.compactMap { chunk -> JSONObject? in
            if case .toolOutputAvailable(_, _, _, _, _, _, let toolMetadata) = chunk { return toolMetadata }
            return nil
        }
        #expect(inputMetadata == [metadata])
        #expect(outputMetadata == [metadata])
    }

    @Test("a provider-executed string error keeps its text")
    func providerStringError() async throws {
        let result = try streamText(model: model([
            .toolCall(LanguageModelV4ToolCall(toolCallId: "call", toolName: "search", input: "{}", providerExecuted: true, dynamic: true)),
            .toolResult(LanguageModelV4ToolResult(toolCallId: "call", toolName: "search", result: .string("provider string error"),
                                                  isError: true, dynamic: true)),
            finish(.stop),
        ]), prompt: "search")
        let errors = try await uiChunks(result).compactMap { chunk -> String? in
            if case .toolOutputError(_, let errorText, _, _, _, _) = chunk { return errorText }
            return nil
        }
        #expect(errors == ["provider string error"])
    }
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
