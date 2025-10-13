import Foundation

/**
 Content that the model has generated (discriminated union).

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV3Content =
   | LanguageModelV3Text
   | LanguageModelV3Reasoning
   | LanguageModelV3File
   | LanguageModelV3Source
   | LanguageModelV3ToolCall
   | LanguageModelV3ToolResult;
 ```
 */
public enum LanguageModelV3Content: Sendable, Equatable, Codable {
    case text(LanguageModelV3Text)
    case reasoning(LanguageModelV3Reasoning)
    case file(LanguageModelV3File)
    case source(LanguageModelV3Source)
    case toolCall(LanguageModelV3ToolCall)
    case toolResult(LanguageModelV3ToolResult)

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try LanguageModelV3Text(from: decoder))
        case "reasoning":
            self = .reasoning(try LanguageModelV3Reasoning(from: decoder))
        case "file":
            self = .file(try LanguageModelV3File(from: decoder))
        case "source":
            self = .source(try LanguageModelV3Source(from: decoder))
        case "tool-call":
            self = .toolCall(try LanguageModelV3ToolCall(from: decoder))
        case "tool-result":
            self = .toolResult(try LanguageModelV3ToolResult(from: decoder))
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
