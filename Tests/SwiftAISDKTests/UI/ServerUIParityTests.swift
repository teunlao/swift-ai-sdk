import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK

@Suite("server UI parity")
struct ServerUIParityTests {
    @Test("SSE preserves the complete chunk payload and validates it on input")
    func chunkWireRoundTrip() async throws {
        let metadata: ProviderMetadata = ["provider": ["id": .string("item")]]
        let toolMetadata: JSONObject = ["owner": .string("server")]
        let citation = Citation(source: .url(id: "source", url: "https://example.com", title: nil, providerMetadata: nil), startIndex: 0, endIndex: 2)
        let chunks: [AnyUIMessageChunk] = [
            .textEnd(id: "text", providerMetadata: metadata, citations: [citation]),
            .custom(kind: "provider.state", providerMetadata: metadata),
            .reasoningFile(url: "data:image/png;base64,AA==", mediaType: "image/png", providerMetadata: metadata),
            .toolInputStart(toolCallId: "call", toolName: "shell", providerExecuted: true, providerMetadata: metadata, dynamic: false, title: "Shell", toolMetadata: toolMetadata, inputEncoding: .text),
            .toolInputAvailable(toolCallId: "call", toolName: "shell", input: .string("pwd"), providerExecuted: true, providerMetadata: metadata, dynamic: false, title: "Shell", toolMetadata: toolMetadata),
            .toolInputError(toolCallId: "bad", toolName: "shell", input: .null, providerExecuted: nil, providerMetadata: metadata, dynamic: nil, errorText: "invalid", title: nil, toolMetadata: toolMetadata),
            .toolApprovalRequest(approvalId: "approval", toolCallId: "call", approvalDescriptor: .object(["kind": .string("shell")]), inputSchemaInput: .null, reason: "review", isAutomatic: true, signature: "signature"),
            .toolApprovalResponse(approvalId: "approval", approved: true, reason: "allowed", providerExecuted: true, providerMetadata: metadata),
            .toolOutputAvailable(toolCallId: "call", output: .null, providerExecuted: true, providerMetadata: metadata, dynamic: false, preliminary: false, toolMetadata: toolMetadata),
            .toolOutputError(toolCallId: "bad", errorText: "failed", providerExecuted: true, providerMetadata: metadata, dynamic: false, toolMetadata: toolMetadata),
            .resetStep
        ]
        let response: UIMessageStreamResponse<UIMessage> = try createUIMessageStreamResponse(stream: chunkStream(chunks))
        var parsed: [AnyUIMessageChunk] = []
        for try await event in response.stream {
            if event == "data: [DONE]\n\n" { continue }
            let payload = try JSONDecoder().decode(JSONValue.self, from: Data(event.dropFirst(6).utf8))
            parsed.append(try await validateTypes(ValidateTypesOptions(value: payload, schema: uiMessageChunkSchema)))
        }
        #expect(parsed == chunks)
        do {
            _ = try await validateTypes(ValidateTypesOptions(value: ["type": "tool-approval-response", "approvalId": "a", "approved": "yes"], schema: uiMessageChunkSchema))
            Issue.record("Invalid approval response was accepted")
        } catch { #expect(error is TypeValidationError) }
    }

    @Test("citation validation rejects invalid offsets before messages enter history")
    func invalidCitation() async {
        do {
            let _: [UIMessage] = try await validateUIMessages(messages: [[
                "id": "message", "role": "assistant", "parts": [[
                    "type": "text", "text": "answer", "citations": [[
                        "source": ["type": "source", "sourceType": "url", "id": "source", "url": "https://example.com"],
                        "startIndex": -1
                    ]]
                ]]
            ]])
            Issue.record("Invalid citation was accepted")
        } catch { #expect(error is TypeValidationError) }
    }

    @Test("explicit end chunks close parts across merged step boundaries")
    func activeTextSurvivesStepFinish() async throws {
        let citation = Citation(source: .url(id: "s", url: "https://example.com", title: nil, providerMetadata: nil))
        let messages = try await snapshots([
            .textStart(id: "text", providerMetadata: nil), .finishStep,
            .textDelta(id: "text", delta: "answer", providerMetadata: nil),
            .textEnd(id: "text", providerMetadata: nil, citations: [citation]),
            .reasoningStart(id: "reason", providerMetadata: nil),
            .reasoningEnd(id: "reason", providerMetadata: nil)
        ])
        let final = try #require(messages.last)
        #expect(final.parts == [
            .text(TextUIPart(text: "answer", state: .done, citations: [citation])),
            .reasoning(ReasoningUIPart(text: "", state: .done, id: "reason"))
        ])
    }

