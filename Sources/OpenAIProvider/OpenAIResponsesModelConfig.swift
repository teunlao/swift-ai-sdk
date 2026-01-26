import Foundation

public enum OpenAIResponsesSystemMessageMode: Sendable {
    case system
    case developer
    case remove
}

struct OpenAIResponsesModelConfig: Sendable {
    let isReasoningModel: Bool
    let systemMessageMode: OpenAIResponsesSystemMessageMode
    let requiredAutoTruncation: Bool
    let supportsFlexProcessing: Bool
    let supportsPriorityProcessing: Bool
    let supportsNonReasoningParameters: Bool
}

func getOpenAIResponsesModelConfig(for modelId: OpenAIResponsesModelId) -> OpenAIResponsesModelConfig {
    let id = modelId.rawValue

    let supportsFlexProcessing = id.hasPrefix("o3") || id.hasPrefix("o4-mini") || (id.hasPrefix("gpt-5") && !id.hasPrefix("gpt-5-chat"))
    let supportsPriorityProcessing = id.hasPrefix("gpt-4")
        || id.hasPrefix("gpt-5-mini")
        || (id.hasPrefix("gpt-5") && !id.hasPrefix("gpt-5-nano") && !id.hasPrefix("gpt-5-chat"))
        || id.hasPrefix("o3")
        || id.hasPrefix("o4-mini")

    // https://platform.openai.com/docs/guides/latest-model#gpt-5-1-parameter-compatibility
    // GPT-5.1 and GPT-5.2 support temperature/topP/logprobs when reasoningEffort is none.
    let supportsNonReasoningParameters = id.hasPrefix("gpt-5.1") || id.hasPrefix("gpt-5.2")

    // Use allowlist approach: only known reasoning models should use 'developer' role.
    // This prevents issues with fine-tuned models, third-party models, and custom models.
    let isReasoningModel = id.hasPrefix("o1")
        || id.hasPrefix("o3")
        || id.hasPrefix("o4-mini")
        || id.hasPrefix("codex-mini")
        || id.hasPrefix("computer-use-preview")
        || (id.hasPrefix("gpt-5") && !id.hasPrefix("gpt-5-chat"))

    let defaults = OpenAIResponsesModelConfig(
        isReasoningModel: isReasoningModel,
        systemMessageMode: isReasoningModel ? .developer : .system,
        requiredAutoTruncation: false,
        supportsFlexProcessing: supportsFlexProcessing,
        supportsPriorityProcessing: supportsPriorityProcessing,
        supportsNonReasoningParameters: supportsNonReasoningParameters
    )

    return defaults
}
