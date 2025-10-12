import Foundation

/**
 Specifies how the tool should be selected. Defaults to 'auto'.

 TypeScript equivalent (discriminated union):
 ```typescript
 export type LanguageModelV2ToolChoice =
   | { type: 'auto' }
   | { type: 'none' }
   | { type: 'required' }
   | { type: 'tool'; toolName: string };
 ```
 */
public enum LanguageModelV2ToolChoice: Sendable, Equatable, Codable {
    /// The tool selection is automatic (can be no tool)
    case auto

    /// No tool must be selected
    case none

    /// One of the available tools must be selected
    case required

    /// A specific tool must be selected
    case tool(toolName: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case toolName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "auto":
            self = .auto
        case "none":
            self = .none
        case "required":
            self = .required
        case "tool":
            let toolName = try container.decode(String.self, forKey: .toolName)
            self = .tool(toolName: toolName)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool choice type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .auto:
            try container.encode("auto", forKey: .type)
        case .none:
            try container.encode("none", forKey: .type)
        case .required:
            try container.encode("required", forKey: .type)
        case .tool(let toolName):
            try container.encode("tool", forKey: .type)
            try container.encode(toolName, forKey: .toolName)
        }
    }
}
