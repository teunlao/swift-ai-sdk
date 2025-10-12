import Foundation

// MARK: - V2 базовые типы

public enum LanguageModelV2FinishReason: String, Sendable, Codable {
    case stop
    case length
    case contentFilter = "content-filter"
    case toolCalls = "tool-calls"
    case error
    case other
}

public struct LanguageModelV2Usage: Sendable, Codable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public enum LanguageModelV2StreamPart: Sendable, Codable, Equatable {
    case streamStart
    case responseMetadata(JSONValue)
    case textStart
    case textDelta(String)
    case textEnd
    case reasoningStart
    case reasoningDelta(String)
    case reasoningEnd
    case toolCall(JSONValue)
    case toolResult(JSONValue)
    case finish
    case error(String)
}

public struct LanguageModelV2CallOptions: Sendable {
    public var prompt: String?
    public init(prompt: String? = nil) {
        self.prompt = prompt
    }
}

public struct LanguageModelV2GenerateResult: Sendable {
    public var content: [JSONValue]
    public var finishReason: LanguageModelV2FinishReason
    public var usage: LanguageModelV2Usage
    public var providerMetadata: SharedV2ProviderMetadata?
    public var responseHeaders: SharedV2Headers?
}

public protocol LanguageModelV2: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }

    func doGenerate(options: LanguageModelV2CallOptions) async throws -> LanguageModelV2GenerateResult

    func doStream(options: LanguageModelV2CallOptions) async throws -> AsyncThrowingStream<LanguageModelV2StreamPart, Error>
}

extension LanguageModelV2 {
    public var specificationVersion: String { "v2" }
}

