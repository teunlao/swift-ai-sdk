import Foundation
import Testing
@testable import OpenResponsesProvider
import AISDKProvider

@Suite("convertToOpenResponsesInput", .serialized)
struct ConvertToOpenResponsesInputTests {
    private func decodeJSONString(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test("system messages: single system message becomes instructions")
    func systemSingle() async {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "You are a helpful assistant.", providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)

        #expect(result.instructions == "You are a helpful assistant.")
        #expect(result.input.isEmpty)
    }

    @Test("system messages: multiple system messages join with newlines")
    func systemJoin() async {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "You are a helpful assistant.", providerOptions: nil),
            .system(content: "Always be concise.", providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)

        #expect(result.instructions == "You are a helpful assistant.\nAlways be concise.")
        #expect(result.input.isEmpty)
    }

    @Test("system messages: no system messages yields nil instructions")
    func systemNone() async {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        #expect(result.instructions == nil)
    }

    @Test("user messages: text -> input_text")
    func userText() async {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        #expect(result.input == [
            .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([
                    .object(["type": .string("input_text"), "text": .string("Hello")])
                ])
            ])
        ])
    }

    @Test("user messages: image file (base64) -> input_image data URL")
    func userImageBase64() async {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .file(.init(data: .base64("ZmFrZS1kYXRh"), mediaType: "image/png"))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        #expect(result.input == [
            .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,ZmFrZS1kYXRh")
                    ])
                ])
            ])
        ])
    }

    @Test("user messages: image file (URL) -> input_image url")
    func userImageURL() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .file(.init(data: .url(try #require(URL(string: "https://example.com/image.png"))), mediaType: "image/png"))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        #expect(result.input == [
            .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("https://example.com/image.png")
                    ])
                ])
            ])
        ])
    }

    @Test("user messages: non-image files add warning and are skipped")
    func userUnsupportedFileWarning() async {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .file(.init(data: .base64("ZmFrZS1kYXRh"), mediaType: "application/pdf"))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        #expect(result.warnings == [.other(message: "unsupported file content type: application/pdf")])
        #expect(result.input == [
            .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([])
            ])
        ])
    }

    @Test("assistant messages: tool-call object input becomes JSON string")
    func assistantToolCallObjectInput() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .toolCall(.init(toolCallId: "call_123", toolName: "get_weather", input: .object([
                    "location": .string("San Francisco")
                ])))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        guard case .object(let item) = try #require(result.input.first) else {
            Issue.record("Expected object item")
            return
        }

        #expect(item["type"] == .string("function_call"))
        #expect(item["call_id"] == .string("call_123"))
        #expect(item["name"] == .string("get_weather"))

        guard case .string(let args) = item["arguments"] else {
            Issue.record("Expected arguments string")
            return
        }
        #expect(try decodeJSONString(args) == .object(["location": .string("San Francisco")]))
    }

    @Test("assistant messages: tool-call string input passes through")
    func assistantToolCallStringInput() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .toolCall(.init(toolCallId: "call_124", toolName: "get_weather", input: .string("{\"location\":\"Berlin\"}")))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        guard case .object(let item) = try #require(result.input.first) else {
            Issue.record("Expected object item")
            return
        }

        guard case .string(let args) = item["arguments"] else {
            Issue.record("Expected arguments string")
            return
        }
        #expect(try decodeJSONString(args) == .object(["location": .string("Berlin")]))
    }

    @Test("assistant messages: text + tool-call produces message then function_call")
    func assistantTextAndToolCall() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .text(.init(text: "Let me check the weather for you.")),
                .toolCall(.init(toolCallId: "call_456", toolName: "get_weather", input: .object([
                    "location": .string("New York")
                ])))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        #expect(result.input.count == 2)

        // assistant message
        guard case .object(let message) = result.input[0] else {
            Issue.record("Expected assistant message object")
            return
        }
        #expect(message["type"] == .string("message"))
        #expect(message["role"] == .string("assistant"))

        // tool call
        guard case .object(let toolCall) = result.input[1] else {
            Issue.record("Expected tool call object")
            return
        }
        guard case .string(let args) = toolCall["arguments"] else {
            Issue.record("Expected arguments string")
            return
        }
        #expect(try decodeJSONString(args) == .object(["location": .string("New York")]))
    }

    @Test("tool messages: json output is JSON string")
    func toolJSONOutput() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "call_123",
                    toolName: "get_weather",
                    output: .json(value: .object(["temperature": .number(72), "condition": .string("sunny")]))
                ))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        guard case .object(let item) = try #require(result.input.first) else {
            Issue.record("Expected object item")
            return
        }

        guard case .string(let output) = item["output"] else {
            Issue.record("Expected output string")
            return
        }
        #expect(try decodeJSONString(output) == .object(["temperature": .number(72), "condition": .string("sunny")]))
    }

    @Test("tool messages: execution-denied uses default message when reason is nil")
    func toolExecutionDeniedDefaultMessage() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "call_denied",
                    toolName: "dangerous_action",
                    output: .executionDenied(reason: nil)
                ))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        guard case .object(let item) = try #require(result.input.first) else {
            Issue.record("Expected object item")
            return
        }
        #expect(item["output"] == .string("Tool execution denied."))
    }

    @Test("tool messages: content output converts text and image-data")
    func toolContentOutputTextAndImage() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "call_content",
                    toolName: "multi_output",
                    output: .content(value: [
                        .text(text: "First result"),
                        .media(data: "ZmFrZS1kYXRh", mediaType: "image/png"),
                    ])
                ))
            ], providerOptions: nil)
        ]

        let result = await convertToOpenResponsesInput(prompt: prompt)
        guard case .object(let item) = try #require(result.input.first) else {
            Issue.record("Expected object item")
            return
        }

        guard case .array(let parts)? = item["output"] else {
            Issue.record("Expected output array")
            return
        }

        #expect(parts == [
            .object(["type": .string("input_text"), "text": .string("First result")]),
            .object(["type": .string("input_image"), "image_url": .string("data:image/png;base64,ZmFrZS1kYXRh")]),
        ])
    }
}
