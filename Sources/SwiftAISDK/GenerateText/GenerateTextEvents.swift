import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Type-erased view of an output specification, as carried by lifecycle events.

 Port of the `Output` interface used as `output` in
 `@ai-sdk/ai/src/generate-text/generate-text-events.ts`.
 */
public protocol OutputSpecification: Sendable {
    /// Name of the output kind (`text`, `object`, `array`, `choice`, `json`).
    var name: String { get }

    /// Response format requested from the model.
    func responseFormat() async throws -> LanguageModelV4ResponseFormat?
}

/**
 Event passed to `onStart` when a `generateText` / `streamText` operation begins.

 Port of `GenerateTextStartEvent` from `@ai-sdk/ai/src/generate-text/generate-text-events.ts`.
 Call options are reachable as members (`event.temperature`).
 */
@dynamicMemberLookup
public struct GenerateTextStartEvent: Sendable {
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let instructions: Instructions?
    public let messages: [ModelMessage]
    public let tools: ToolSet?
    public let toolChoice: ToolChoice?
    public let activeTools: [String]?
    public let toolOrder: [String]?
    public let callOptions: LanguageModelCallOptions
    public let maxRetries: Int
    public let timeout: TimeoutConfiguration?
    public let headers: [String: String]?
    public let providerOptions: ProviderOptions?
    public let output: (any OutputSpecification)?
    public let toolsContext: ToolsContext
    public let runtimeContext: Context

    public init(
        callId: String,
        operationId: String,
        provider: String,
        modelId: String,
        instructions: Instructions?,
        messages: [ModelMessage],
        tools: ToolSet?,
        toolChoice: ToolChoice?,
        activeTools: [String]?,
        toolOrder: [String]?,
        callOptions: LanguageModelCallOptions,
        maxRetries: Int,
        timeout: TimeoutConfiguration?,
        headers: [String: String]?,
        providerOptions: ProviderOptions?,
        output: (any OutputSpecification)?,
        toolsContext: ToolsContext,
        runtimeContext: Context
    ) {
        self.callId = callId
        self.operationId = operationId
        self.provider = provider
        self.modelId = modelId
        self.instructions = instructions
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.activeTools = activeTools
        self.toolOrder = toolOrder
        self.callOptions = callOptions
        self.maxRetries = maxRetries
        self.timeout = timeout
        self.headers = headers
        self.providerOptions = providerOptions
        self.output = output
        self.toolsContext = toolsContext
        self.runtimeContext = runtimeContext
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<LanguageModelCallOptions, T>) -> T {
        callOptions[keyPath: keyPath]
    }

    func with(runtimeContext: Context, toolsContext: ToolsContext) -> GenerateTextStartEvent {
        GenerateTextStartEvent(
            callId: callId, operationId: operationId, provider: provider, modelId: modelId,
            instructions: instructions, messages: messages, tools: tools, toolChoice: toolChoice,
            activeTools: activeTools, toolOrder: toolOrder, callOptions: callOptions,
            maxRetries: maxRetries, timeout: timeout, headers: headers,
            providerOptions: providerOptions, output: output,
            toolsContext: toolsContext, runtimeContext: runtimeContext
        )
    }
}

/**
 Event passed to `onStepStart` before the provider is called for a step.

 Port of `GenerateTextStepStartEvent` from `@ai-sdk/ai/src/generate-text/generate-text-events.ts`,
 including the prepared prompt, tools and tool choice that upstream attaches to the event.
 */
public struct GenerateTextStepStartEvent: Sendable {
    public let callId: String
    public let provider: String
    public let modelId: String
    public let stepNumber: Int
    public let instructions: Instructions?
    public let messages: [ModelMessage]
    public let tools: ToolSet?
    public let toolChoice: ToolChoice?
    public let activeTools: [String]?
    public let toolOrder: [String]?
    public let steps: [StepResult]
    public let providerOptions: ProviderOptions?
    public let output: (any OutputSpecification)?
    public let runtimeContext: Context
    public let toolsContext: ToolsContext
    /// The prompt sent to the provider.
    public let promptMessages: LanguageModelV4Prompt
    /// The tools sent to the provider.
    public let stepTools: [LanguageModelV4Tool]?
    /// The tool choice sent to the provider.
    public let stepToolChoice: LanguageModelV4ToolChoice

