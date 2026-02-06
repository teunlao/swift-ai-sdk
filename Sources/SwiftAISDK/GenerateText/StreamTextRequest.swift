import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A request object for `streamText`, mirroring the TypeScript object-style API.

 This is a Swift-only DX convenience that allows reusing base configurations and
 avoids Swift's positional argument ordering constraints.

 It does not replace the existing `streamText(...)` overloads.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct StreamTextRequest<OutputValue: Sendable, PartialOutputValue: Sendable>: Sendable {
    public var model: LanguageModel

    public var system: String?
    public var prompt: String?
    public var messages: [ModelMessage]?

    public var tools: ToolSet?
    public var toolChoice: ToolChoice?

    public var providerOptions: ProviderOptions?
    public var activeTools: [String]?

    public var experimentalOutput: Output.Specification<OutputValue, PartialOutputValue>?
    public var telemetry: TelemetrySettings?

    public var approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)?
    public var transforms: [StreamTextTransform]

    public var download: DownloadFunction?
    public var repairToolCall: ToolCallRepairFunction?
    public var prepareStep: PrepareStepFunction?
    public var context: JSONValue?
    public var include: StreamTextInclude?

    public var includeRawChunks: Bool
    public var stopWhen: [StopCondition]

    public var onChunk: StreamTextOnChunk?
    public var onStepFinish: StreamTextOnStepFinish?
    public var onFinish: StreamTextOnFinish?
    public var onAbort: StreamTextOnAbort?
    public var onError: StreamTextOnError?

    public var internalOptions: StreamTextInternalOptions
    public var settings: CallSettings

    /**
     Creates a request for the common case (no structured output parser).

     The generic output types are fixed to `JSONValue` to keep the call site concise.
     */
    public init(
        model: LanguageModel,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        telemetry: TelemetrySettings? = nil,
        approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
        transforms: [StreamTextTransform] = [],
        download: DownloadFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        prepareStep: PrepareStepFunction? = nil,
        context: JSONValue? = nil,
        include: StreamTextInclude? = nil,
        includeRawChunks: Bool = false,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        onChunk: StreamTextOnChunk? = nil,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil,
        internalOptions: StreamTextInternalOptions = StreamTextInternalOptions(),
        settings: CallSettings = CallSettings()
    ) where OutputValue == JSONValue, PartialOutputValue == JSONValue {
        self.model = model
        self.system = system
        self.prompt = prompt
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.providerOptions = providerOptions
        self.activeTools = activeTools
        self.experimentalOutput = nil
        self.telemetry = telemetry
        self.approve = approve
        self.transforms = transforms
        self.download = download
        self.repairToolCall = repairToolCall
        self.prepareStep = prepareStep
        self.context = context
        self.include = include
        self.includeRawChunks = includeRawChunks
        self.stopWhen = stopWhen
        self.onChunk = onChunk
        self.onStepFinish = onStepFinish
        self.onFinish = onFinish
        self.onAbort = onAbort
        self.onError = onError
        self.internalOptions = internalOptions
        self.settings = settings
    }

    /**
     Creates a request with a structured output parser.

     Passing the `experimentalOutput` specification makes `OutputValue` and `PartialOutputValue` inferable.
     */
    public init(
        model: LanguageModel,
        experimentalOutput: Output.Specification<OutputValue, PartialOutputValue>,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        telemetry: TelemetrySettings? = nil,
        approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
        transforms: [StreamTextTransform] = [],
        download: DownloadFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        prepareStep: PrepareStepFunction? = nil,
        context: JSONValue? = nil,
        include: StreamTextInclude? = nil,
        includeRawChunks: Bool = false,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        onChunk: StreamTextOnChunk? = nil,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil,
        internalOptions: StreamTextInternalOptions = StreamTextInternalOptions(),
        settings: CallSettings = CallSettings()
    ) {
        self.model = model
        self.system = system
        self.prompt = prompt
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.providerOptions = providerOptions
        self.activeTools = activeTools
        self.experimentalOutput = experimentalOutput
        self.telemetry = telemetry
        self.approve = approve
        self.transforms = transforms
        self.download = download
        self.repairToolCall = repairToolCall
        self.prepareStep = prepareStep
        self.context = context
        self.include = include
        self.includeRawChunks = includeRawChunks
        self.stopWhen = stopWhen
        self.onChunk = onChunk
        self.onStepFinish = onStepFinish
        self.onFinish = onFinish
        self.onAbort = onAbort
        self.onError = onError
        self.internalOptions = internalOptions
        self.settings = settings
    }

    // MARK: - Model convenience initializers

    public init(
        model: any LanguageModelV3,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        telemetry: TelemetrySettings? = nil,
        approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
        transforms: [StreamTextTransform] = [],
        download: DownloadFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        prepareStep: PrepareStepFunction? = nil,
        context: JSONValue? = nil,
        include: StreamTextInclude? = nil,
        includeRawChunks: Bool = false,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        onChunk: StreamTextOnChunk? = nil,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil,
        internalOptions: StreamTextInternalOptions = StreamTextInternalOptions(),
        settings: CallSettings = CallSettings()
    ) where OutputValue == JSONValue, PartialOutputValue == JSONValue {
        self.init(
            model: .v3(model),
            system: system,
            prompt: prompt,
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            providerOptions: providerOptions,
            activeTools: activeTools,
            telemetry: telemetry,
            approve: approve,
            transforms: transforms,
            download: download,
            repairToolCall: repairToolCall,
            prepareStep: prepareStep,
            context: context,
            include: include,
            includeRawChunks: includeRawChunks,
            stopWhen: stopWhen,
            onChunk: onChunk,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            onAbort: onAbort,
            onError: onError,
            internalOptions: internalOptions,
            settings: settings
        )
    }

    public init(
        model: any LanguageModelV2,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        telemetry: TelemetrySettings? = nil,
        approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
        transforms: [StreamTextTransform] = [],
        download: DownloadFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        prepareStep: PrepareStepFunction? = nil,
        context: JSONValue? = nil,
        include: StreamTextInclude? = nil,
        includeRawChunks: Bool = false,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        onChunk: StreamTextOnChunk? = nil,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil,
        internalOptions: StreamTextInternalOptions = StreamTextInternalOptions(),
        settings: CallSettings = CallSettings()
    ) where OutputValue == JSONValue, PartialOutputValue == JSONValue {
        self.init(
            model: .v2(model),
            system: system,
            prompt: prompt,
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            providerOptions: providerOptions,
            activeTools: activeTools,
            telemetry: telemetry,
            approve: approve,
            transforms: transforms,
            download: download,
            repairToolCall: repairToolCall,
            prepareStep: prepareStep,
            context: context,
            include: include,
            includeRawChunks: includeRawChunks,
            stopWhen: stopWhen,
            onChunk: onChunk,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            onAbort: onAbort,
            onError: onError,
            internalOptions: internalOptions,
            settings: settings
        )
    }

    public init(
        model: any LanguageModelV3,
        experimentalOutput: Output.Specification<OutputValue, PartialOutputValue>,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        telemetry: TelemetrySettings? = nil,
        approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
        transforms: [StreamTextTransform] = [],
        download: DownloadFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        prepareStep: PrepareStepFunction? = nil,
        context: JSONValue? = nil,
        include: StreamTextInclude? = nil,
        includeRawChunks: Bool = false,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        onChunk: StreamTextOnChunk? = nil,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil,
        internalOptions: StreamTextInternalOptions = StreamTextInternalOptions(),
        settings: CallSettings = CallSettings()
    ) {
        self.init(
            model: .v3(model),
            experimentalOutput: experimentalOutput,
            system: system,
            prompt: prompt,
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            providerOptions: providerOptions,
            activeTools: activeTools,
            telemetry: telemetry,
            approve: approve,
            transforms: transforms,
            download: download,
            repairToolCall: repairToolCall,
            prepareStep: prepareStep,
            context: context,
            include: include,
            includeRawChunks: includeRawChunks,
            stopWhen: stopWhen,
            onChunk: onChunk,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            onAbort: onAbort,
            onError: onError,
            internalOptions: internalOptions,
            settings: settings
        )
    }

    public init(
        model: any LanguageModelV2,
        experimentalOutput: Output.Specification<OutputValue, PartialOutputValue>,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        telemetry: TelemetrySettings? = nil,
        approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
        transforms: [StreamTextTransform] = [],
        download: DownloadFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        prepareStep: PrepareStepFunction? = nil,
        context: JSONValue? = nil,
        include: StreamTextInclude? = nil,
        includeRawChunks: Bool = false,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        onChunk: StreamTextOnChunk? = nil,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil,
        internalOptions: StreamTextInternalOptions = StreamTextInternalOptions(),
        settings: CallSettings = CallSettings()
    ) {
        self.init(
            model: .v2(model),
            experimentalOutput: experimentalOutput,
            system: system,
            prompt: prompt,
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            providerOptions: providerOptions,
            activeTools: activeTools,
            telemetry: telemetry,
            approve: approve,
            transforms: transforms,
            download: download,
            repairToolCall: repairToolCall,
            prepareStep: prepareStep,
            context: context,
            include: include,
            includeRawChunks: includeRawChunks,
            stopWhen: stopWhen,
            onChunk: onChunk,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            onAbort: onAbort,
            onError: onError,
            internalOptions: internalOptions,
            settings: settings
        )
    }
}

