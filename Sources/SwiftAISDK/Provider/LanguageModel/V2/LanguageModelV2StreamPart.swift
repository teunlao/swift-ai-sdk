import Foundation

/**
 Stream parts for language model V2 streaming responses.

 TypeScript equivalent (discriminated union):
 ```typescript
 export type LanguageModelV2StreamPart =
   | { type: 'stream-start'; metadata: LanguageModelV2ResponseMetadata }
   | { type: 'response-metadata'; metadata: LanguageModelV2ResponseMetadata }
   | { type: 'text-start' }
   | { type: 'text-delta'; textDelta: string }
   | { type: 'text-end' }
   | { type: 'reasoning-start' }
   | { type: 'reasoning-delta'; textDelta: string }
   | { type: 'reasoning-end' }
   | { type: 'tool-call'; toolCallId: string; toolName: string; input: string }
   | { type: 'tool-result'; toolCallId: string; toolName: string; result: unknown; isError?: boolean }
   | { type: 'finish'; finishReason: LanguageModelV2FinishReason; usage: LanguageModelV2Usage; providerMetadata?: SharedV2ProviderMetadata }
   | { type: 'error'; error: unknown }
   | { type: 'raw-chunk'; rawChunk: unknown };
 ```
 */
public enum LanguageModelV2StreamPart: Sendable, Equatable, Codable {
    case streamStart(metadata: LanguageModelV2ResponseMetadata)
    case responseMetadata(metadata: LanguageModelV2ResponseMetadata)
    case textStart
    case textDelta(textDelta: String)
    case textEnd
    case reasoningStart
    case reasoningDelta(textDelta: String)
    case reasoningEnd
    case toolCall(toolCallId: String, toolName: String, input: String)
    case toolResult(toolCallId: String, toolName: String, result: JSONValue, isError: Bool?)
    case finish(finishReason: LanguageModelV2FinishReason, usage: LanguageModelV2Usage, providerMetadata: SharedV2ProviderMetadata?)
    case error(error: String)
    case rawChunk(rawChunk: JSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
        case metadata
        case textDelta
        case toolCallId
        case toolName
        case input
        case result
        case isError
        case finishReason
        case usage
        case providerMetadata
        case error
        case rawChunk
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "stream-start":
            let metadata = try container.decode(LanguageModelV2ResponseMetadata.self, forKey: .metadata)
            self = .streamStart(metadata: metadata)
        case "response-metadata":
            let metadata = try container.decode(LanguageModelV2ResponseMetadata.self, forKey: .metadata)
            self = .responseMetadata(metadata: metadata)
        case "text-start":
            self = .textStart
        case "text-delta":
            let textDelta = try container.decode(String.self, forKey: .textDelta)
            self = .textDelta(textDelta: textDelta)
        case "text-end":
            self = .textEnd
        case "reasoning-start":
            self = .reasoningStart
        case "reasoning-delta":
            let textDelta = try container.decode(String.self, forKey: .textDelta)
            self = .reasoningDelta(textDelta: textDelta)
        case "reasoning-end":
            self = .reasoningEnd
        case "tool-call":
            let toolCallId = try container.decode(String.self, forKey: .toolCallId)
            let toolName = try container.decode(String.self, forKey: .toolName)
            let input = try container.decode(String.self, forKey: .input)
            self = .toolCall(toolCallId: toolCallId, toolName: toolName, input: input)
        case "tool-result":
            let toolCallId = try container.decode(String.self, forKey: .toolCallId)
            let toolName = try container.decode(String.self, forKey: .toolName)
            let result = try container.decode(JSONValue.self, forKey: .result)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
            self = .toolResult(toolCallId: toolCallId, toolName: toolName, result: result, isError: isError)
        case "finish":
            let finishReason = try container.decode(LanguageModelV2FinishReason.self, forKey: .finishReason)
            let usage = try container.decode(LanguageModelV2Usage.self, forKey: .usage)
            let providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
            self = .finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata)
        case "error":
            let error = try container.decode(String.self, forKey: .error)
            self = .error(error: error)
        case "raw-chunk":
            let rawChunk = try container.decode(JSONValue.self, forKey: .rawChunk)
            self = .rawChunk(rawChunk: rawChunk)
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
        case .streamStart(let metadata):
            try container.encode("stream-start", forKey: .type)
            try container.encode(metadata, forKey: .metadata)
        case .responseMetadata(let metadata):
            try container.encode("response-metadata", forKey: .type)
            try container.encode(metadata, forKey: .metadata)
        case .textStart:
            try container.encode("text-start", forKey: .type)
        case .textDelta(let textDelta):
            try container.encode("text-delta", forKey: .type)
            try container.encode(textDelta, forKey: .textDelta)
        case .textEnd:
            try container.encode("text-end", forKey: .type)
        case .reasoningStart:
            try container.encode("reasoning-start", forKey: .type)
        case .reasoningDelta(let textDelta):
            try container.encode("reasoning-delta", forKey: .type)
            try container.encode(textDelta, forKey: .textDelta)
        case .reasoningEnd:
            try container.encode("reasoning-end", forKey: .type)
        case .toolCall(let toolCallId, let toolName, let input):
            try container.encode("tool-call", forKey: .type)
            try container.encode(toolCallId, forKey: .toolCallId)
            try container.encode(toolName, forKey: .toolName)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolCallId, let toolName, let result, let isError):
            try container.encode("tool-result", forKey: .type)
            try container.encode(toolCallId, forKey: .toolCallId)
            try container.encode(toolName, forKey: .toolName)
            try container.encode(result, forKey: .result)
            try container.encodeIfPresent(isError, forKey: .isError)
        case .finish(let finishReason, let usage, let providerMetadata):
            try container.encode("finish", forKey: .type)
            try container.encode(finishReason, forKey: .finishReason)
            try container.encode(usage, forKey: .usage)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case .error(let error):
            try container.encode("error", forKey: .type)
            try container.encode(error, forKey: .error)
        case .rawChunk(let rawChunk):
            try container.encode("raw-chunk", forKey: .type)
            try container.encode(rawChunk, forKey: .rawChunk)
        }
    }
}

/**
 Finish reason enum.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2FinishReason = 'stop' | 'length' | 'content-filter' | 'tool-calls' | 'error' | 'other';
 ```
 */
public enum LanguageModelV2FinishReason: String, Sendable, Codable, Equatable {
    case stop
    case length
    case contentFilter = "content-filter"
    case toolCalls = "tool-calls"
    case error
    case other
}

/**
 Usage information.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2Usage = {
   inputTokens: number;
   outputTokens: number;
   totalTokens: number;
 };
 ```
 */
public struct LanguageModelV2Usage: Sendable, Codable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}
