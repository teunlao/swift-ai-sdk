import Testing
import Foundation
@testable import XAIProvider
import AISDKProvider

/**
 Tests for convertToXAIChatMessages function.

 Port of `@ai-sdk/xai/src/convert-to-xai-chat-messages.test.ts`.
 */

@Suite("convertToXAIChatMessages")
struct ConvertToXAIChatMessagesTests {

    @Test("should convert simple text messages")
    func convertSimpleTextMessages() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let (messages, warnings) = try convertToXAIChatMessages(prompt)

        #expect(warnings.isEmpty)
        #expect(messages.count == 1)
        #expect(messages[0].role == .user)
        #expect(messages[0].textContent == "Hello")
        #expect(messages[0].userContentParts == nil)
    }

    @Test("should convert system messages")
    func convertSystemMessages() throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "You are a helpful assistant.", providerOptions: nil)
        ]

        let (messages, warnings) = try convertToXAIChatMessages(prompt)

        #expect(warnings.isEmpty)
        #expect(messages.count == 1)
        #expect(messages[0].role == .system)
        #expect(messages[0].textContent == "You are a helpful assistant.")
    }

    @Test("should convert assistant messages")
    func convertAssistantMessages() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.text(.init(text: "Hello there!"))], providerOptions: nil)
        ]

        let (messages, warnings) = try convertToXAIChatMessages(prompt)

        #expect(warnings.isEmpty)
        #expect(messages.count == 1)
        #expect(messages[0].role == .assistant)
        #expect(messages[0].textContent == "Hello there!")
        #expect(messages[0].toolCalls == nil)
    }

    @Test("should convert messages with image parts")
    func convertMessagesWithImageParts() throws {
        let data = Data([0, 1, 2, 3])
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "What is in this image?")),
                .file(.init(data: .data(data), mediaType: "image/png"))
            ], providerOptions: nil)
        ]

        let (messages, warnings) = try convertToXAIChatMessages(prompt)

        #expect(warnings.isEmpty)
        #expect(messages.count == 1)
        #expect(messages[0].role == .user)

        guard let parts = messages[0].userContentParts else {
            Issue.record("Expected userContentParts to be present")
            return
        }

        #expect(parts.count == 2)
        if case .text(let text) = parts[0] {
            #expect(text == "What is in this image?")
        } else {
            Issue.record("Expected first part to be text")
        }

        if case .imageURL(let url) = parts[1] {
            #expect(url == "data:image/png;base64,AAECAw==")
        } else {
            Issue.record("Expected second part to be imageURL")
        }
    }

    @Test("should convert image URLs")
    func convertImageURLs() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .file(.init(data: .url(URL(string: "https://example.com/image.jpg")!), mediaType: "image/jpeg"))
            ], providerOptions: nil)
        ]

        let (messages, warnings) = try convertToXAIChatMessages(prompt)

        #expect(warnings.isEmpty)
        #expect(messages.count == 1)
        #expect(messages[0].role == .user)

        guard let parts = messages[0].userContentParts else {
            Issue.record("Expected userContentParts to be present")
            return
        }

        #expect(parts.count == 1)
        if case .imageURL(let url) = parts[0] {
            #expect(url == "https://example.com/image.jpg")
        } else {
            Issue.record("Expected part to be imageURL")
        }
    }

    @Test("should throw error for unsupported file types")
    func throwErrorForUnsupportedFileTypes() throws {
        let data = Data([0, 1, 2, 3])
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .file(.init(data: .data(data), mediaType: "application/pdf"))
            ], providerOptions: nil)
        ]

        #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try convertToXAIChatMessages(prompt)
        }
    }

    @Test("should convert tool calls and tool responses")
    func convertToolCallsAndResponses() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .toolCall(.init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    input: .object(["location": .string("Paris")])
                ))
            ], providerOptions: nil),
            .tool(content: [
                .init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    output: .json(value: .object(["temperature": .number(20)]))
                )
            ], providerOptions: nil)
        ]

        let (messages, warnings) = try convertToXAIChatMessages(prompt)

        #expect(warnings.isEmpty)
        #expect(messages.count == 2)

        // Check assistant message with tool call
        #expect(messages[0].role == .assistant)
        #expect(messages[0].textContent == nil || messages[0].textContent == "")

        guard let toolCalls = messages[0].toolCalls else {
            Issue.record("Expected toolCalls to be present")
            return
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].id == "call_123")
        #expect(toolCalls[0].name == "weather")
        #expect(toolCalls[0].arguments == "{\"location\":\"Paris\"}")

        // Check tool response
        #expect(messages[1].role == .tool)
        #expect(messages[1].toolCallId == "call_123")
        #expect(messages[1].textContent == "{\"temperature\":20}")
    }

    @Test("should handle multiple tool calls in one message")
    func handleMultipleToolCalls() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .toolCall(.init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    input: .object(["location": .string("Paris")])
                )),
                .toolCall(.init(
                    toolCallId: "call_456",
                    toolName: "time",
                    input: .object(["timezone": .string("UTC")])
                ))
            ], providerOptions: nil)
        ]

        let (messages, warnings) = try convertToXAIChatMessages(prompt)

        #expect(warnings.isEmpty)
        #expect(messages.count == 1)
        #expect(messages[0].role == .assistant)
        #expect(messages[0].textContent == nil || messages[0].textContent == "")

        guard let toolCalls = messages[0].toolCalls else {
            Issue.record("Expected toolCalls to be present")
            return
        }

        #expect(toolCalls.count == 2)
        #expect(toolCalls[0].id == "call_123")
        #expect(toolCalls[0].name == "weather")
        #expect(toolCalls[0].arguments == "{\"location\":\"Paris\"}")

        #expect(toolCalls[1].id == "call_456")
        #expect(toolCalls[1].name == "time")
        #expect(toolCalls[1].arguments == "{\"timezone\":\"UTC\"}")
    }

    @Test("should handle mixed content with text and tool calls")
    func handleMixedContentTextAndToolCalls() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .text(.init(text: "Let me check the weather for you.")),
                .toolCall(.init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    input: .object(["location": .string("Paris")])
                ))
            ], providerOptions: nil)
        ]

        let (messages, warnings) = try convertToXAIChatMessages(prompt)

        #expect(warnings.isEmpty)
        #expect(messages.count == 1)
        #expect(messages[0].role == .assistant)
        #expect(messages[0].textContent == "Let me check the weather for you.")

        guard let toolCalls = messages[0].toolCalls else {
            Issue.record("Expected toolCalls to be present")
            return
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].id == "call_123")
        #expect(toolCalls[0].name == "weather")
        #expect(toolCalls[0].arguments == "{\"location\":\"Paris\"}")
    }
}
