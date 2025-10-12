import Foundation

/**
 Prompt configuration for AI function calls.

 Port of `@ai-sdk/ai/src/prompt/prompt.ts`.

 A prompt can contain:
 - A `system` message (optional)
 - Either a `prompt` string/messages OR a `messages` array (mutually exclusive)

 ## Example
 ```swift
 // Simple text prompt
 let prompt1 = Prompt(
     system: "You are a helpful assistant",
     prompt: .text("Hello, how are you?")
 )

 // Multi-message prompt
 let prompt2 = Prompt(
     messages: [
         .user(content: [.text(.init(text: "What is 2+2?"))], providerOptions: nil)
     ]
 )
 ```
 */
public struct Prompt: Sendable, Equatable {
    /**
     System message to include in the prompt.

     Can be used with either `prompt` or `messages`.
     */
    public let system: String?

    /**
     The prompt content. Mutually exclusive with `messages`.
     */
    public let prompt: PromptContent?

    /**
     Array of messages. Mutually exclusive with `prompt`.
     */
    public let messages: [LanguageModelV3Message]?

    /**
     Creates a prompt with a simple text or message list.

     - Parameters:
       - system: Optional system message
       - prompt: Prompt content (text or messages)
     */
    public init(system: String? = nil, prompt: PromptContent) {
        self.system = system
        self.prompt = prompt
        self.messages = nil
    }

    /**
     Creates a prompt with an array of messages.

     - Parameters:
       - system: Optional system message
       - messages: Array of messages
     */
    public init(system: String? = nil, messages: [LanguageModelV3Message]) {
        self.system = system
        self.prompt = nil
        self.messages = messages
    }
}

/**
 Prompt content can be either a simple text string or an array of messages.

 Mirrors TypeScript union:
 ```typescript
 prompt: string | Array<ModelMessage>
 ```
 */
public enum PromptContent: Sendable, Equatable {
    /// Simple text prompt
    case text(String)

    /// Array of messages
    case messages([LanguageModelV3Message])
}

// MARK: - Convenience Initializers

extension Prompt {
    /**
     Creates a simple text prompt.

     - Parameters:
       - text: The prompt text
       - system: Optional system message
     */
    public static func text(_ text: String, system: String? = nil) -> Prompt {
        Prompt(system: system, prompt: .text(text))
    }

    /**
     Creates a prompt from messages.

     - Parameters:
       - messages: Array of messages
       - system: Optional system message
     */
    public static func messages(_ messages: [LanguageModelV3Message], system: String? = nil) -> Prompt {
        Prompt(system: system, messages: messages)
    }
}

