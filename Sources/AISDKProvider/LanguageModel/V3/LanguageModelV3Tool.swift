import Foundation

/**
 Union type for tools (FunctionTool or ProviderTool).

 Port of `LanguageModelV3CallOptions['tools']` union:
 `LanguageModelV3FunctionTool | LanguageModelV3ProviderTool`.
 */
public enum LanguageModelV3Tool: Sendable, Equatable, Codable {
    case function(LanguageModelV3FunctionTool)
    case provider(LanguageModelV3ProviderTool)

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "function":
            self = .function(try LanguageModelV3FunctionTool(from: decoder))
        case "provider":
            self = .provider(try LanguageModelV3ProviderTool(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .function(let tool):
            try tool.encode(to: encoder)
        case .provider(let tool):
            try tool.encode(to: encoder)
        }
    }
}
