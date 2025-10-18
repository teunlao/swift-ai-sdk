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
}

func getOpenAIResponsesModelConfig(for modelId: OpenAIResponsesModelId) -> OpenAIResponsesModelConfig {
    let id = modelId.rawValue

    let supportsFlexProcessing = id.hasPrefix("o3") || id.hasPrefix("o4-mini") || (id.hasPrefix("gpt-5") && !id.hasPrefix("gpt-5-chat"))
    let supportsPriorityProcessing = id.hasPrefix("gpt-4")
        || id.hasPrefix("gpt-5-mini")
        || (id.hasPrefix("gpt-5") && !id.hasPrefix("gpt-5-nano") && !id.hasPrefix("gpt-5-chat"))
        || id.hasPrefix("o3")
        || id.hasPrefix("o4-mini")

    let defaults = OpenAIResponsesModelConfig(
        isReasoningModel: false,
        systemMessageMode: .system,
        requiredAutoTruncation: false,
        supportsFlexProcessing: supportsFlexProcessing,
        supportsPriorityProcessing: supportsPriorityProcessing
    )

    if id.hasPrefix("gpt-5-chat") {
        return defaults
    }

    if id.hasPrefix("o") || id.hasPrefix("gpt-5") || id.hasPrefix("codex-") || id.hasPrefix("computer-use") {
        if id.hasPrefix("o1-mini") || id.hasPrefix("o1-preview") {
            return OpenAIResponsesModelConfig(
                isReasoningModel: true,
                systemMessageMode: .remove,
                requiredAutoTruncation: defaults.requiredAutoTruncation,
                supportsFlexProcessing: supportsFlexProcessing,
                supportsPriorityProcessing: supportsPriorityProcessing
            )
        }

        return OpenAIResponsesModelConfig(
            isReasoningModel: true,
            systemMessageMode: .developer,
            requiredAutoTruncation: defaults.requiredAutoTruncation,
            supportsFlexProcessing: supportsFlexProcessing,
            supportsPriorityProcessing: supportsPriorityProcessing
        )
    }

    return defaults
}
