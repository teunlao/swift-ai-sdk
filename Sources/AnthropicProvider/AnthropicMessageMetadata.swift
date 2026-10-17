import AISDKProvider

public struct AnthropicUsageIteration: Codable, Sendable {
    public let type: String
    public let model: String?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?
}

public struct AnthropicMessageMetadata: Codable, Sendable {
    public struct StopDetails: Codable, Sendable {
        public let type: String
        public let category: String?
        public let explanation: String?
        public let recommendedModel: String?
    }

    public struct Container: Codable, Sendable {
        public struct Skill: Codable, Sendable {
            public let type: String
            public let skillId: String
            public let version: String
        }
        public let expiresAt: String
        public let id: String
        public let skills: [Skill]?
    }

    public struct ContextManagement: Codable, Sendable {
        public struct AppliedEdit: Codable, Sendable {
            public let type: String
            public let clearedToolUses: Int?
            public let clearedThinkingTurns: Int?
            public let clearedInputTokens: Int?
        }
        public let appliedEdits: [AppliedEdit]
    }

    public let usage: [String: JSONValue]
    public let stopSequence: String?
    public let inputTransformations: [AnthropicInputTransformation]?
    public let safeguardResults: [AnthropicSafeguardResult]?
    public let stopDetails: StopDetails?
    public let iterations: [AnthropicUsageIteration]?
    public let container: Container?
    public let contextManagement: ContextManagement?
}

public struct AnthropicTextProviderMetadata: Codable, Sendable {
    public struct Content: Codable, Sendable {
        public let citations: [AnthropicCitation]
    }
    public let anthropic: Content
}
