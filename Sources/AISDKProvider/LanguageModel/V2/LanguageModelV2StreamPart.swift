import Foundation

/**
 Stream parts for language model V2 streaming responses.

 TypeScript equivalent (discriminated union):
 ```typescript
 export type LanguageModelV2StreamPart =
   // Text blocks:
   | { type: 'text-start'; providerMetadata?: SharedV2ProviderMetadata; id: string; }
   | { type: 'text-delta'; id: string; providerMetadata?: SharedV2ProviderMetadata; delta: string; }
   | { type: 'text-end'; providerMetadata?: SharedV2ProviderMetadata; id: string; }

   // Reasoning blocks:
   | { type: 'reasoning-start'; providerMetadata?: SharedV2ProviderMetadata; id: string; }
   | { type: 'reasoning-delta'; id: string; providerMetadata?: SharedV2ProviderMetadata; delta: string; }
   | { type: 'reasoning-end'; id: string; providerMetadata?: SharedV2ProviderMetadata; }

   // Tool calls and results:
   | { type: 'tool-input-start'; id: string; toolName: string; providerMetadata?: SharedV2ProviderMetadata; providerExecuted?: boolean; }
   | { type: 'tool-input-delta'; id: string; delta: string; providerMetadata?: SharedV2ProviderMetadata; }
   | { type: 'tool-input-end'; id: string; providerMetadata?: SharedV2ProviderMetadata; }
   | LanguageModelV2ToolCall
   | LanguageModelV2ToolResult

   // Files and sources:
   | LanguageModelV2File
   | LanguageModelV2Source

   // stream start event with warnings:
   | { type: 'stream-start'; warnings: Array<LanguageModelV2CallWarning>; }

   // metadata for the response:
   | ({ type: 'response-metadata' } & LanguageModelV2ResponseMetadata)

   // metadata available after stream is finished:
   | { type: 'finish'; usage: LanguageModelV2Usage; finishReason: LanguageModelV2FinishReason; providerMetadata?: SharedV2ProviderMetadata; }

   // raw chunks if enabled:
   | { type: 'raw'; rawValue: unknown; }

   // error parts:
   | { type: 'error'; error: unknown; }
 ```
 */
public enum LanguageModelV2StreamPart: Sendable, Equatable, Codable {
    // Text blocks:
    case textStart(id: String, providerMetadata: SharedV2ProviderMetadata?)
    case textDelta(id: String, delta: String, providerMetadata: SharedV2ProviderMetadata?)
    case textEnd(id: String, providerMetadata: SharedV2ProviderMetadata?)

    // Reasoning blocks:
    case reasoningStart(id: String, providerMetadata: SharedV2ProviderMetadata?)
    case reasoningDelta(id: String, delta: String, providerMetadata: SharedV2ProviderMetadata?)
    case reasoningEnd(id: String, providerMetadata: SharedV2ProviderMetadata?)

    // Tool input blocks (streaming tool arguments):
    case toolInputStart(id: String, toolName: String, providerMetadata: SharedV2ProviderMetadata?, providerExecuted: Bool?)
    case toolInputDelta(id: String, delta: String, providerMetadata: SharedV2ProviderMetadata?)
    case toolInputEnd(id: String, providerMetadata: SharedV2ProviderMetadata?)

    // Tool call and result (complete types, not inline fields):
    case toolCall(LanguageModelV2ToolCall)
    case toolResult(LanguageModelV2ToolResult)

    // Files and sources:
    case file(LanguageModelV2File)
    case source(LanguageModelV2Source)

    // Stream start with warnings:
    case streamStart(warnings: [LanguageModelV2CallWarning])

    // Response metadata (intersection type: flatten fields):
    case responseMetadata(id: String?, modelId: String?, timestamp: Date?)

    // Finish with usage:
    case finish(finishReason: LanguageModelV2FinishReason, usage: LanguageModelV2Usage, providerMetadata: SharedV2ProviderMetadata?)

    // Raw chunks:
    case raw(rawValue: JSONValue)

    // Error:
    case error(error: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case providerMetadata
        case delta
        case toolName
        case providerExecuted
        case warnings
        case modelId
        case timestamp
        case finishReason
        case usage
        case rawValue
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        // Text blocks:
        case "text-start":
            let id = try container.decode(String.self, forKey: .id)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .textStart(id: id, providerMetadata: providerMetadata)

        case "text-delta":
            let id = try container.decode(String.self, forKey: .id)
            let delta = try container.decode(String.self, forKey: .delta)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .textDelta(id: id, delta: delta, providerMetadata: providerMetadata)

        case "text-end":
            let id = try container.decode(String.self, forKey: .id)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .textEnd(id: id, providerMetadata: providerMetadata)

        // Reasoning blocks:
        case "reasoning-start":
            let id = try container.decode(String.self, forKey: .id)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .reasoningStart(id: id, providerMetadata: providerMetadata)

        case "reasoning-delta":
            let id = try container.decode(String.self, forKey: .id)
            let delta = try container.decode(String.self, forKey: .delta)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .reasoningDelta(id: id, delta: delta, providerMetadata: providerMetadata)

        case "reasoning-end":
            let id = try container.decode(String.self, forKey: .id)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .reasoningEnd(id: id, providerMetadata: providerMetadata)

        // Tool input blocks:
        case "tool-input-start":
            let id = try container.decode(String.self, forKey: .id)
            let toolName = try container.decode(String.self, forKey: .toolName)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            let providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
            self = .toolInputStart(id: id, toolName: toolName, providerMetadata: providerMetadata, providerExecuted: providerExecuted)

        case "tool-input-delta":
            let id = try container.decode(String.self, forKey: .id)
            let delta = try container.decode(String.self, forKey: .delta)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata)

