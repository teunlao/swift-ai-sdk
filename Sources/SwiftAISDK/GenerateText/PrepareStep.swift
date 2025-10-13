/**
 Step preparation utilities for multi-step tool orchestration.

 Port of `@ai-sdk/ai/src/generate-text/prepare-step.ts`.
 */
import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Options for preparing a generation step.

 Port of `@ai-sdk/ai/src/generate-text/prepare-step.ts`.
 */
public struct PrepareStepOptions: Sendable {
    /// Steps that have been executed so far.
    public let steps: [StepResult]

    /// Number of the step that is being executed (1-based).
    public let stepNumber: Int

    /// Model that will be used for the next step.
    public let model: LanguageModel

    /// Messages that were exchanged up to this point.
    public let messages: [ModelMessage]

    public init(
        steps: [StepResult],
        stepNumber: Int,
        model: LanguageModel,
        messages: [ModelMessage]
    ) {
        self.steps = steps
        self.stepNumber = stepNumber
        self.model = model
        self.messages = messages
    }
}

/**
 Result of preparing a generation step.

 Port of `@ai-sdk/ai/src/generate-text/prepare-step.ts`.
 */
public struct PrepareStepResult: Sendable {
    public var model: LanguageModel?
    public var toolChoice: ToolChoice?
    public var activeTools: [String]?
    public var system: String?
    public var messages: [ModelMessage]?

    public init(
        model: LanguageModel? = nil,
        toolChoice: ToolChoice? = nil,
        activeTools: [String]? = nil,
        system: String? = nil,
        messages: [ModelMessage]? = nil
    ) {
        self.model = model
        self.toolChoice = toolChoice
        self.activeTools = activeTools
        self.system = system
        self.messages = messages
    }
}

/**
 Function type that allows customizing settings for each generation step.

 Port of `@ai-sdk/ai/src/generate-text/prepare-step.ts`.
 */
public typealias PrepareStepFunction = @Sendable (PrepareStepOptions) async throws -> PrepareStepResult?
