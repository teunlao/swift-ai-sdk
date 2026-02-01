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
    let capabilities = getOpenAILanguageModelCapabilities(for: modelId.rawValue)

    let defaults = OpenAIResponsesModelConfig(
        isReasoningModel: capabilities.isReasoningModel,
        systemMessageMode: capabilities.systemMessageMode,
        requiredAutoTruncation: false,
        supportsFlexProcessing: capabilities.supportsFlexProcessing,
        supportsPriorityProcessing: capabilities.supportsPriorityProcessing,
        supportsNonReasoningParameters: capabilities.supportsNonReasoningParameters
    )

    return defaults
}
