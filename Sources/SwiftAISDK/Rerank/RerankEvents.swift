import AISDKProvider
import AISDKProviderUtils

public struct RerankStartEvent<Value: Sendable>: Sendable {
    public let runtimeContext: Context
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
    public let runtimeContext: Context
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

public struct RerankingModelCallStartEvent: Sendable {
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    /// The documents as JSON: a string or an object per document.
    public let documents: [JSONValue]
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

extension RerankStartEvent {
    func with(runtimeContext: Context) -> Self {
        RerankStartEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: operationId,
            provider: provider, modelId: modelId, documents: documents, query: query,
            topN: topN, maxRetries: maxRetries, headers: headers, providerOptions: providerOptions
        )
    }

    func mapDocuments<T: Sendable>(_ transform: (Value) -> T) -> RerankStartEvent<T> {
        RerankStartEvent<T>(
            runtimeContext: runtimeContext, callId: callId, operationId: operationId,
            provider: provider, modelId: modelId, documents: documents.map(transform), query: query,
            topN: topN, maxRetries: maxRetries, headers: headers, providerOptions: providerOptions
        )
    }
}

extension RerankEndEvent {
    func with(runtimeContext: Context) -> Self {
        RerankEndEvent(
            runtimeContext: runtimeContext, callId: callId, operationId: operationId,
            provider: provider, modelId: modelId, documents: documents, query: query,
            ranking: ranking, warnings: warnings, providerMetadata: providerMetadata, response: response
        )
    }

    func mapDocuments<T: Sendable>(_ transform: (Value) -> T) -> RerankEndEvent<T> {
        RerankEndEvent<T>(
            runtimeContext: runtimeContext, callId: callId, operationId: operationId,
            provider: provider, modelId: modelId, documents: documents.map(transform), query: query,
            ranking: ranking.map { RerankRanking(originalIndex: $0.originalIndex, score: $0.score, document: transform($0.document)) },
            warnings: warnings, providerMetadata: providerMetadata, response: response
        )
    }
}
