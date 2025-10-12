import Testing
@testable import SwiftAISDK

/**
 Tests for standardizePrompt function.

 Port of `@ai-sdk/ai/src/prompt/standardize-prompt.test.ts`.

 Covers:
 - Text prompt conversion to user message
 - Messages array pass-through
 - Empty messages validation
 - System message handling
 */
@Suite("StandardizePrompt")
struct StandardizePromptTests {

    // MARK: - Valid Cases

    @Test("converts text prompt to user message")
    func convertsTextPromptToUserMessage() throws {
        let prompt = Prompt(
            system: nil,
            prompt: .text("Hello, world!")
        )

        let result = try standardizePrompt(prompt)

        #expect(result.system == nil)
        #expect(result.messages.count == 1)

        guard case .user(let userMessage) = result.messages[0] else {
            Issue.record("Expected user message")
            return
        }

        guard case .text(let text) = userMessage.content else {
            Issue.record("Expected text content")
            return
        }
        #expect(text == "Hello, world!")
    }

    @Test("converts text prompt with system message")
    func convertsTextPromptWithSystem() throws {
        let prompt = Prompt(
            system: "You are a helpful assistant",
            prompt: .text("Hello!")
        )

        let result = try standardizePrompt(prompt)

        #expect(result.system == "You are a helpful assistant")
        #expect(result.messages.count == 1)

        guard case .user(let userMessage) = result.messages[0] else {
            Issue.record("Expected user message")
            return
        }

        guard case .text(let text) = userMessage.content else {
            Issue.record("Expected text content")
            return
        }
        #expect(text == "Hello!")
    }

    @Test("passes through messages array")
    func passesThroughMessagesArray() throws {
        let messages: [ModelMessage] = [
            .user(UserModelMessage(
                content: .parts([.text(TextPart(text: "Message 1"))]),
                providerOptions: nil
            )),
            .assistant(AssistantModelMessage(
                content: .parts([.text(TextPart(text: "Response 1"))]),
                providerOptions: nil
            )),
        ]

        let prompt = Prompt(system: nil, messages: messages)

        let result = try standardizePrompt(prompt)

        #expect(result.system == nil)
        #expect(result.messages.count == 2)

        guard case .user = result.messages[0] else {
            Issue.record("Expected user message at index 0")
            return
        }
        guard case .assistant = result.messages[1] else {
            Issue.record("Expected assistant message at index 1")
            return
        }
    }

    @Test("handles messages with system")
    func handlesMessagesWithSystem() throws {
        let messages: [ModelMessage] = [
            .user(UserModelMessage(
                content: .parts([.text(TextPart(text: "Hello"))]),
                providerOptions: nil
            ))
        ]

        let prompt = Prompt(system: "System prompt", messages: messages)

        let result = try standardizePrompt(prompt)

        #expect(result.system == "System prompt")
        #expect(result.messages.count == 1)
    }

    @Test("converts PromptContent.messages to array")
    func convertsPromptContentMessages() throws {
        let messages: [ModelMessage] = [
            .user(UserModelMessage(
                content: .parts([.text(TextPart(text: "Test"))]),
                providerOptions: nil
            ))
        ]

        let prompt = Prompt(system: nil, prompt: .messages(messages))

        let result = try standardizePrompt(prompt)

        #expect(result.system == nil)
        #expect(result.messages.count == 1)
    }

    // MARK: - Error Cases

    @Test("throws InvalidPromptError for empty messages array")
    func throwsForEmptyMessages() throws {
        let prompt = Prompt(system: nil, messages: [])

        #expect(throws: InvalidPromptError.self) {
            try standardizePrompt(prompt)
        }
    }

    @Test("throws InvalidPromptError for empty PromptContent.messages")
    func throwsForEmptyPromptContentMessages() throws {
        let prompt = Prompt(system: nil, prompt: .messages([]))

        #expect(throws: InvalidPromptError.self) {
            try standardizePrompt(prompt)
        }
    }

    @Test("error message for empty messages is correct")
    func errorMessageForEmptyMessages() throws {
        let prompt = Prompt(system: nil, messages: [])

        do {
            _ = try standardizePrompt(prompt)
            Issue.record("Expected InvalidPromptError to be thrown")
        } catch let error as InvalidPromptError {
            #expect(error.message.contains("messages must not be empty"))
        } catch {
            Issue.record("Expected InvalidPromptError, got \(error)")
        }
    }
}
