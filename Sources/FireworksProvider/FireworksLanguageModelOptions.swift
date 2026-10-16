import Foundation

public struct FireworksLanguageModelOptions: Codable, Sendable, Equatable {
    public enum ServiceTier: String, Codable, Sendable { case priority }
    public enum ReasoningHistory: String, Codable, Sendable { case disabled, interleaved, preserved }
    public struct Thinking: Codable, Sendable, Equatable {
        public enum Mode: String, Codable, Sendable { case enabled, disabled }
        public var type: Mode?
        public var budgetTokens: Int?
        public init(type: Mode? = nil, budgetTokens: Int? = nil) { self.type = type; self.budgetTokens = budgetTokens }
    }
    public var promptCacheKey: String?
    public var serviceTier: ServiceTier?
    public var thinking: Thinking?
    public var reasoningHistory: ReasoningHistory?
    public init(promptCacheKey: String? = nil, serviceTier: ServiceTier? = nil, thinking: Thinking? = nil, reasoningHistory: ReasoningHistory? = nil) {
        self.promptCacheKey = promptCacheKey; self.serviceTier = serviceTier; self.thinking = thinking; self.reasoningHistory = reasoningHistory
    }
}

public struct FireworksEmbeddingModelOptions: Codable, Sendable, Equatable {
    public init() {}
}
