import Foundation
import AISDKProvider
import AISDKProviderUtils

/// What agent step results retain: the union of `GenerateTextInclude` and `StreamTextInclude`.
public struct ToolLoopAgentInclude: Sendable {
    public var requestBody: Bool?
    public var requestMessages: Bool?
    public var responseBody: Bool?
    public var rawChunks: Bool?

    public init(requestBody: Bool? = nil, requestMessages: Bool? = nil, responseBody: Bool? = nil, rawChunks: Bool? = nil) {
        self.requestBody = requestBody
        self.requestMessages = requestMessages
        self.responseBody = responseBody
        self.rawChunks = rawChunks
    }

    var generateTextInclude: GenerateTextInclude {
        GenerateTextInclude(requestBody: requestBody, requestMessages: requestMessages, responseBody: responseBody)
    }

    var streamTextInclude: StreamTextInclude {
        StreamTextInclude(requestBody: requestBody, requestMessages: requestMessages, rawChunks: rawChunks)
    }
}

/// Internal knobs for tests: id generators.
public struct ToolLoopAgentInternalOptions: Sendable {
    public var generateId: IDGenerator?
    public var generateCallId: IDGenerator?

    public init(generateId: IDGenerator? = nil, generateCallId: IDGenerator? = nil) {
        self.generateId = generateId
        self.generateCallId = generateCallId
    }
}

/**
 The settings of one agent call, as `prepareCall` receives and returns them.

 Port of the `prepareCall` parameter and result of `ToolLoopAgentSettings` in
 `@ai-sdk/ai/src/agent/tool-loop-agent-settings.ts`. Upstream picks these
 fields out of the settings; Swift names the shape. `options`, `prompt` and
 `messages` come from the call.
 */
public struct ToolLoopAgentCall<CallOptions: Sendable>: Sendable {
    public var options: CallOptions?
    public var prompt: PromptContent?
    public var messages: [ModelMessage]?
    public var instructions: Instructions?
    public var allowSystemInMessages: Bool?
    public var model: LanguageModel
    public var tools: ToolSet?
    public var toolChoice: ToolChoice?
    public var stopWhen: [StopCondition]
    public var telemetry: TelemetryOptions?
    public var activeTools: [String]?
    public var toolOrder: [String]?
    public var toolCallConcurrency: Int?
    public var toolApproval: ToolApprovalConfiguration?
    public var prepareStep: PrepareStepFunction?
    public var repairToolCall: ToolCallRepairFunction?
    public var refineToolInput: ToolInputRefinement?
    public var providerOptions: ProviderOptions?
    public var download: DownloadFunction?
    public var include: ToolLoopAgentInclude?
    public var runtimeContext: Context?
    public var toolsContext: ToolsContext
    public var internalOptions: ToolLoopAgentInternalOptions?
    /// Model call settings, retries, timeout and headers. The call's abort signal is set separately.
    public var callSettings: CallSettings
}

/// Prepares the settings of an agent call, e.g. from call options.
public typealias ToolLoopAgentPrepareCallFunction<CallOptions: Sendable> = @Sendable (
    ToolLoopAgentCall<CallOptions>
) async throws -> ToolLoopAgentCall<CallOptions>

/**
 Configuration of a `ToolLoopAgent`.

 Port of `@ai-sdk/ai/src/agent/tool-loop-agent-settings.ts`.
 */
