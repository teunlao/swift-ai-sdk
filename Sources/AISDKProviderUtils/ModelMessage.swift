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
public struct SystemModelMessage: Sendable, Equatable {
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
}

// MARK: - User Message

/**
 Content of a user message. It can be a string or an array of text, image, and file parts.
 */
public enum UserContent: Sendable, Equatable {
    /// Simple text content
    case text(String)
    /// Array of content parts (text, images, files)
    case parts([UserContentPart])
}

/**
 Content part types allowed in user messages.
 */
public enum UserContentPart: Sendable, Equatable {
    case text(TextPart)
    case image(ImagePart)
    case file(FilePart)
}

/**
 A user message. It can contain text or a combination of text, images, and files.

 Port of `@ai-sdk/provider-utils/types/user-model-message.ts`.
 */
public struct UserModelMessage: Sendable, Equatable {
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
}

// MARK: - Assistant Message

/**
 Content of an assistant message.
 It can be a string or an array of text, file, reasoning, tool call, tool result, and approval request parts.
 */
public enum AssistantContent: Sendable, Equatable {
    /// Simple text content
    case text(String)
    /// Array of content parts
    case parts([AssistantContentPart])
}

/**
 Content part types allowed in assistant messages.
 */
public enum AssistantContentPart: Sendable, Equatable {
    case text(TextPart)
    case file(FilePart)
    case reasoning(ReasoningPart)
    case toolCall(ToolCallPart)
    case toolResult(ToolResultPart)
    case toolApprovalRequest(ToolApprovalRequest)
}

/**
 An assistant message. It can contain text, tool calls, or a combination of text and tool calls.

 Port of `@ai-sdk/provider-utils/types/assistant-model-message.ts`.
 */
public struct AssistantModelMessage: Sendable, Equatable {
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
}

// MARK: - Tool Message

/**
 Content part types allowed in tool messages.
 */
public enum ToolContentPart: Sendable, Equatable {
    case toolResult(ToolResultPart)
    case toolApprovalResponse(ToolApprovalResponse)
}

/**
 A tool message. It contains the result of one or more tool calls.

 Port of `@ai-sdk/provider-utils/types/tool-model-message.ts`.
 */
public struct ToolModelMessage: Sendable, Equatable {
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
}

// MARK: - Model Message Union

/**
 A message that can be used in the `messages` field of a prompt.
 It can be a user message, an assistant message, or a tool message.

 Port of `@ai-sdk/provider-utils/types/model-message.ts`.
 */
public enum ModelMessage: Sendable, Equatable {
    case system(SystemModelMessage)
    case user(UserModelMessage)
    case assistant(AssistantModelMessage)
    case tool(ToolModelMessage)
}
