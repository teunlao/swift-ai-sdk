import Testing
@testable import AISDKProvider
import Foundation

@Suite("LanguageModelV3 Prompt & Messages")
struct LanguageModelV3PromptTests {

    @Test("Message: system role round-trip")
    func v3_system_message() throws {
        let msg = LanguageModelV3Message.system(content: "behave", providerOptions: ["o": ["k": .number(1)]])
        let data = try JSONEncoder().encode(msg)
        let back = try JSONDecoder().decode(LanguageModelV3Message.self, from: data)
        #expect(back == msg)
    }

    @Test("Message: user with text and file parts")
    func v3_user_with_parts() throws {
        let bytes = Data(base64Encoded: "QUJD")!
        let parts: [LanguageModelV3UserMessagePart] = [
            .text(.init(text: "Hello")),
            .file(.init(data: .data(bytes), mediaType: "image/png", filename: "a.png"))
        ]
        let msg = LanguageModelV3Message.user(content: parts, providerOptions: nil)
        let data = try JSONEncoder().encode(msg)
        let back = try JSONDecoder().decode(LanguageModelV3Message.self, from: data)
        #expect(back == msg)
    }

    @Test("Message: assistant with tool-call and reasoning")
    func v3_assistant_with_toolcall() throws {
        let toolCall = LanguageModelV3MessagePart.toolCall(.init(
            toolCallId: "c1",
            toolName: "weather",
            input: ["city": .string("London")],
            providerExecuted: false
        ))
        let msg = LanguageModelV3Message.assistant(content: [
            .reasoning(.init(text: "think...")),
            toolCall
        ], providerOptions: nil)
        let data = try JSONEncoder().encode(msg)
        let back = try JSONDecoder().decode(LanguageModelV3Message.self, from: data)
        #expect(back == msg)
    }

    @Test("Message: tool role with result outputs")
    func v3_tool_role_with_result() throws {
        let outText: LanguageModelV3ToolResultOutput = .text(value: "ok")
        let outContent: LanguageModelV3ToolResultOutput = .content(value: [
            .text(text: "hello"),
            .media(data: "QUJD", mediaType: "image/png")
        ])

        let m1 = LanguageModelV3Message.tool(content: [
            .init(toolCallId: "c1", toolName: "weather", output: outText),
        ], providerOptions: nil)
        let m2 = LanguageModelV3Message.tool(content: [
            .init(toolCallId: "c2", toolName: "render", output: outContent)
        ], providerOptions: ["p": ["x": .bool(true)]])

        let enc = JSONEncoder(); let dec = JSONDecoder()
        let b1 = try dec.decode(LanguageModelV3Message.self, from: try enc.encode(m1))
        let b2 = try dec.decode(LanguageModelV3Message.self, from: try enc.encode(m2))
        #expect(b1 == m1)
        #expect(b2 == m2)
    }

    @Test("Prompt: multi-turn conversation")
    func v3_prompt_multi_turn() throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "helpful", providerOptions: nil),
            .user(content: [.text(.init(text: "hi"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "hello"))], providerOptions: nil),
            .tool(content: [.init(toolCallId: "c1", toolName: "noop", output: .json(value: ["k": .string("v")]))], providerOptions: nil)
        ]
        let data = try JSONEncoder().encode(prompt)
        let back = try JSONDecoder().decode(LanguageModelV3Prompt.self, from: data)
        #expect(back == prompt)
    }

    @Test("Message: user rejects reasoning/tool parts")
    func v3_user_rejects_invalid_parts() throws {
        let json = """
        [
          {
            "role": "user",
            "content": [
              { "type": "reasoning", "text": "not allowed" }
            ]
          }
        ]
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(LanguageModelV3Prompt.self, from: json)
        }
    }
}
