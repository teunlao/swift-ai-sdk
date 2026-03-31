import Foundation
import AISDKProvider

/**
 Model message types for prompts and conversations.

 Port of `@ai-sdk/provider-utils/types/model-message.ts` and related files:
 - `system-model-message.ts`
 - `user-model-message.ts`
 - `assistant-model-message.ts`
 - `tool-model-message.ts`

 Model messages represent different roles in a conversation:
 - System: System instructions and context
 - User: User input (text, images, files)
 - Assistant: Model responses (text, tool calls, reasoning)
 - Tool: Tool execution results
 */

// MARK: - System Message

/**
 A system message. It can contain system information.

 Note: using the "system" part of the prompt is strongly preferred
 to increase the resilience against prompt injection attacks,
 and because not all providers support several system messages.

 Port of `@ai-sdk/provider-utils/types/system-model-message.ts`.
 */
public struct SystemModelMessage: Sendable, Equatable, Codable {
    public let role: String = "system"

    /// System content (text only).
    public let content: String

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(content: String, providerOptions: ProviderOptions? = nil) {
        self.content = content
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case role, content, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - User Message

/**
 A user message. It can contain text or a combination of text, images, and files.

 Port of `@ai-sdk/provider-utils/types/user-model-message.ts`.
 */
public struct UserModelMessage: Sendable, Equatable, Codable {
    public let role: String = "user"

    /// Content of the user message.
    public let content: UserContent

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(content: UserContent, providerOptions: ProviderOptions? = nil) {
        self.content = content
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case role, content, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(UserContent.self, forKey: .content)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - Assistant Message

/**
 An assistant message. It can contain text, tool calls, or a combination of text and tool calls.

 Port of `@ai-sdk/provider-utils/types/assistant-model-message.ts`.
 */
public struct AssistantModelMessage: Sendable, Equatable, Codable {
    public let role: String = "assistant"

    /// Content of the assistant message.
    public let content: AssistantContent

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(content: AssistantContent, providerOptions: ProviderOptions? = nil) {
        self.content = content
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case role, content, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(AssistantContent.self, forKey: .content)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - Tool Message

/**
 A tool message. It contains the result of one or more tool calls.

 Port of `@ai-sdk/provider-utils/types/tool-model-message.ts`.
 */
public struct ToolModelMessage: Sendable, Equatable, Codable {
    public let role: String = "tool"

    /// Content of the tool message (array of tool results and approval responses).
    public let content: [ToolContentPart]

    /// Additional provider-specific metadata. They are passed through
    /// to the provider from the AI SDK and enable provider-specific
    /// functionality that can be fully encapsulated in the provider.
    public let providerOptions: ProviderOptions?

    public init(content: [ToolContentPart], providerOptions: ProviderOptions? = nil) {
        self.content = content
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case role, content, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode([ToolContentPart].self, forKey: .content)
        providerOptions = try container.decodeIfPresent(ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

// MARK: - Model Message Union

/**
 A message that can be used in the `messages` field of a prompt.
 It can be a user message, an assistant message, or a tool message.

 Port of `@ai-sdk/provider-utils/types/model-message.ts`.
 */
public enum ModelMessage: Sendable, Equatable, Codable {
    case system(SystemModelMessage)
    case user(UserModelMessage)
    case assistant(AssistantModelMessage)
    case tool(ToolModelMessage)

    private enum CodingKeys: String, CodingKey {
        case role
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(String.self, forKey: .role)

        switch role {
        case "system":
            self = .system(try SystemModelMessage(from: decoder))
        case "user":
            self = .user(try UserModelMessage(from: decoder))
        case "assistant":
            self = .assistant(try AssistantModelMessage(from: decoder))
        case "tool":
            self = .tool(try ToolModelMessage(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .role,
                in: container,
                debugDescription: "Unknown ModelMessage role: \(role)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .system(let message):
            try message.encode(to: encoder)
        case .user(let message):
            try message.encode(to: encoder)
        case .assistant(let message):
            try message.encode(to: encoder)
        case .tool(let message):
            try message.encode(to: encoder)
        }
    }
}
