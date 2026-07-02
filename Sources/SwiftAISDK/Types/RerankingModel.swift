import AISDKProvider

/**
 Reranking model input union.

 Port of `@ai-sdk/ai/src/types/reranking-model.ts`.
 */
public enum RerankingModel: Sendable {
    /// Model identifier string (will be resolved via the global/default provider).
    case string(String)

    /// Reranking model V4 implementation.
    case v4(any RerankingModelV4)

    /// Reranking model V3 implementation.
    case v3(any RerankingModelV3)
}