    public init(
        callId: String,
        provider: String,
        modelId: String,
        stepNumber: Int,
        instructions: Instructions?,
        messages: [ModelMessage],
        tools: ToolSet?,
        toolChoice: ToolChoice?,
        activeTools: [String]?,
        toolOrder: [String]?,
        steps: [StepResult],
        providerOptions: ProviderOptions?,
        output: (any OutputSpecification)?,
        runtimeContext: Context,
        toolsContext: ToolsContext,
        promptMessages: LanguageModelV4Prompt,
        stepTools: [LanguageModelV4Tool]?,
        stepToolChoice: LanguageModelV4ToolChoice
    ) {
        self.callId = callId
        self.provider = provider
        self.modelId = modelId
        self.stepNumber = stepNumber
        self.instructions = instructions
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.activeTools = activeTools
        self.toolOrder = toolOrder
        self.steps = steps
        self.providerOptions = providerOptions
        self.output = output
        self.runtimeContext = runtimeContext
        self.toolsContext = toolsContext
        self.promptMessages = promptMessages
        self.stepTools = stepTools
        self.stepToolChoice = stepToolChoice
    }

    func with(runtimeContext: Context, toolsContext: ToolsContext, steps: [StepResult]) -> GenerateTextStepStartEvent {
        GenerateTextStepStartEvent(
            callId: callId, provider: provider, modelId: modelId, stepNumber: stepNumber,
            instructions: instructions, messages: messages, tools: tools, toolChoice: toolChoice,
            activeTools: activeTools, toolOrder: toolOrder, steps: steps,
            providerOptions: providerOptions, output: output,
            runtimeContext: runtimeContext, toolsContext: toolsContext,
            promptMessages: promptMessages, stepTools: stepTools, stepToolChoice: stepToolChoice
        )
    }
}

/// Event passed to `onStepEnd`: the result of the step.
public typealias GenerateTextStepEndEvent = StepResult

/**
 Event passed to `onEnd` when all steps are finished.

 Port of `GenerateTextEndEvent` from `@ai-sdk/ai/src/generate-text/generate-text-events.ts`.
 */
public struct GenerateTextEndEvent: Sendable {
    public let callId: String
    public let stepNumber: Int
    public let model: ModelInfo
    public let toolsContext: ToolsContext
    public let runtimeContext: Context
    /// Content of all steps.
    public let content: [ContentPart]
    /// Text of the final step.
    public let text: String
    /// Reasoning of the final step.
    public let reasoning: [ReasoningOutput]
    public let reasoningText: String?
    /// Files of all steps.
    public let files: [GeneratedFile]
    /// Sources of all steps.
    public let sources: [Source]
    /// Tool calls of all steps.
    public let toolCalls: [TypedToolCall]
    public let staticToolCalls: [StaticToolCall]
    public let dynamicToolCalls: [DynamicToolCall]
    /// Tool results of all steps.
    public let toolResults: [TypedToolResult]
    public let staticToolResults: [StaticToolResult]
    public let dynamicToolResults: [DynamicToolResult]
    public let finishReason: FinishReason
    public let rawFinishReason: String?
    /// Total usage of all steps.
    public let usage: LanguageModelUsage
    public let totalUsage: LanguageModelUsage
    /// Warnings of all steps.
    public let warnings: [CallWarning]?
    public let request: LanguageModelRequestMetadata
    public let response: StepResultResponse
    public let providerMetadata: ProviderMetadata?
    public let responseMessages: [ResponseMessage]
    public let steps: [StepResult]
    public let finalStep: StepResult

