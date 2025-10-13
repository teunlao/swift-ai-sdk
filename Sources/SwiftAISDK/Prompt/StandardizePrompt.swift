import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Standardized prompt structure containing system message and messages.
 */
public struct StandardizedPrompt: Sendable {
    public let system: String?
    public let messages: [ModelMessage]

    public init(system: String?, messages: [ModelMessage]) {
        self.system = system
        self.messages = messages
    }
}

/**
 Standardizes a prompt into a consistent format with system message and message list.

 Port of `@ai-sdk/ai/src/prompt/standardize-prompt.ts`.

 Converts various prompt formats into a standardized structure:
 - Extracts system message
 - Converts text prompts to user messages
 - Normalizes message arrays
 - Validates that messages are not empty

 TypeScript version is async due to zod schema validation. Swift version is
 synchronous since type system guarantees `[ModelMessage]` correctness.

 - Parameter prompt: The prompt to standardize
 - Returns: StandardizedPrompt containing optional system message and array of messages
 - Throws: `InvalidPromptError` if messages are empty or prompt is invalid
 */
public func standardizePrompt(_ prompt: Prompt) throws -> StandardizedPrompt {
    // Extract system message
    let system = prompt.system

    var messages: [ModelMessage]

    // Handle prompt content
    if let promptContent = prompt.prompt {
        switch promptContent {
        case .text(let text):
            // Convert simple text to user message (matches upstream line 46-47)
            messages = [.user(UserModelMessage(
                content: .text(text),
                providerOptions: nil
            ))]

        case .messages(let msgs):
            // Already have messages
            messages = msgs
        }
    }
    // Handle messages array
    else if let msgs = prompt.messages {
        messages = msgs
    }
    // This should never happen due to Prompt's XOR constraint via init,
    // but we check defensively to match upstream behavior
    else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"), prompt: nil, messages: nil)",
            message: "prompt or messages must be defined"
        )
    }

    // Validate messages are not empty (matches upstream line 59-64)
    if messages.isEmpty {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"), messages: [])",
            message: "messages must not be empty"
        )
    }

    // Note: TypeScript version validates message schema via zod (line 66-79).
    // Swift relies on type system: [ModelMessage] is compile-time guaranteed.
    // No runtime schema validation needed.

    // Return StandardizedPrompt struct (matches upstream line 81-84)
    return StandardizedPrompt(system: system, messages: messages)
}