public struct ToolLoopAgentSettings<CallOptions: Sendable, OutputValue: Sendable, PartialOutput: Sendable>: Sendable {
    public var id: String?
    /// The instructions for the agent.
    public var instructions: Instructions?
    /// Whether `prompt` and `messages` may contain system messages. Default: `false`.
    public var allowSystemInMessages: Bool?
    public var model: LanguageModel
    public var tools: ToolSet?
    public var toolChoice: ToolChoice?
    /// Stop conditions for the tool loop. Default: 20 steps.
    public var stopWhen: [StopCondition]?
    public var telemetry: TelemetryOptions?
    public var activeTools: [String]?
    public var toolOrder: [String]?
    public var toolCallConcurrency: Int?
    public var output: Output.Specification<OutputValue, PartialOutput>
    /// Runtime context. Update it in `prepareStep`, never by mutation.
    public var runtimeContext: Context?
    public var toolsContext: ToolsContext
    /// Takes precedence over the tools' own approval settings.
    public var toolApproval: ToolApprovalConfiguration?
    /// Signs approval requests at issuance and verifies them before approved calls execute.
    public var toolApprovalSecret: ToolApprovalSecret?
    public var prepareStep: PrepareStepFunction?
    public var repairToolCall: ToolCallRepairFunction?
    public var refineToolInput: ToolInputRefinement?
    public var onStart: GenerateTextOnStartCallback?
    public var onStepStart: GenerateTextOnStepStartCallback?
    public var onLanguageModelCallStart: OnLanguageModelCallStartCallback?
    public var onLanguageModelCallEnd: OnLanguageModelCallEndCallback?
    public var onToolExecutionStart: OnToolExecutionStartCallback?
    public var onToolExecutionEnd: OnToolExecutionEndCallback?
    public var onStepEnd: GenerateTextOnStepEndCallback?
    public var onEnd: GenerateTextOnEndCallback?
    public var providerOptions: ProviderOptions?
    public var download: DownloadFunction?
    public var include: ToolLoopAgentInclude?
    public var internalOptions: ToolLoopAgentInternalOptions?
    /// Validates the call options.
    public var callOptionsSchema: FlexibleSchema<CallOptions>?
    /// Prepares the settings of each call.
    public var prepareCall: ToolLoopAgentPrepareCallFunction<CallOptions>?
    /// Model call settings, retries, timeout and headers. The abort signal is set per call.
    public var callSettings: CallSettings

    public init(
        id: String? = nil,
        instructions: Instructions? = nil,
        allowSystemInMessages: Bool? = nil,
        model: LanguageModel,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        stopWhen: [StopCondition]? = nil,
        telemetry: TelemetryOptions? = nil,
        activeTools: [String]? = nil,
        toolOrder: [String]? = nil,
        toolCallConcurrency: Int? = nil,
        output: Output.Specification<OutputValue, PartialOutput>,
        runtimeContext: Context? = nil,
        toolsContext: ToolsContext = [:],
        toolApproval: ToolApprovalConfiguration? = nil,
        toolApprovalSecret: ToolApprovalSecret? = nil,
        prepareStep: PrepareStepFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        refineToolInput: ToolInputRefinement? = nil,
        onStart: GenerateTextOnStartCallback? = nil,
        onStepStart: GenerateTextOnStepStartCallback? = nil,
        onLanguageModelCallStart: OnLanguageModelCallStartCallback? = nil,
        onLanguageModelCallEnd: OnLanguageModelCallEndCallback? = nil,
        onToolExecutionStart: OnToolExecutionStartCallback? = nil,
        onToolExecutionEnd: OnToolExecutionEndCallback? = nil,
        onStepEnd: GenerateTextOnStepEndCallback? = nil,
        onEnd: GenerateTextOnEndCallback? = nil,
        providerOptions: ProviderOptions? = nil,
        download: DownloadFunction? = nil,
        include: ToolLoopAgentInclude? = nil,
        internalOptions: ToolLoopAgentInternalOptions? = nil,
        callOptionsSchema: FlexibleSchema<CallOptions>? = nil,
        prepareCall: ToolLoopAgentPrepareCallFunction<CallOptions>? = nil,
        callSettings: CallSettings = CallSettings()
    ) {
        self.id = id
        self.instructions = instructions
        self.allowSystemInMessages = allowSystemInMessages
        self.model = model
        self.tools = tools
        self.toolChoice = toolChoice
        self.stopWhen = stopWhen
        self.telemetry = telemetry
        self.activeTools = activeTools
        self.toolOrder = toolOrder
        self.toolCallConcurrency = toolCallConcurrency
        self.output = output
        self.runtimeContext = runtimeContext
        self.toolsContext = toolsContext
        self.toolApproval = toolApproval
        self.toolApprovalSecret = toolApprovalSecret
        self.prepareStep = prepareStep
        self.repairToolCall = repairToolCall
        self.refineToolInput = refineToolInput
        self.onStart = onStart
        self.onStepStart = onStepStart
        self.onLanguageModelCallStart = onLanguageModelCallStart
        self.onLanguageModelCallEnd = onLanguageModelCallEnd
        self.onToolExecutionStart = onToolExecutionStart
        self.onToolExecutionEnd = onToolExecutionEnd
        self.onStepEnd = onStepEnd
        self.onEnd = onEnd
        self.providerOptions = providerOptions
        self.download = download
        self.include = include
        self.internalOptions = internalOptions
        self.callOptionsSchema = callOptionsSchema
        self.prepareCall = prepareCall
        self.callSettings = callSettings
    }
}

