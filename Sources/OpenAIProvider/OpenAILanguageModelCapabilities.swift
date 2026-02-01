import Foundation

struct OpenAILanguageModelCapabilities: Sendable, Equatable {
    let isReasoningModel: Bool
    let systemMessageMode: OpenAIResponsesSystemMessageMode
    let supportsFlexProcessing: Bool
    let supportsPriorityProcessing: Bool
    let supportsNonReasoningParameters: Bool
}

/// Port of `packages/openai/src/openai-language-model-capabilities.ts`.
func getOpenAILanguageModelCapabilities(for modelId: String) -> OpenAILanguageModelCapabilities {
    let supportsFlexProcessing =
        modelId.hasPrefix("o3")
        || modelId.hasPrefix("o4-mini")
        || (modelId.hasPrefix("gpt-5") && !modelId.hasPrefix("gpt-5-chat"))

    let supportsPriorityProcessing =
        modelId.hasPrefix("gpt-4")
        || modelId.hasPrefix("gpt-5-mini")
        || (modelId.hasPrefix("gpt-5") && !modelId.hasPrefix("gpt-5-nano") && !modelId.hasPrefix("gpt-5-chat"))
        || modelId.hasPrefix("o3")
        || modelId.hasPrefix("o4-mini")

    // Use allowlist approach: only known reasoning models should use 'developer' role.
    // This prevents issues with fine-tuned models, third-party models, and custom models.
    let isReasoningModel =
        modelId.hasPrefix("o1")
        || modelId.hasPrefix("o3")
        || modelId.hasPrefix("o4-mini")
        || modelId.hasPrefix("codex-mini")
        || modelId.hasPrefix("computer-use-preview")
        || (modelId.hasPrefix("gpt-5") && !modelId.hasPrefix("gpt-5-chat"))

    // https://platform.openai.com/docs/guides/latest-model#gpt-5-1-parameter-compatibility
    // GPT-5.1 and GPT-5.2 support temperature/topP/logprobs when reasoningEffort is none.
    let supportsNonReasoningParameters = modelId.hasPrefix("gpt-5.1") || modelId.hasPrefix("gpt-5.2")

    let systemMessageMode: OpenAIResponsesSystemMessageMode = isReasoningModel ? .developer : .system

    return OpenAILanguageModelCapabilities(
        isReasoningModel: isReasoningModel,
        systemMessageMode: systemMessageMode,
        supportsFlexProcessing: supportsFlexProcessing,
        supportsPriorityProcessing: supportsPriorityProcessing,
        supportsNonReasoningParameters: supportsNonReasoningParameters
    )
}

