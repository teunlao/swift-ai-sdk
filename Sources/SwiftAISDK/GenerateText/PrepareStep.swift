import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Options passed to `prepareStep`.

 Port of `@ai-sdk/ai/src/generate-text/prepare-step.ts`.
 */
public struct PrepareStepOptions: Sendable {
    /// Steps executed so far.
    public let steps: [StepResult]

    /// Number of the step that is being prepared.
    public let stepNumber: Int

    /// The model of the call.
    public let model: LanguageModel

    /// Instructions the step would use: the previous step's instructions.
    public let instructions: Instructions?

    /// Instructions of the call.
    public let initialInstructions: Instructions?

    /// Messages the step would send: the previous step's messages and its response.
    public let messages: [ModelMessage]

    /// Messages of the call.
    public let initialMessages: [ModelMessage]

    /// Response messages accumulated so far.
    public let responseMessages: [ResponseMessage]

    /// Tool contexts of the call.
    public let toolsContext: ToolsContext

    /// Runtime context of the call.
    public let runtimeContext: Context

    public init(
        steps: [StepResult],
        stepNumber: Int,
        model: LanguageModel,
        instructions: Instructions? = nil,
        initialInstructions: Instructions? = nil,
        messages: [ModelMessage],
        initialMessages: [ModelMessage] = [],
        responseMessages: [ResponseMessage] = [],
        toolsContext: ToolsContext = [:],
        runtimeContext: Context = [:]
    ) {
        self.steps = steps
        self.stepNumber = stepNumber
        self.model = model
        self.instructions = instructions
        self.initialInstructions = initialInstructions
        self.messages = messages
        self.initialMessages = initialMessages
        self.responseMessages = responseMessages
        self.toolsContext = toolsContext
        self.runtimeContext = runtimeContext
    }
}

/**
 Settings for one step; unset fields keep the call's settings.

 Port of `PrepareStepResult` from `@ai-sdk/ai/src/generate-text/prepare-step.ts`,
 including the per-step model call setting overrides.
 */
public struct PrepareStepResult: Sendable {
    public var model: LanguageModel?
    public var toolChoice: ToolChoice?
    public var activeTools: [String]?
    public var toolOrder: [String]?
    public var instructions: Instructions?
    public var messages: [ModelMessage]?
    public var toolsContext: ToolsContext?
    public var runtimeContext: Context?
    public var providerOptions: ProviderOptions?
    /// Model call settings for this step.
    public var callOptions: LanguageModelCallOptions

    public init(
        model: LanguageModel? = nil,
        toolChoice: ToolChoice? = nil,
        activeTools: [String]? = nil,
        toolOrder: [String]? = nil,
        instructions: Instructions? = nil,
        messages: [ModelMessage]? = nil,
        toolsContext: ToolsContext? = nil,
        runtimeContext: Context? = nil,
        providerOptions: ProviderOptions? = nil,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil,
        reasoning: LanguageModelV4ReasoningEffort? = nil
    ) {
        self.model = model
        self.toolChoice = toolChoice
        self.activeTools = activeTools
        self.toolOrder = toolOrder
        self.instructions = instructions
        self.messages = messages
        self.toolsContext = toolsContext
        self.runtimeContext = runtimeContext
        self.providerOptions = providerOptions
        self.callOptions = LanguageModelCallOptions(
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            stopSequences: stopSequences,
            seed: seed,
            reasoning: reasoning
        )
    }
}

/// Customizes the settings of each step.
public typealias PrepareStepFunction = @Sendable (PrepareStepOptions) async throws -> PrepareStepResult?