public extension ToolLoopAgentSettings where OutputValue == String, PartialOutput == String {
    /// Settings of an agent with text output.
    init(
        id: String? = nil,
        instructions: Instructions? = nil,
        allowSystemInMessages: Bool? = nil,
        model: LanguageModel,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        stopWhen: [StopCondition]? = nil,
        telemetry: TelemetryOptions? = nil,
        activeTools: [String]? = nil,
        toolOrder: [String]? = nil,
        toolCallConcurrency: Int? = nil,
        runtimeContext: Context? = nil,
        toolsContext: ToolsContext = [:],
        toolApproval: ToolApprovalConfiguration? = nil,
        toolApprovalSecret: ToolApprovalSecret? = nil,
        prepareStep: PrepareStepFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        refineToolInput: ToolInputRefinement? = nil,
        onStart: GenerateTextOnStartCallback? = nil,
        onStepStart: GenerateTextOnStepStartCallback? = nil,
        onLanguageModelCallStart: OnLanguageModelCallStartCallback? = nil,
        onLanguageModelCallEnd: OnLanguageModelCallEndCallback? = nil,
        onToolExecutionStart: OnToolExecutionStartCallback? = nil,
        onToolExecutionEnd: OnToolExecutionEndCallback? = nil,
        onStepEnd: GenerateTextOnStepEndCallback? = nil,
        onEnd: GenerateTextOnEndCallback? = nil,
        providerOptions: ProviderOptions? = nil,
        download: DownloadFunction? = nil,
        include: ToolLoopAgentInclude? = nil,
        internalOptions: ToolLoopAgentInternalOptions? = nil,
        callOptionsSchema: FlexibleSchema<CallOptions>? = nil,
        prepareCall: ToolLoopAgentPrepareCallFunction<CallOptions>? = nil,
        callSettings: CallSettings = CallSettings()
    ) {
        self.init(
            id: id,
            instructions: instructions,
            allowSystemInMessages: allowSystemInMessages,
            model: model,
            tools: tools,
            toolChoice: toolChoice,
            stopWhen: stopWhen,
            telemetry: telemetry,
            activeTools: activeTools,
            toolOrder: toolOrder,
            toolCallConcurrency: toolCallConcurrency,
            output: Output.text(),
            runtimeContext: runtimeContext,
            toolsContext: toolsContext,
            toolApproval: toolApproval,
            toolApprovalSecret: toolApprovalSecret,
            prepareStep: prepareStep,
            repairToolCall: repairToolCall,
            refineToolInput: refineToolInput,
            onStart: onStart,
            onStepStart: onStepStart,
            onLanguageModelCallStart: onLanguageModelCallStart,
            onLanguageModelCallEnd: onLanguageModelCallEnd,
            onToolExecutionStart: onToolExecutionStart,
            onToolExecutionEnd: onToolExecutionEnd,
            onStepEnd: onStepEnd,
            onEnd: onEnd,
            providerOptions: providerOptions,
            download: download,
            include: include,
            internalOptions: internalOptions,
            callOptionsSchema: callOptionsSchema,
            prepareCall: prepareCall,
            callSettings: callSettings
        )
    }
}

