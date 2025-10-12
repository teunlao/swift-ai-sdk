import Foundation

/**
 Warning from the model provider for this call. The call will proceed, but e.g.
 some settings might not be supported, which can lead to suboptimal results.

 TypeScript equivalent (discriminated union):
 ```typescript
 export type LanguageModelV3CallWarning =
   | {
       type: 'unsupported-setting';
       setting: Omit<keyof LanguageModelV3CallOptions, 'prompt'>;
       details?: string;
     }
   | {
       type: 'unsupported-tool';
       tool: LanguageModelV3FunctionTool | LanguageModelV3ProviderDefinedTool;
       details?: string;
     }
   | {
       type: 'other';
       message: string;
     };
 ```
 */
public enum LanguageModelV3CallWarning: Sendable, Equatable, Codable {
    case unsupportedSetting(setting: String, details: String?)
    case unsupportedTool(tool: LanguageModelV3Tool, details: String?)
    case other(message: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case setting
        case tool
        case details
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "unsupported-setting":
            let setting = try container.decode(String.self, forKey: .setting)
            let details = try container.decodeIfPresent(String.self, forKey: .details)
            self = .unsupportedSetting(setting: setting, details: details)
        case "unsupported-tool":
            let tool = try container.decode(LanguageModelV3Tool.self, forKey: .tool)
            let details = try container.decodeIfPresent(String.self, forKey: .details)
            self = .unsupportedTool(tool: tool, details: details)
        case "other":
            let message = try container.decode(String.self, forKey: .message)
            self = .other(message: message)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown warning type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .unsupportedSetting(setting, details):
            try container.encode("unsupported-setting", forKey: .type)
            try container.encode(setting, forKey: .setting)
            try container.encodeIfPresent(details, forKey: .details)
        case let .unsupportedTool(tool, details):
            try container.encode("unsupported-tool", forKey: .type)
            try container.encode(tool, forKey: .tool)
            try container.encodeIfPresent(details, forKey: .details)
        case let .other(message):
            try container.encode("other", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

/// Union type for tools (FunctionTool or ProviderDefinedTool)
public enum LanguageModelV3Tool: Sendable, Equatable, Codable {
    case function(LanguageModelV3FunctionTool)
    case providerDefined(LanguageModelV3ProviderDefinedTool)

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "function":
            self = .function(try LanguageModelV3FunctionTool(from: decoder))
        case "provider-defined":
            self = .providerDefined(try LanguageModelV3ProviderDefinedTool(from: decoder))
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
        case .providerDefined(let tool):
            try tool.encode(to: encoder)
        }
    }
}
