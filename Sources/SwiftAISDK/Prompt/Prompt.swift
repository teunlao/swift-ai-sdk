import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Instructions sent to the model ahead of the conversation: a string, or one or
 more system messages.

 Port of `Instructions` from `@ai-sdk/ai/src/prompt/prompt.ts`
 (`string | SystemModelMessage | Array<SystemModelMessage>`).
 */
public enum Instructions: Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case text(String)
    case messages([SystemModelMessage])

    public init(stringLiteral value: String) {
        self = .text(value)
    }

    public init(stringInterpolation: DefaultStringInterpolation) {
        self = .text(String(stringInterpolation: stringInterpolation))
    }

    /// A single system message.
    public static func message(_ message: SystemModelMessage) -> Instructions {
        .messages([message])
    }

    /// The instruction text when the instructions are a plain string.
    public var text: String? {
        if case .text(let text) = self { return text }
        return nil
    }
}

/**
 Prompt configuration for AI function calls.

 Port of `@ai-sdk/ai/src/prompt/prompt.ts`: optional `instructions` (or the
 deprecated alias `system`), and either `prompt` (text or messages) or
 `messages`.
 */
public struct Prompt: Sendable, Equatable {
    /// Instructions for the model.
    public let instructions: Instructions?

    /// Deprecated alias for `instructions`.
    public let system: Instructions?

    /// Whether system messages are allowed in `prompt` or `messages`. Default: `false`.
    public let allowSystemInMessages: Bool?

    /// The prompt content. Mutually exclusive with `messages`.
    public let prompt: PromptContent?

    /// Array of messages. Mutually exclusive with `prompt`.
    public let messages: [ModelMessage]?

    public init(
        instructions: Instructions? = nil,
        system: Instructions? = nil,
        allowSystemInMessages: Bool? = nil,
        prompt: PromptContent? = nil,
        messages: [ModelMessage]? = nil
    ) {
        self.instructions = instructions
        self.system = system
        self.allowSystemInMessages = allowSystemInMessages
        self.prompt = prompt
        self.messages = messages
    }

    public init(system: String?, prompt: PromptContent) {
        self.init(system: system.map(Instructions.text), prompt: prompt)
    }

    public init(system: String?, messages: [ModelMessage]) {
        self.init(system: system.map(Instructions.text), messages: messages)
    }

    /// Creates a simple text prompt.
    public static func text(_ text: String, system: String? = nil) -> Prompt {
        Prompt(system: system.map(Instructions.text), prompt: .text(text))
    }

    /// Creates a prompt from messages.
    public static func messages(_ messages: [ModelMessage], system: String? = nil) -> Prompt {
        Prompt(system: system.map(Instructions.text), messages: messages)
    }
}

/**
 Prompt content: a simple text string or an array of messages.

 Mirrors the upstream union `prompt: string | Array<ModelMessage>`.
 */
public enum PromptContent: Sendable, Equatable {
    case text(String)
    case messages([ModelMessage])
}
