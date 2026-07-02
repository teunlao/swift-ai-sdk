import Foundation

/**
 Content that the model has generated.

 Port of `@ai-sdk/provider/src/language-model/v4/language-model-v4-content.ts`.
 */
public enum LanguageModelV4Content: Sendable, Equatable, Codable {
    case text(LanguageModelV4Text)
    case reasoning(LanguageModelV4Reasoning)
    case custom(LanguageModelV4CustomContent)
    case reasoningFile(LanguageModelV4ReasoningFile)
    case file(LanguageModelV4File)
    case toolApprovalRequest(LanguageModelV4ToolApprovalRequest)
    case source(LanguageModelV4Source)
    case toolCall(LanguageModelV4ToolCall)
    case toolResult(LanguageModelV4ToolResult)

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try LanguageModelV4Text(from: decoder))
        case "reasoning":
            self = .reasoning(try LanguageModelV4Reasoning(from: decoder))
        case "custom":
            self = .custom(try LanguageModelV4CustomContent(from: decoder))
        case "reasoning-file":
            self = .reasoningFile(try LanguageModelV4ReasoningFile(from: decoder))
        case "file":
            self = .file(try LanguageModelV4File(from: decoder))
        case "tool-approval-request":
            self = .toolApprovalRequest(try LanguageModelV4ToolApprovalRequest(from: decoder))
        case "source":
            self = .source(try LanguageModelV4Source(from: decoder))
        case "tool-call":
            self = .toolCall(try LanguageModelV4ToolCall(from: decoder))
        case "tool-result":
            self = .toolResult(try LanguageModelV4ToolResult(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value):
            try value.encode(to: encoder)
        case .reasoning(let value):
            try value.encode(to: encoder)
        case .custom(let value):
            try value.encode(to: encoder)
        case .reasoningFile(let value):
            try value.encode(to: encoder)
        case .file(let value):
            try value.encode(to: encoder)
        case .toolApprovalRequest(let value):
            try value.encode(to: encoder)
        case .source(let value):
            try value.encode(to: encoder)
        case .toolCall(let value):
            try value.encode(to: encoder)
        case .toolResult(let value):
            try value.encode(to: encoder)
        }
    }
}
