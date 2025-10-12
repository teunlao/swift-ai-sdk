import Foundation

/**
 Standardizes a prompt into a consistent format with system message and message list.

 Port of `@ai-sdk/ai/src/prompt/standardize-prompt.ts`.

 Converts various prompt formats into a standardized structure:
 - Extracts system message
 - Converts text prompts to user messages
 - Normalizes message arrays
 - Validates that messages are not empty

 TypeScript version is async due to zod schema validation. Swift version is
 synchronous since type system guarantees `[LanguageModelV3Message]` correctness.

 - Parameter prompt: The prompt to standardize
 - Returns: A tuple containing optional system message and array of messages
 - Throws: `InvalidPromptError` if messages are empty or prompt is invalid
 */
public func standardizePrompt(_ prompt: Prompt) throws -> (system: String?, messages: [LanguageModelV3Message]) {
    // Extract system message
    let system = prompt.system

    var messages: [LanguageModelV3Message]

    // Handle prompt content
    if let promptContent = prompt.prompt {
        switch promptContent {
        case .text(let text):
            // Convert simple text to user message
            messages = [LanguageModelV3Message.user(
                content: [.text(.init(text: text))],
                providerOptions: nil
            )]

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
    // Swift relies on type system: [LanguageModelV3Message] is compile-time guaranteed.
    // No runtime schema validation needed.

    return (system, messages)
}
