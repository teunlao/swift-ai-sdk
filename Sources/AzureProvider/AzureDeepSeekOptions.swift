public struct AzureDeepSeekLanguageModelOptions: Sendable, Encodable, Equatable {
    public enum ReasoningEffort: String, Sendable, Encodable {
        case low, high, max
    }

    public var logprobs: Bool?
    public var topLogprobs: Int?
    public var userId: String?
    public var reasoningEffort: ReasoningEffort?
    public var strictJsonSchema: Bool?

    public init(
        logprobs: Bool? = nil,
        topLogprobs: Int? = nil,
        userId: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        strictJsonSchema: Bool? = nil
    ) {
        self.logprobs = logprobs
        self.topLogprobs = topLogprobs
        self.userId = userId
        self.reasoningEffort = reasoningEffort
        self.strictJsonSchema = strictJsonSchema
    }
}
