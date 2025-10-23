import Foundation
import AISDKProvider

/// Swift representation of the xAI chat prompt structures.
/// Mirrors `packages/xai/src/xai-chat-prompt.ts`.
public typealias XAIChatPrompt = [XAIChatMessage]

public struct XAIChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public struct ToolCall: Sendable, Equatable {
        public let id: String
        public let name: String
        public let arguments: String

        public func toJSON() -> JSONValue {
            .object([
                "id": .string(id),
                "type": .string("function"),
                "function": .object([
                    "name": .string(name),
                    "arguments": .string(arguments)
                ])
            ])
        }
    }

    public let role: Role
    public let textContent: String?
    public let userContentParts: [XAIUserMessageContent]?
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?

    public init(
        role: Role,
        textContent: String? = nil,
        userContentParts: [XAIUserMessageContent]? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil
    ) {
        self.role = role
        self.textContent = textContent
        self.userContentParts = userContentParts
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    public var assistantContent: String? {
        guard role == .assistant else { return nil }
        return textContent
    }

    public func toJSON() -> JSONValue {
        switch role {
        case .system:
            return .object([
                "role": .string("system"),
                "content": .string(textContent ?? "")
            ])
        case .user:
            if let text = textContent {
                return .object([
                    "role": .string("user"),
                    "content": .string(text)
                ])
            }

            let parts = (userContentParts ?? []).map { $0.toJSON() }
            return .object([
                "role": .string("user"),
                "content": .array(parts)
            ])
        case .assistant:
            var payload: [String: JSONValue] = ["role": .string("assistant")]
            if let text = textContent {
                payload["content"] = .string(text)
            }
            if let toolCalls {
                payload["tool_calls"] = .array(toolCalls.map { $0.toJSON() })
            }
            return .object(payload)
        case .tool:
            var payload: [String: JSONValue] = [
                "role": .string("tool"),
                "content": .string(textContent ?? "")
            ]
            if let toolCallId {
                payload["tool_call_id"] = .string(toolCallId)
            }
            return .object(payload)
        }
    }
}

public enum XAIUserMessageContent: Sendable, Equatable {
    case text(String)
    case imageURL(String)

    func toJSON() -> JSONValue {
        switch self {
        case .text(let text):
            return .object([
                "type": .string("text"),
                "text": .string(text)
            ])
        case .imageURL(let url):
            return .object([
                "type": .string("image_url"),
                "image_url": .object([
                    "url": .string(url)
                ])
            ])
        }
    }
}