    /// Builds the end event of a finished generation.
    public init(
        callId: String,
        steps: [StepResult],
        initialResponseMessages: [ResponseMessage],
        totalUsage: LanguageModelUsage
    ) {
        let lastStep = steps[steps.count - 1]
        self.callId = callId
        self.stepNumber = lastStep.stepNumber
        self.model = lastStep.model
        self.toolsContext = lastStep.toolsContext
        self.runtimeContext = lastStep.runtimeContext
        self.content = steps.flatMap(\.content)
        self.text = lastStep.text
        self.reasoning = lastStep.reasoning
        self.reasoningText = lastStep.reasoningText
        self.files = steps.flatMap(\.files)
        self.sources = steps.flatMap(\.sources)
        self.toolCalls = steps.flatMap(\.toolCalls)
        self.staticToolCalls = steps.flatMap(\.staticToolCalls)
        self.dynamicToolCalls = steps.flatMap(\.dynamicToolCalls)
        self.toolResults = steps.flatMap(\.toolResults)
        self.staticToolResults = steps.flatMap(\.staticToolResults)
        self.dynamicToolResults = steps.flatMap(\.dynamicToolResults)
        self.finishReason = lastStep.finishReason
        self.rawFinishReason = lastStep.rawFinishReason
        self.usage = totalUsage
        self.totalUsage = totalUsage
        self.warnings = steps.flatMap { $0.warnings ?? [] }
        self.request = lastStep.request
        self.response = lastStep.response
        self.providerMetadata = lastStep.providerMetadata
        self.responseMessages = initialResponseMessages + steps.flatMap(\.response.messages)
        self.steps = steps
        self.finalStep = lastStep
    }

    private init(copy event: GenerateTextEndEvent, runtimeContext: Context, toolsContext: ToolsContext, steps: [StepResult]) {
        self.callId = event.callId
        self.stepNumber = event.stepNumber
        self.model = event.model
        self.toolsContext = toolsContext
        self.runtimeContext = runtimeContext
        self.content = event.content
        self.text = event.text
        self.reasoning = event.reasoning
        self.reasoningText = event.reasoningText
        self.files = event.files
        self.sources = event.sources
        self.toolCalls = event.toolCalls
        self.staticToolCalls = event.staticToolCalls
        self.dynamicToolCalls = event.dynamicToolCalls
        self.toolResults = event.toolResults
        self.staticToolResults = event.staticToolResults
        self.dynamicToolResults = event.dynamicToolResults
        self.finishReason = event.finishReason
        self.rawFinishReason = event.rawFinishReason
        self.usage = event.usage
        self.totalUsage = event.totalUsage
        self.warnings = event.warnings
        self.request = event.request
        self.response = event.response
        self.providerMetadata = event.providerMetadata
        self.responseMessages = event.responseMessages
        self.steps = steps
        self.finalStep = steps[steps.count - 1]
    }

    func with(runtimeContext: Context, toolsContext: ToolsContext, steps: [StepResult]) -> GenerateTextEndEvent {
        GenerateTextEndEvent(copy: self, runtimeContext: runtimeContext, toolsContext: toolsContext, steps: steps)
    }
}

/**
 Event passed to `onAbort` when a streaming generation is aborted.

 Port of `GenerateTextAbortEvent` from `@ai-sdk/ai/src/generate-text/generate-text-events.ts`.
 */
public struct GenerateTextAbortEvent: Sendable {
    public let callId: String
    /// Steps completed before the abort.
    public let steps: [StepResult]
    /// The abort reason, when known.
    public let reason: (any Error)?

    public init(callId: String, steps: [StepResult], reason: (any Error)? = nil) {
        self.callId = callId
        self.steps = steps
        self.reason = reason
    }
}

public typealias GenerateTextOnStartCallback = @Sendable (GenerateTextStartEvent) async throws -> Void
public typealias GenerateTextOnStepStartCallback = @Sendable (GenerateTextStepStartEvent) async throws -> Void
public typealias GenerateTextOnStepEndCallback = @Sendable (StepResult) async throws -> Void
public typealias GenerateTextOnEndCallback = @Sendable (GenerateTextEndEvent) async throws -> Void
public typealias GenerateTextOnAbortCallback = @Sendable (GenerateTextAbortEvent) async throws -> Void
