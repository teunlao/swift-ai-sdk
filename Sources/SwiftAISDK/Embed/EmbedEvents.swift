import AISDKProvider
import AISDKProviderUtils

public struct EmbedStartEvent<Value: Sendable>: Sendable {
    public let runtimeContext: [String: any Sendable]
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let value: Value
    public let dimensions: Int?
    public let maxRetries: Int
    public let headers: [String: String]?
    public let providerOptions: ProviderOptions?
}

public enum EmbedResponse: Sendable {
    case single(EmbeddingModelV4ResponseInfo?)
    case many([EmbeddingModelV4ResponseInfo?])
}

public struct EmbedEndEvent<Value: Sendable, Output: Sendable>: Sendable {
    public let runtimeContext: [String: any Sendable]
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let value: Value
    public let embedding: Output
    public let usage: EmbeddingModelUsage
    public let warnings: [SharedV4Warning]
    public let providerMetadata: ProviderMetadata?
    public let response: EmbedResponse
}

public struct EmbeddingModelCallStartEvent: Sendable {
    public let callId: String
    public let embedCallId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let values: [String]
    public let dimensions: Int?
}

public struct EmbeddingModelCallEndEvent: Sendable {
    public let callId: String
    public let embedCallId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let values: [String]
    public let embeddings: [Embedding]
    public let usage: EmbeddingModelUsage
}