/**
 Executes `streamText` using a request object.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    _ request: StreamTextRequest<OutputValue, PartialOutputValue>
) throws -> DefaultStreamTextResult<OutputValue, PartialOutputValue> {
    if let prompt = request.prompt, request.messages != nil {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(request.system ?? "nil"), prompt: \(prompt), messages: provided)",
            message: "Provide either `prompt` or `messages`, not both."
        )
    }

    if let prompt = request.prompt {
        return try streamText(
            model: request.model,
            system: request.system,
            prompt: prompt,
            tools: request.tools,
            toolChoice: request.toolChoice,
            providerOptions: request.providerOptions,
            experimentalActiveTools: nil,
            activeTools: request.activeTools,
            experimentalOutput: request.experimentalOutput,
            experimentalTelemetry: request.telemetry,
            experimentalApprove: request.approve,
            experimentalTransform: request.transforms,
            experimentalDownload: request.download,
            experimentalRepairToolCall: request.repairToolCall,
            prepareStep: request.prepareStep,
            experimentalContext: request.context,
            experimentalInclude: request.include,
            includeRawChunks: request.includeRawChunks,
            stopWhen: request.stopWhen,
            onChunk: request.onChunk,
            onStepFinish: request.onStepFinish,
            onFinish: request.onFinish,
            onAbort: request.onAbort,
            onError: request.onError,
            internalOptions: request.internalOptions,
            settings: request.settings
        )
    }

    if let messages = request.messages {
        return try streamText(
            model: request.model,
            system: request.system,
            messages: messages,
            tools: request.tools,
            toolChoice: request.toolChoice,
            providerOptions: request.providerOptions,
            experimentalActiveTools: nil,
            activeTools: request.activeTools,
            experimentalOutput: request.experimentalOutput,
            experimentalTelemetry: request.telemetry,
            experimentalApprove: request.approve,
            experimentalTransform: request.transforms,
            experimentalDownload: request.download,
            experimentalRepairToolCall: request.repairToolCall,
            prepareStep: request.prepareStep,
            experimentalContext: request.context,
            experimentalInclude: request.include,
            includeRawChunks: request.includeRawChunks,
            stopWhen: request.stopWhen,
            onChunk: request.onChunk,
            onStepFinish: request.onStepFinish,
            onFinish: request.onFinish,
            onAbort: request.onAbort,
            onError: request.onError,
            internalOptions: request.internalOptions,
            settings: request.settings
        )
    }

    throw InvalidPromptError(
        prompt: "Prompt(system: \(request.system ?? "nil"))",
        message: "Either `prompt` or `messages` must be provided."
    )
}