        case "tool-input-end":
            let id = try container.decode(String.self, forKey: .id)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .toolInputEnd(id: id, providerMetadata: providerMetadata)

        // Tool call and result (decode as complete types):
        case "tool-call":
            let toolCall = try LanguageModelV2ToolCall(from: decoder)
            self = .toolCall(toolCall)

        case "tool-result":
            let toolResult = try LanguageModelV2ToolResult(from: decoder)
            self = .toolResult(toolResult)

        // Files and sources:
        case "file":
            let file = try LanguageModelV2File(from: decoder)
            self = .file(file)

        case "source":
            let source = try LanguageModelV2Source(from: decoder)
            self = .source(source)

        // Stream start:
        case "stream-start":
            let warnings = try container.decode([LanguageModelV2CallWarning].self, forKey: .warnings)
            self = .streamStart(warnings: warnings)

        // Response metadata (flatten intersection type):
        case "response-metadata":
            let id = try container.decodeIfPresent(String.self, forKey: .id)
            let modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
            let timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
            self = .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)

        // Finish:
        case "finish":
            let finishReason = try container.decode(LanguageModelV2FinishReason.self, forKey: .finishReason)
            let usage = try container.decode(LanguageModelV2Usage.self, forKey: .usage)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata)

        // Raw:
        case "raw":
            let rawValue = try container.decode(JSONValue.self, forKey: .rawValue)
            self = .raw(rawValue: rawValue)

        // Error:
        case "error":
            let error = try container.decode(JSONValue.self, forKey: .error)
            self = .error(error: error)

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
        // Text blocks:
        case .textStart(let id, let providerMetadata):
            try container.encode("text-start", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        case .textDelta(let id, let delta, let providerMetadata):
            try container.encode("text-delta", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(delta, forKey: .delta)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        case .textEnd(let id, let providerMetadata):
            try container.encode("text-end", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        // Reasoning blocks:
        case .reasoningStart(let id, let providerMetadata):
            try container.encode("reasoning-start", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        case .reasoningDelta(let id, let delta, let providerMetadata):
            try container.encode("reasoning-delta", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(delta, forKey: .delta)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        case .reasoningEnd(let id, let providerMetadata):
            try container.encode("reasoning-end", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        // Tool input blocks:
        case .toolInputStart(let id, let toolName, let providerMetadata, let providerExecuted):
            try container.encode("tool-input-start", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(toolName, forKey: .toolName)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
            try container.encodeIfPresent(providerExecuted, forKey: .providerExecuted)

        case .toolInputDelta(let id, let delta, let providerMetadata):
            try container.encode("tool-input-delta", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(delta, forKey: .delta)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        case .toolInputEnd(let id, let providerMetadata):
            try container.encode("tool-input-end", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        // Tool call and result (encode complete types):
        case .toolCall(let toolCall):
            try toolCall.encode(to: encoder)

        case .toolResult(let toolResult):
            try toolResult.encode(to: encoder)

        // Files and sources:
        case .file(let file):
            try file.encode(to: encoder)

        case .source(let source):
            try source.encode(to: encoder)

        // Stream start:
        case .streamStart(let warnings):
            try container.encode("stream-start", forKey: .type)
            try container.encode(warnings, forKey: .warnings)

        // Response metadata:
        case .responseMetadata(let id, let modelId, let timestamp):
            try container.encode("response-metadata", forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(modelId, forKey: .modelId)
            try container.encodeIfPresent(timestamp, forKey: .timestamp)

        // Finish:
        case .finish(let finishReason, let usage, let providerMetadata):
            try container.encode("finish", forKey: .type)
            try container.encode(finishReason, forKey: .finishReason)
            try container.encode(usage, forKey: .usage)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)

        // Raw:
        case .raw(let rawValue):
            try container.encode("raw", forKey: .type)
            try container.encode(rawValue, forKey: .rawValue)

        // Error:
        case .error(let error):
            try container.encode("error", forKey: .type)
            try container.encode(error, forKey: .error)
        }
    }
}

/**
 Finish reason enum.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2FinishReason = 'stop' | 'length' | 'content-filter' | 'tool-calls' | 'error' | 'other' | 'unknown';
 ```
 */
public enum LanguageModelV2FinishReason: String, Sendable, Codable, Equatable {
    case stop
    case length
    case contentFilter = "content-filter"
    case toolCalls = "tool-calls"
    case error
    case other
    case unknown
}

/**
 Usage information.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2Usage = {
   inputTokens: number | undefined;
   outputTokens: number | undefined;
   totalTokens: number | undefined;
   reasoningTokens?: number | undefined;
   cachedInputTokens?: number | undefined;
 };
 ```
 */
public struct LanguageModelV2Usage: Sendable, Codable, Equatable {
    /// The number of input (prompt) tokens used.
    public let inputTokens: Int?

    /// The number of output (completion) tokens used.
    public let outputTokens: Int?

    /// The total number of tokens as reported by the provider.
    /// This number might be different from the sum of `inputTokens` and `outputTokens`
    /// and e.g. include reasoning tokens or other overhead.
    public let totalTokens: Int?

    /// The number of reasoning tokens used.
    public let reasoningTokens: Int?

    /// The number of cached input tokens.
    public let cachedInputTokens: Int?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        cachedInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.reasoningTokens = reasoningTokens
        self.cachedInputTokens = cachedInputTokens
    }
}
