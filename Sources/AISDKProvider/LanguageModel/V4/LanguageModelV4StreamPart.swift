import Foundation

public enum LanguageModelV4StreamPart: Sendable, Equatable, Codable {
    case textStart(id: String, providerMetadata: SharedV4ProviderMetadata?)
    case textDelta(id: String, delta: String, providerMetadata: SharedV4ProviderMetadata?)
    case textEnd(id: String, providerMetadata: SharedV4ProviderMetadata?)
    case reasoningStart(id: String, providerMetadata: SharedV4ProviderMetadata?)
    case reasoningDelta(id: String, delta: String, providerMetadata: SharedV4ProviderMetadata?)
    case reasoningEnd(id: String, providerMetadata: SharedV4ProviderMetadata?)
    case toolInputStart(
        id: String,
        toolName: String,
        providerMetadata: SharedV4ProviderMetadata?,
        providerExecuted: Bool?,
        dynamic: Bool?,
        title: String?
    )
    case toolInputDelta(id: String, delta: String, providerMetadata: SharedV4ProviderMetadata?)
    case toolInputEnd(id: String, providerMetadata: SharedV4ProviderMetadata?)
    case toolApprovalRequest(LanguageModelV4ToolApprovalRequest)
    case toolCall(LanguageModelV4ToolCall)
    case toolResult(LanguageModelV4ToolResult)
    case custom(LanguageModelV4CustomContent)
    case file(LanguageModelV4File)
    case reasoningFile(LanguageModelV4ReasoningFile)
    case source(LanguageModelV4Source)
    case streamStart(warnings: [SharedV4Warning])
    case responseMetadata(id: String?, modelId: String?, timestamp: Date?)
    case finish(finishReason: LanguageModelV4FinishReason, usage: LanguageModelV4Usage, providerMetadata: SharedV4ProviderMetadata?)
    case raw(rawValue: JSONValue)
    case error(error: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type, id, providerMetadata, delta, toolName, providerExecuted, dynamic, title
        case warnings, modelId, timestamp, finishReason, usage, rawValue, error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text-start":
            self = .textStart(
                id: try container.decode(String.self, forKey: .id),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "text-delta":
            self = .textDelta(
                id: try container.decode(String.self, forKey: .id),
                delta: try container.decode(String.self, forKey: .delta),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "text-end":
            self = .textEnd(
                id: try container.decode(String.self, forKey: .id),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "reasoning-start":
            self = .reasoningStart(
                id: try container.decode(String.self, forKey: .id),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "reasoning-delta":
            self = .reasoningDelta(
                id: try container.decode(String.self, forKey: .id),
                delta: try container.decode(String.self, forKey: .delta),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "reasoning-end":
            self = .reasoningEnd(
                id: try container.decode(String.self, forKey: .id),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "tool-input-start":
            self = .toolInputStart(
                id: try container.decode(String.self, forKey: .id),
                toolName: try container.decode(String.self, forKey: .toolName),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata),
                providerExecuted: try container.decodeIfPresent(Bool.self, forKey: .providerExecuted),
                dynamic: try container.decodeIfPresent(Bool.self, forKey: .dynamic),
                title: try container.decodeIfPresent(String.self, forKey: .title)
            )
        case "tool-input-delta":
            self = .toolInputDelta(
                id: try container.decode(String.self, forKey: .id),
                delta: try container.decode(String.self, forKey: .delta),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "tool-input-end":
            self = .toolInputEnd(
                id: try container.decode(String.self, forKey: .id),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "tool-approval-request":
            self = .toolApprovalRequest(try LanguageModelV4ToolApprovalRequest(from: decoder))
        case "tool-call":
            self = .toolCall(try LanguageModelV4ToolCall(from: decoder))
        case "tool-result":
            self = .toolResult(try LanguageModelV4ToolResult(from: decoder))
        case "custom":
            self = .custom(try LanguageModelV4CustomContent(from: decoder))
        case "file":
            self = .file(try LanguageModelV4File(from: decoder))
        case "reasoning-file":
            self = .reasoningFile(try LanguageModelV4ReasoningFile(from: decoder))
        case "source":
            self = .source(try LanguageModelV4Source(from: decoder))
        case "stream-start":
            self = .streamStart(warnings: try container.decode([SharedV4Warning].self, forKey: .warnings))
        case "response-metadata":
            self = .responseMetadata(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                modelId: try container.decodeIfPresent(String.self, forKey: .modelId),
                timestamp: try container.decodeIfPresent(Date.self, forKey: .timestamp)
            )
        case "finish":
            self = .finish(
                finishReason: try container.decode(LanguageModelV4FinishReason.self, forKey: .finishReason),
                usage: try container.decode(LanguageModelV4Usage.self, forKey: .usage),
                providerMetadata: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
            )
        case "raw":
            self = .raw(rawValue: try container.decode(JSONValue.self, forKey: .rawValue))
        case "error":
            self = .error(error: try container.decode(JSONValue.self, forKey: .error))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown stream part type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .textStart(id, providerMetadata):
            try container.encode("text-start", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case let .textDelta(id, delta, providerMetadata):
            try container.encode("text-delta", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(delta, forKey: .delta)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case let .textEnd(id, providerMetadata):
            try container.encode("text-end", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case let .reasoningStart(id, providerMetadata):
            try container.encode("reasoning-start", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case let .reasoningDelta(id, delta, providerMetadata):
            try container.encode("reasoning-delta", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(delta, forKey: .delta)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case let .reasoningEnd(id, providerMetadata):
            try container.encode("reasoning-end", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case let .toolInputStart(id, toolName, providerMetadata, providerExecuted, dynamic, title):
            try container.encode("tool-input-start", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(toolName, forKey: .toolName)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
            try container.encodeIfPresent(providerExecuted, forKey: .providerExecuted)
            try container.encodeIfPresent(dynamic, forKey: .dynamic)
            try container.encodeIfPresent(title, forKey: .title)
        case let .toolInputDelta(id, delta, providerMetadata):
            try container.encode("tool-input-delta", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(delta, forKey: .delta)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case let .toolInputEnd(id, providerMetadata):
            try container.encode("tool-input-end", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case .toolApprovalRequest(let request):
            try request.encode(to: encoder)
        case .toolCall(let toolCall):
            try toolCall.encode(to: encoder)
        case .toolResult(let toolResult):
            try toolResult.encode(to: encoder)
        case .custom(let custom):
            try custom.encode(to: encoder)
        case .file(let file):
            try file.encode(to: encoder)
        case .reasoningFile(let file):
            try file.encode(to: encoder)
        case .source(let source):
            try source.encode(to: encoder)
        case .streamStart(let warnings):
            try container.encode("stream-start", forKey: .type)
            try container.encode(warnings, forKey: .warnings)
        case let .responseMetadata(id, modelId, timestamp):
            try container.encode("response-metadata", forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(modelId, forKey: .modelId)
            try container.encodeIfPresent(timestamp, forKey: .timestamp)
        case let .finish(finishReason, usage, providerMetadata):
            try container.encode("finish", forKey: .type)
            try container.encode(finishReason, forKey: .finishReason)
            try container.encode(usage, forKey: .usage)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case .raw(let rawValue):
            try container.encode("raw", forKey: .type)
            try container.encode(rawValue, forKey: .rawValue)
        case .error(let error):
            try container.encode("error", forKey: .type)
            try container.encode(error, forKey: .error)
        }
    }
}
