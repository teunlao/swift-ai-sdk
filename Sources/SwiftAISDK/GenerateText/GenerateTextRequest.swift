import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A request object for `generateText`, mirroring the TypeScript object-style API.

 This is a Swift-only DX convenience that lets you build reusable "base" requests
 (e.g. `base + override`) without repeating long argument lists.

 It does not replace the existing `generateText(...)` overloads; those remain the
 canonical API and continue to work unchanged.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct GenerateTextRequest<OutputValue: Sendable>: Sendable {
    public var model: LanguageModel

    public var tools: ToolSet?
    public var toolChoice: ToolChoice?

    public var system: String?
    public var prompt: String?
    public var messages: [ModelMessage]?

    public var stopWhen: [StopCondition]

    public var experimentalOutput: Output.Specification<OutputValue, JSONValue>?

    public var telemetry: TelemetrySettings?
    public var providerOptions: ProviderOptions?

    public var activeTools: [String]?
    public var prepareStep: PrepareStepFunction?

    public var repairToolCall: ToolCallRepairFunction?
    public var download: DownloadFunction?
    public var context: JSONValue?
    public var include: GenerateTextInclude?

    public var internalOptions: GenerateTextInternalOptions

    public var onStepFinish: GenerateTextOnStepFinishCallback?
    public var onFinish: GenerateTextOnFinishCallback?

    public var settings: CallSettings

    /**
     Creates a request for the common case (no structured output parser).

     The generic output type is fixed to `JSONValue` to keep the call site concise:

     ```swift
     var req = GenerateTextRequest(model: openai("gpt-5"))
     req.prompt = "Hello"
     let result = try await generateText(req)
     ```
     */
    public init(
        model: LanguageModel,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        telemetry: TelemetrySettings? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        prepareStep: PrepareStepFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        download: DownloadFunction? = nil,
        context: JSONValue? = nil,
        include: GenerateTextInclude? = nil,
        internalOptions: GenerateTextInternalOptions = GenerateTextInternalOptions(),
        onStepFinish: GenerateTextOnStepFinishCallback? = nil,
        onFinish: GenerateTextOnFinishCallback? = nil,
        settings: CallSettings = CallSettings()
    ) where OutputValue == JSONValue {
        self.model = model
        self.tools = tools
        self.toolChoice = toolChoice
        self.system = system
        self.prompt = prompt
        self.messages = messages
        self.stopWhen = stopWhen
        self.experimentalOutput = nil
        self.telemetry = telemetry
        self.providerOptions = providerOptions
        self.activeTools = activeTools
        self.prepareStep = prepareStep
        self.repairToolCall = repairToolCall
        self.download = download
        self.context = context
        self.include = include
        self.internalOptions = internalOptions
        self.onStepFinish = onStepFinish
        self.onFinish = onFinish
        self.settings = settings
    }

    /**
     Creates a request with a structured output parser.

     Passing the `experimentalOutput` specification makes `OutputValue` inferable at the call site.
     */
    public init(
        model: LanguageModel,
        experimentalOutput: Output.Specification<OutputValue, JSONValue>,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        telemetry: TelemetrySettings? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        prepareStep: PrepareStepFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        download: DownloadFunction? = nil,
        context: JSONValue? = nil,
        include: GenerateTextInclude? = nil,
        internalOptions: GenerateTextInternalOptions = GenerateTextInternalOptions(),
        onStepFinish: GenerateTextOnStepFinishCallback? = nil,
        onFinish: GenerateTextOnFinishCallback? = nil,
        settings: CallSettings = CallSettings()
    ) {
        self.model = model
        self.tools = tools
        self.toolChoice = toolChoice
        self.system = system
        self.prompt = prompt
        self.messages = messages
        self.stopWhen = stopWhen
        self.experimentalOutput = experimentalOutput
        self.telemetry = telemetry
        self.providerOptions = providerOptions
        self.activeTools = activeTools
        self.prepareStep = prepareStep
        self.repairToolCall = repairToolCall
        self.download = download
        self.context = context
        self.include = include
        self.internalOptions = internalOptions
        self.onStepFinish = onStepFinish
        self.onFinish = onFinish
        self.settings = settings
    }

    // MARK: - Model convenience initializers

    public init(
        model: any LanguageModelV3,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        telemetry: TelemetrySettings? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        prepareStep: PrepareStepFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        download: DownloadFunction? = nil,
        context: JSONValue? = nil,
        include: GenerateTextInclude? = nil,
        internalOptions: GenerateTextInternalOptions = GenerateTextInternalOptions(),
        onStepFinish: GenerateTextOnStepFinishCallback? = nil,
        onFinish: GenerateTextOnFinishCallback? = nil,
        settings: CallSettings = CallSettings()
    ) where OutputValue == JSONValue {
        self.init(
            model: .v3(model),
            tools: tools,
            toolChoice: toolChoice,
            system: system,
            prompt: prompt,
            messages: messages,
            stopWhen: stopWhen,
            telemetry: telemetry,
            providerOptions: providerOptions,
            activeTools: activeTools,
            prepareStep: prepareStep,
            repairToolCall: repairToolCall,
            download: download,
            context: context,
            include: include,
            internalOptions: internalOptions,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            settings: settings
        )
    }

    public init(
        model: any LanguageModelV2,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        telemetry: TelemetrySettings? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        prepareStep: PrepareStepFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        download: DownloadFunction? = nil,
        context: JSONValue? = nil,
        include: GenerateTextInclude? = nil,
        internalOptions: GenerateTextInternalOptions = GenerateTextInternalOptions(),
        onStepFinish: GenerateTextOnStepFinishCallback? = nil,
        onFinish: GenerateTextOnFinishCallback? = nil,
        settings: CallSettings = CallSettings()
    ) where OutputValue == JSONValue {
        self.init(
            model: .v2(model),
            tools: tools,
            toolChoice: toolChoice,
            system: system,
            prompt: prompt,
            messages: messages,
            stopWhen: stopWhen,
            telemetry: telemetry,
            providerOptions: providerOptions,
            activeTools: activeTools,
            prepareStep: prepareStep,
            repairToolCall: repairToolCall,
            download: download,
            context: context,
            include: include,
            internalOptions: internalOptions,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            settings: settings
        )
    }

    public init(
        model: any LanguageModelV3,
        experimentalOutput: Output.Specification<OutputValue, JSONValue>,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        telemetry: TelemetrySettings? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        prepareStep: PrepareStepFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        download: DownloadFunction? = nil,
        context: JSONValue? = nil,
        include: GenerateTextInclude? = nil,
        internalOptions: GenerateTextInternalOptions = GenerateTextInternalOptions(),
        onStepFinish: GenerateTextOnStepFinishCallback? = nil,
        onFinish: GenerateTextOnFinishCallback? = nil,
        settings: CallSettings = CallSettings()
    ) {
        self.init(
            model: .v3(model),
            experimentalOutput: experimentalOutput,
            tools: tools,
            toolChoice: toolChoice,
            system: system,
            prompt: prompt,
            messages: messages,
            stopWhen: stopWhen,
            telemetry: telemetry,
            providerOptions: providerOptions,
            activeTools: activeTools,
            prepareStep: prepareStep,
            repairToolCall: repairToolCall,
            download: download,
            context: context,
            include: include,
            internalOptions: internalOptions,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            settings: settings
        )
    }

    public init(
        model: any LanguageModelV2,
        experimentalOutput: Output.Specification<OutputValue, JSONValue>,
        tools: ToolSet? = nil,
        toolChoice: ToolChoice? = nil,
        system: String? = nil,
        prompt: String? = nil,
        messages: [ModelMessage]? = nil,
        stopWhen: [StopCondition] = [stepCountIs(1)],
        telemetry: TelemetrySettings? = nil,
        providerOptions: ProviderOptions? = nil,
        activeTools: [String]? = nil,
        prepareStep: PrepareStepFunction? = nil,
        repairToolCall: ToolCallRepairFunction? = nil,
        download: DownloadFunction? = nil,
        context: JSONValue? = nil,
        include: GenerateTextInclude? = nil,
        internalOptions: GenerateTextInternalOptions = GenerateTextInternalOptions(),
        onStepFinish: GenerateTextOnStepFinishCallback? = nil,
        onFinish: GenerateTextOnFinishCallback? = nil,
        settings: CallSettings = CallSettings()
    ) {
        self.init(
            model: .v2(model),
            experimentalOutput: experimentalOutput,
            tools: tools,
            toolChoice: toolChoice,
            system: system,
            prompt: prompt,
            messages: messages,
            stopWhen: stopWhen,
            telemetry: telemetry,
            providerOptions: providerOptions,
            activeTools: activeTools,
            prepareStep: prepareStep,
            repairToolCall: repairToolCall,
            download: download,
            context: context,
            include: include,
            internalOptions: internalOptions,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            settings: settings
        )
    }
}

/**
 Executes `generateText` using a request object.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateText<OutputValue: Sendable>(
    _ request: GenerateTextRequest<OutputValue>
) async throws -> DefaultGenerateTextResult<OutputValue> {
    try await generateText(
        model: request.model,
        tools: request.tools,
        toolChoice: request.toolChoice,
        system: request.system,
        prompt: request.prompt,
        messages: request.messages,
        stopWhen: request.stopWhen,
        experimentalOutput: request.experimentalOutput,
        experimentalTelemetry: request.telemetry,
        providerOptions: request.providerOptions,
        experimentalActiveTools: nil,
        activeTools: request.activeTools,
        experimentalPrepareStep: nil,
        prepareStep: request.prepareStep,
        experimentalRepairToolCall: request.repairToolCall,
        experimentalDownload: request.download,
        experimentalContext: request.context,
        experimentalInclude: request.include,
        internalOptions: request.internalOptions,
        onStepFinish: request.onStepFinish,
        onFinish: request.onFinish,
        settings: request.settings
    )
}
