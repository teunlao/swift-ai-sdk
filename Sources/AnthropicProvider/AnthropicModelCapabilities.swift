import Foundation

public struct AnthropicModelCapabilities: Sendable {
    public let maxOutputTokens: Int
    public let supportsStructuredOutput: Bool
    public let supportsAdaptiveThinking: Bool
    public let rejectsSamplingParameters: Bool
    public let supportsXhighEffort: Bool
    public let rejectsThinkingDisabledAboveHighEffort: Bool
    public let rejectsThinkingDisabled: Bool
    public let rejectsBudgetThinking: Bool
    public let rejectsForcedToolUse: Bool
    public let supportsBetweenToolsThinking: Bool
    public let isKnownModel: Bool

    init(
        maxOutputTokens: Int = 4096,
        supportsStructuredOutput: Bool = false,
        supportsAdaptiveThinking: Bool = false,
        rejectsSamplingParameters: Bool = false,
        supportsXhighEffort: Bool = false,
        rejectsThinkingDisabledAboveHighEffort: Bool = false,
        rejectsThinkingDisabled: Bool = false,
        rejectsBudgetThinking: Bool = false,
        rejectsForcedToolUse: Bool = false,
        supportsBetweenToolsThinking: Bool = false,
        isKnownModel: Bool = true
    ) {
        self.maxOutputTokens = maxOutputTokens
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsAdaptiveThinking = supportsAdaptiveThinking
        self.rejectsSamplingParameters = rejectsSamplingParameters
        self.supportsXhighEffort = supportsXhighEffort
        self.rejectsThinkingDisabledAboveHighEffort = rejectsThinkingDisabledAboveHighEffort
        self.rejectsThinkingDisabled = rejectsThinkingDisabled
        self.rejectsBudgetThinking = rejectsBudgetThinking
        self.rejectsForcedToolUse = rejectsForcedToolUse
        self.supportsBetweenToolsThinking = supportsBetweenToolsThinking
        self.isKnownModel = isKnownModel
    }
}

public func getAnthropicModelCapabilities(modelId: String) -> AnthropicModelCapabilities {
    if modelId.contains("claude-sonnet-5-5") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true,
                     supportsAdaptiveThinking: true, rejectsSamplingParameters: true,
                     supportsXhighEffort: true, rejectsThinkingDisabledAboveHighEffort: true,
                     rejectsThinkingDisabled: true, rejectsBudgetThinking: true,
                     rejectsForcedToolUse: true, supportsBetweenToolsThinking: true)
    }
    if modelId.contains("claude-opus-5-5") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true,
                     supportsAdaptiveThinking: true, rejectsSamplingParameters: true,
                     supportsXhighEffort: true, rejectsThinkingDisabledAboveHighEffort: true,
                     rejectsThinkingDisabled: true, rejectsBudgetThinking: true,
                     rejectsForcedToolUse: true)
    }
    if modelId.contains("claude-haiku-5-5") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true,
                     supportsAdaptiveThinking: true, rejectsSamplingParameters: true,
                     supportsXhighEffort: true, rejectsThinkingDisabledAboveHighEffort: true,
                     rejectsBudgetThinking: true)
    }
    if modelId.contains("claude-opus-5") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true,
                     supportsAdaptiveThinking: true, rejectsSamplingParameters: true,
                     supportsXhighEffort: true, rejectsThinkingDisabledAboveHighEffort: true)
    }
    if modelId.contains("claude-fable-5-1") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true,
                     supportsAdaptiveThinking: true, rejectsSamplingParameters: true,
                     supportsXhighEffort: true, rejectsThinkingDisabled: true,
                     rejectsBudgetThinking: true, rejectsForcedToolUse: true)
    }
    if modelId.contains("claude-fable-5") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true,
                     supportsAdaptiveThinking: true, rejectsSamplingParameters: true,
                     supportsXhighEffort: true, rejectsThinkingDisabled: true,
                     rejectsBudgetThinking: true)
    }
    if modelId.contains("claude-opus-4-8") || modelId.contains("claude-opus-4-7")
        || modelId.contains("claude-sonnet-5") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true,
                     supportsAdaptiveThinking: true, rejectsSamplingParameters: true,
                     supportsXhighEffort: true)
    }
    if modelId.contains("claude-sonnet-4-6") || modelId.contains("claude-opus-4-6") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true, supportsAdaptiveThinking: true)
    }
    if modelId.contains("claude-sonnet-4-5") || modelId.contains("claude-opus-4-5")
        || modelId.contains("claude-haiku-4-5") {
        return .init(maxOutputTokens: 64000, supportsStructuredOutput: true)
    }
    if modelId.contains("claude-opus-4-1") {
        return .init(maxOutputTokens: 32000, supportsStructuredOutput: true)
    }
    if modelId.range(of: "claude-sonnet-4(?:-|@)", options: .regularExpression) != nil {
        return .init(maxOutputTokens: 64000)
    }
    if modelId.range(of: "claude-opus-4(?:-|@)", options: .regularExpression) != nil {
        return .init(maxOutputTokens: 32000)
    }
    if modelId.contains("claude-3-haiku") {
        return .init()
    }
    if modelId.range(of: "claude-(?:instant(?:-|$)|v?2(?=$|[-.:])|3(?=$|[-.]))", options: .regularExpression) != nil {
        return .init(isKnownModel: false)
    }
    if modelId.contains("claude-") {
        return .init(maxOutputTokens: 128000, supportsStructuredOutput: true,
                     supportsAdaptiveThinking: true, rejectsSamplingParameters: true,
                     supportsXhighEffort: true, rejectsThinkingDisabledAboveHighEffort: true,
                     isKnownModel: false)
    }
    return .init(isKnownModel: false)
}
