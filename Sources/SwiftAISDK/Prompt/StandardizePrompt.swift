import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Standardized prompt: the instructions and a non-empty list of messages.

 Port of `StandardizedPrompt` from `@ai-sdk/ai/src/prompt/standardize-prompt.ts`.
 */
public struct StandardizedPrompt: Sendable, Equatable {
    /// Instructions for the model.
    public let instructions: Instructions?

    /// Messages of the prompt.
    public let messages: [ModelMessage]

    public init(instructions: Instructions?, messages: [ModelMessage]) {
        self.instructions = instructions
        self.messages = messages
    }
}

/**
 Standardizes a prompt into instructions and a non-empty message list.

 Port of `@ai-sdk/ai/src/prompt/standardize-prompt.ts`. Message shape
 validation is enforced by the `ModelMessage` type instead of a runtime schema.

 - Throws: `InvalidPromptError` when neither or both of `prompt`/`messages` are
   set, when the messages are empty, or when system messages appear without
   `allowSystemInMessages`.
 */
public func standardizePrompt(_ prompt: Prompt) throws -> StandardizedPrompt {
    let instructions = prompt.instructions
    let description = String(describing: prompt)

    if prompt.prompt == nil && prompt.messages == nil {
        throw InvalidPromptError(prompt: description, message: "prompt or messages must be defined")
    }

    if prompt.prompt != nil && prompt.messages != nil {
        throw InvalidPromptError(
            prompt: description,
            message: "prompt and messages cannot be defined at the same time"
        )
    }

    let messages: [ModelMessage]
    switch prompt.prompt {
    case .text(let text):
        messages = [.user(UserModelMessage(content: .text(text), providerOptions: nil))]
    case .messages(let promptMessages):
        messages = promptMessages
    case nil:
        messages = prompt.messages ?? []
    }

    if messages.isEmpty {
        throw InvalidPromptError(prompt: description, message: "messages must not be empty")
    }

    if prompt.allowSystemInMessages != true,
       messages.contains(where: { if case .system = $0 { return true } else { return false } }) {
        throw InvalidPromptError(
            prompt: description,
            message: "System messages are not allowed in the prompt or messages fields. Use the instructions option instead."
        )
    }

    return StandardizedPrompt(instructions: instructions, messages: messages)
}
