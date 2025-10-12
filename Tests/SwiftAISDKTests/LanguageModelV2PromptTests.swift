import Testing
@testable import SwiftAISDK
import Foundation

@Suite("LanguageModelV2 Prompt & Messages")
struct LanguageModelV2PromptTests {

    @Test("Message: system role round-trip")
    func system_message() throws {
        let msg = LanguageModelV2Message.system(content: "behave", providerOptions: ["o": ["k": .number(1)]])
        let data = try JSONEncoder().encode(msg)
        let back = try JSONDecoder().decode(LanguageModelV2Message.self, from: data)
        #expect(back == msg)
    }

    @Test("Message: user with text and file parts")
    func user_with_parts() throws {
        let bytes = Data(base64Encoded: "QUJD")!
        let parts: [LanguageModelV2MessagePart] = [
            .text(.init(text: "Hello")),
            .file(.init(data: .data(bytes), mediaType: "image/png", filename: "a.png"))
        ]
        let msg = LanguageModelV2Message.user(content: parts, providerOptions: nil)
        let data = try JSONEncoder().encode(msg)
        let back = try JSONDecoder().decode(LanguageModelV2Message.self, from: data)
        #expect(back == msg)
    }

    @Test("Message: assistant with tool-call and reasoning")
    func assistant_with_toolcall() throws {
        let toolCall = LanguageModelV2MessagePart.toolCall(.init(
            toolCallId: "c1",
            toolName: "weather",
            input: ["city": .string("London")],
            providerExecuted: false
        ))
        let msg = LanguageModelV2Message.assistant(content: [
            .reasoning(.init(text: "think...")),
            toolCall
        ], providerOptions: nil)
        let data = try JSONEncoder().encode(msg)
        let back = try JSONDecoder().decode(LanguageModelV2Message.self, from: data)
        #expect(back == msg)
    }

    @Test("Message: tool role with result outputs")
    func tool_role_with_result() throws {
        let outText: LanguageModelV2ToolResultOutput = .text(value: "ok")
        let outContent: LanguageModelV2ToolResultOutput = .content(value: [
            .text(text: "hello"),
            .media(data: "QUJD", mediaType: "image/png")
        ])

        let m1 = LanguageModelV2Message.tool(content: [
            .init(toolCallId: "c1", toolName: "weather", output: outText),
        ], providerOptions: nil)
        let m2 = LanguageModelV2Message.tool(content: [
            .init(toolCallId: "c2", toolName: "render", output: outContent)
        ], providerOptions: ["p": ["x": .bool(true)]])

        let enc = JSONEncoder(); let dec = JSONDecoder()
        let b1 = try dec.decode(LanguageModelV2Message.self, from: try enc.encode(m1))
        let b2 = try dec.decode(LanguageModelV2Message.self, from: try enc.encode(m2))
        #expect(b1 == m1)
        #expect(b2 == m2)
    }

    @Test("Prompt: multi-turn conversation")
    func prompt_multi_turn() throws {
        let prompt: LanguageModelV2Prompt = [
            .system(content: "helpful", providerOptions: nil),
            .user(content: [.text(.init(text: "hi"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "hello"))], providerOptions: nil),
            .tool(content: [.init(toolCallId: "c1", toolName: "noop", output: .json(value: ["k": .string("v")]))], providerOptions: nil)
        ]
        let data = try JSONEncoder().encode(prompt)
        let back = try JSONDecoder().decode(LanguageModelV2Prompt.self, from: data)
        #expect(back == prompt)
    }
}
