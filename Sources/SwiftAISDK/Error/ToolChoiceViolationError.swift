import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A tool choice that requires the model to call a tool.

 Port of the `EnforcedToolChoice` subset of `LanguageModelV4ToolChoice`
 (`required` or a specific `tool`).
 */
public enum EnforcedToolChoice: Sendable, Equatable {
    case required
    case tool(toolName: String)

    public var languageModelToolChoice: LanguageModelV4ToolChoice {
        switch self {
        case .required:
            return .required
        case .tool(let toolName):
            return .tool(toolName: toolName)
        }
    }
}

/**
 Thrown when a model response does not satisfy an enforced tool choice.

 Port of `@ai-sdk/ai/src/error/tool-choice-violation-error.ts`.
 */
public struct ToolChoiceViolationError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_ToolChoiceViolationError"

    public let name = "AI_ToolChoiceViolationError"
    public let message: String
    public let cause: (any Error)? = nil

    /// The tool choice that the model response did not satisfy.
    public let toolChoice: EnforcedToolChoice

    /// Reason why the model finished generating the response.
    public let finishReason: FinishReason

    /// The provider that returned the response.
    public let provider: String

    /// The model that returned the response.
    public let modelId: String

    /// The normalized content returned by the model.
    public let content: [LanguageModelV4Content]

    public init(
        toolChoice: EnforcedToolChoice,
        finishReason: FinishReason,
        provider: String,
        modelId: String,
        content: [LanguageModelV4Content],
        message: String? = nil
    ) {
        self.toolChoice = toolChoice
        self.finishReason = finishReason
        self.provider = provider
        self.modelId = modelId
        self.content = content
        switch toolChoice {
        case .required:
            self.message = message
                ?? "Model response did not contain a tool call even though tool choice was required."
        case .tool(let toolName):
            self.message = message
                ?? "Model response did not contain a call to the required tool '\(toolName)'."
        }
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