    @Test("raw text tool input resumes from persisted state")
    func resumeTextInput() async throws {
        let initial = UIMessage(id: "message", role: .assistant, parts: [.tool(UIToolUIPart(
            toolName: "shell", toolCallId: "call", state: .inputStreaming,
            input: .string("echo "), rawInput: .string("echo "), providerExecuted: true,
            toolMetadata: ["kind": .string("shell")], inputEncoding: .text
        ))])
        let stream: AsyncIterableStream<UIMessage> = readUIMessageStream(message: initial, stream: chunkStream([
            .toolInputDelta(toolCallId: "call", inputTextDelta: "hello")
        ]), terminateOnError: true)
        var final: UIMessage?
        for try await message in stream { final = message }
        guard case .tool(let tool) = final?.parts.first else { Issue.record("Expected resumed tool"); return }
        #expect(tool.input == .string("echo hello"))
        #expect(tool.rawInput == .string("echo hello"))
        #expect(tool.inputEncoding == .text)
        #expect(tool.providerExecuted == true)
        #expect(tool.toolMetadata == ["kind": .string("shell")])
    }

    @Test("reset-step replaces only the current step and anonymous data parts append")
    func resetStepAndAnonymousData() async throws {
        let messages = try await snapshots([
            .startStep, .custom(kind: "provider.keep", providerMetadata: nil),
            .startStep, .textStart(id: "old", providerMetadata: nil), .resetStep,
            .data(DataUIMessageChunk(name: "item", data: .number(1))),
            .data(DataUIMessageChunk(name: "item", data: .number(2)))
        ])
        #expect(messages.last?.parts == [
            .stepStart, .custom(CustomContentUIPart(kind: "provider.keep")), .stepStart,
            .data(DataUIPart(typeIdentifier: "data-item", data: .number(1))),
            .data(DataUIPart(typeIdentifier: "data-item", data: .number(2)))
        ])
    }

    @Test("a different response id starts a separate message")
    func newResponseResetsState() async throws {
        let messages = try await snapshots([
            .start(messageId: "one", messageMetadata: .object(["old": .bool(true)])),
            .custom(kind: "provider.old", providerMetadata: nil),
            .start(messageId: "two", messageMetadata: nil),
            .reasoningFile(url: "https://example.com/file", mediaType: "image/png", providerMetadata: nil)
        ])
        #expect(messages.last == UIMessage(id: "two", role: .assistant, parts: [
            .reasoningFile(ReasoningFileUIPart(mediaType: "image/png", url: "https://example.com/file"))
        ]))
    }

    @Test("approval descriptors and signatures survive stream processing and model conversion")
    func approvalRoundTrip() async throws {
        let messages = try await snapshots([
            .toolInputAvailable(toolCallId: "call", toolName: "shell", input: .string("pwd"), providerExecuted: true, providerMetadata: nil, dynamic: nil, title: nil),
            .toolApprovalRequest(approvalId: "approval", toolCallId: "call", approvalDescriptor: .string("descriptor"), inputSchemaInput: .null, reason: "review", isAutomatic: true, signature: "signature"),
            .toolApprovalResponse(approvalId: "approval", approved: false, reason: "denied", providerExecuted: true)
        ])
        let final = try #require(messages.last)
        guard case .tool(let tool) = final.parts.first else { Issue.record("Expected tool"); return }
        #expect(tool.approval?.descriptor == .string("descriptor"))
        let converted = try await convertToModelMessages(messages: [final])
        guard case .assistant(let assistant) = converted.first, case .parts(let content) = assistant.content,
              case .toolApprovalRequest(let request) = content.last,
              case .tool(let result) = converted.last,
              case .toolResult(let denied) = result.content.last else { Issue.record("Expected approval exchange"); return }
        #expect(request.reason == "review")
        #expect(request.signature == "signature")
        #expect(request.inputSchemaInput == .null)
        #expect(request.isAutomatic == true)
        #expect(denied.output == .executionDenied(reason: "denied"))
    }

    @Test("validation loads empty assistant states and normalizes unavailable terminal tools")
    func terminalHistory() async throws {
        let messages: [UIMessage] = try await validateUIMessages(messages: [
            ["id": "empty", "role": "assistant", "parts": []],
            ["id": "history", "role": "assistant", "parts": [
                ["type": "tool-missing", "toolCallId": "call", "state": "output-available", "input": [:], "output": ["secret": "raw"]],
                ["type": "tool-failed", "toolCallId": "failed", "state": "output-error", "errorText": "provider error"]
            ]]
        ], tools: [:])
        #expect(messages[0].parts.isEmpty)
        guard case .dynamicTool(let tool) = messages[1].parts[0] else { Issue.record("Expected dynamic history"); return }
        #expect(tool.dynamic == false)
        #expect(isToolOutputErrorUIPart(messages[1].parts[1]))
        let result = try await convertToModelMessages(messages: messages)
        guard case .tool(let output) = result.last, case .toolResult(let unavailable) = output.content[0],
              case .toolResult(let failed) = output.content[1] else { Issue.record("Expected tool outputs"); return }
        #expect(unavailable.output == .text(value: "Tool output omitted because the tool is no longer available."))
        #expect(failed.output == .errorText(value: "provider error"))
    }

    @Test("conversion drops superseded approvals and preliminary tool calls")
    func incompleteCalls() async throws {
        let messages = [
            UIMessage(id: "old", role: .assistant, parts: [.tool(UIToolUIPart(toolName: "shell", toolCallId: "pending", state: .approvalRequested, input: .string("pwd"), approval: UIToolApproval(id: "a")))]),
            UIMessage(id: "user", role: .user, parts: [.text(TextUIPart(text: "new request"))]),
            UIMessage(id: "new", role: .assistant, parts: [.tool(UIToolUIPart(toolName: "shell", toolCallId: "preliminary", state: .outputAvailable, input: .string("pwd"), output: .string("partial"), preliminary: true))])
        ]
        let converted = try await convertToModelMessages(messages: messages, options: ConvertToModelMessagesOptions(ignoreIncompleteToolCalls: true))
        #expect(converted == [.user(UserModelMessage(content: .parts([.text(TextPart(text: "new request"))])))])
    }

    @Test("data converters and provider references preserve multimodal prompt order")
    func multimodalConversion() async throws {
        let message = UIMessage(id: "assistant", role: .assistant, parts: [
            .custom(CustomContentUIPart(kind: "provider.state")),
            .sourceURL(SourceUrlUIPart(sourceId: "s", url: "https://example.com")),
            .data(DataUIPart(typeIdentifier: "data-note", data: .string("note"))),
            .file(FileUIPart(mediaType: "image/png", url: "unused", providerReference: ["provider": "file-id"])),
            .reasoningFile(ReasoningFileUIPart(mediaType: "image/png", url: "https://example.com/reason"))
        ])
        let converted = try await convertToModelMessages(messages: [message], options: ConvertToModelMessagesOptions(convertDataPart: { _ in .text(TextPart(text: "note")) }))
        #expect(converted == [.assistant(AssistantModelMessage(content: .parts([
            .custom(CustomPart(kind: "provider.state")), .text(TextPart(text: "note")),
            .file(FilePart(data: .reference(["provider": "file-id"]), mediaType: "image/png")),
            .reasoningFile(ReasoningFilePart(data: .url(URL(string: "https://example.com/reason")!), mediaType: "image/png"))
        ])))])
    }

    private func chunkStream(_ chunks: [AnyUIMessageChunk]) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }

    private func snapshots(_ chunks: [AnyUIMessageChunk]) async throws -> [UIMessage] {
        let stream: AsyncIterableStream<UIMessage> = readUIMessageStream(stream: chunkStream(chunks), terminateOnError: true)
        var messages: [UIMessage] = []
        for try await message in stream { messages.append(message) }
        return messages
    }
}
