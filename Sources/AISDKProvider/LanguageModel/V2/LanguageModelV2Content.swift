import Foundation

/**
 Content that the model has generated (discriminated union).

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2Content =
   | LanguageModelV2Text
   | LanguageModelV2Reasoning
   | LanguageModelV2File
   | LanguageModelV2Source
   | LanguageModelV2ToolCall
   | LanguageModelV2ToolResult;
 ```
 */
public enum LanguageModelV2Content: Sendable, Equatable, Codable {
    case text(LanguageModelV2Text)
    case reasoning(LanguageModelV2Reasoning)
    case file(LanguageModelV2File)
    case source(LanguageModelV2Source)
    case toolCall(LanguageModelV2ToolCall)
    case toolResult(LanguageModelV2ToolResult)

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try LanguageModelV2Text(from: decoder))
        case "reasoning":
            self = .reasoning(try LanguageModelV2Reasoning(from: decoder))
        case "file":
            self = .file(try LanguageModelV2File(from: decoder))
        case "source":
            self = .source(try LanguageModelV2Source(from: decoder))
        case "tool-call":
            self = .toolCall(try LanguageModelV2ToolCall(from: decoder))
        case "tool-result":
            self = .toolResult(try LanguageModelV2ToolResult(from: decoder))
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
        case .file(let value):
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
