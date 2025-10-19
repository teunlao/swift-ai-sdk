import Foundation
import Testing
@testable import AISDKProvider
@testable import GoogleProvider

@Suite("convertToGoogleGenerativeAIMessages")
struct ConvertToGoogleGenerativeAIMessagesTests {
    @Test("collects system instruction at start")
    func systemInstruction() throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "behave", providerOptions: nil),
            .user(content: [.text(.init(text: "hello"))], providerOptions: nil)
        ]

        let result = try convertToGoogleGenerativeAIMessages(prompt, options: .init(isGemmaModel: false))
        #expect(result.systemInstruction != nil)
        #expect(result.systemInstruction?.parts.count == 1)
        #expect(result.systemInstruction?.parts.first?.text == "behave")
        #expect(result.contents.first?.role == .user)
    }

    @Test("inlines data for user file bytes")
    func userFileData() throws {
        let data = Data([0x01, 0x02])
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .file(.init(
                    data: .data(data),
                    mediaType: "image/png"
                ))
            ], providerOptions: nil)
        ]

        let result = try convertToGoogleGenerativeAIMessages(prompt)
        guard let parts = result.contents.first?.parts else {
            Issue.record("Missing parts")
            return
        }

        #expect(parts.count == 1)
        if case let .inlineData(inline) = parts[0] {
            #expect(inline.mimeType == "image/png")
            #expect(Data(base64Encoded: inline.data) == data)
        } else {
            Issue.record("Expected inline data part")
        }
    }

    @Test("maps assistant reasoning and tool call")
    func assistantReasoningAndToolCall() throws {
        let toolCall = LanguageModelV3ToolCallPart(
            toolCallId: "tool-1",
            toolName: "lookup",
            input: .object(["query": .string("rain")] ),
            providerExecuted: false,
            providerOptions: ["google": ["thoughtSignature": .string("sig")]]
        )
        let assistantParts: [LanguageModelV3MessagePart] = [
            .reasoning(.init(text: "thinking", providerOptions: ["google": ["thoughtSignature": .string("reason")]])),
            .toolCall(toolCall)
        ]
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: assistantParts, providerOptions: nil)
        ]

        let result = try convertToGoogleGenerativeAIMessages(prompt)
        guard let modelParts = result.contents.first?.parts else {
            Issue.record("Missing model parts")
            return
        }

        #expect(modelParts.count == 2)
        if case let .text(text) = modelParts[0] {
            #expect(text.text == "thinking")
            #expect(text.thought == true)
            #expect(text.thoughtSignature == "reason")
        } else {
            Issue.record("Expected reasoning text")
        }

        if case let .functionCall(call) = modelParts[1] {
            #expect(call.name == "lookup")
            #expect(call.arguments == toolCall.input)
            #expect(call.thoughtSignature == "sig")
        } else {
            Issue.record("Expected function call")
        }
    }

    @Test("maps tool result to function response")
    func toolResultMapping() throws {
        let toolPart = LanguageModelV3ToolResultPart(
            toolCallId: "call-1",
            toolName: "lookup",
            output: .text(value: "result text"),
            providerOptions: nil
        )
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [toolPart], providerOptions: nil)
        ]

        let result = try convertToGoogleGenerativeAIMessages(prompt)
        guard let userParts = result.contents.first?.parts else {
            Issue.record("Missing user parts")
            return
        }

        #expect(userParts.count == 1)
        if case let .functionResponse(response) = userParts[0] {
            #expect(response.name == "lookup")
            guard case let .object(payload) = response.response else {
                Issue.record("Expected object payload")
                return
            }
            #expect(payload["content"] == .string("result text"))
        } else {
            Issue.record("Expected function response part")
        }
    }

    @Test("gemma models fold system instruction into first message")
    func gemmaSystemHandling() throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "rule", providerOptions: nil),
            .user(content: [.text(.init(text: "hi"))], providerOptions: nil)
        ]

        let result = try convertToGoogleGenerativeAIMessages(prompt, options: .init(isGemmaModel: true))
        #expect(result.systemInstruction == nil)
        #expect(result.contents.first?.parts.first == .text(.init(text: "rule\n\n")))
    }
}
