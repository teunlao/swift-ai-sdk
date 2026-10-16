import AISDKProvider
import AISDKProviderUtils

public struct RerankStartEvent<Value: Sendable>: Sendable {
    public let runtimeContext: [String: any Sendable]
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let documents: [Value]
    public let query: String
    public let topN: Int?
    public let maxRetries: Int
    public let headers: [String: String]?
    public let providerOptions: ProviderOptions?
}

public struct RerankEndEvent<Value: Sendable>: Sendable {
    public let runtimeContext: [String: any Sendable]
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let documents: [Value]
    public let query: String
    public let ranking: [RerankRanking<Value>]
    public let warnings: [SharedV4Warning]
    public let providerMetadata: ProviderMetadata?
    public let response: RerankResponse
}

public struct RerankingModelCallStartEvent<Value: Sendable>: Sendable {
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let documents: [Value]
    public let documentsType: String
    public let query: String
    public let topN: Int?
}

public struct RerankingModelCallEndEvent: Sendable {
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let documentsType: String
    public let ranking: [RerankingModelV4Ranking]
}
