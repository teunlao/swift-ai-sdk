import Foundation
import AISDKProvider
import AISDKProviderUtils
import AISDKJSONSchema

// MARK: - Request object V4 convenience

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public extension GenerateTextRequest {
    init(
        model: any LanguageModelV4,
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
            model: .v4(model),
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

    init(
        model: any LanguageModelV4,
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
            model: .v4(model),
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public extension StreamTextRequest {
    init(
        model: any LanguageModelV4,
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
            model: .v4(model),
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

    init(
        model: any LanguageModelV4,
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
            model: .v4(model),
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

public extension PrepareStepResult {
    init(
        model: any LanguageModelV4,
        toolChoice: ToolChoice? = nil,
        activeTools: [String]? = nil,
        system: String? = nil,
        messages: [ModelMessage]? = nil,
        experimentalContext: JSONValue? = nil,
        providerOptions: ProviderOptions? = nil
    ) {
        self.init(
            model: .v4(model),
            toolChoice: toolChoice,
            activeTools: activeTools,
            system: system,
            messages: messages,
            experimentalContext: experimentalContext,
            providerOptions: providerOptions
        )
    }
}

// MARK: - generateText V4 convenience

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateText(
    model: any LanguageModelV4,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    stopWhen: [StopCondition] = [stepCountIs(1)],
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalPrepareStep: PrepareStepFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    experimentalContext: JSONValue? = nil,
    experimentalInclude include: GenerateTextInclude? = nil,
    internalOptions _internal: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStepFinish: GenerateTextOnStepFinishCallback? = nil,
    onFinish: GenerateTextOnFinishCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<JSONValue> {
    try await generateText(
        model: .v4(model),
        tools: tools,
        toolChoice: toolChoice,
        system: system,
        prompt: prompt,
        messages: messages,
        stopWhen: stopWhen,
        experimentalOutput: nil as Output.Specification<JSONValue, JSONValue>?,
        experimentalTelemetry: telemetry,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalPrepareStep: experimentalPrepareStep,
        prepareStep: prepareStep,
        experimentalRepairToolCall: repairToolCall,
        experimentalDownload: download,
        experimentalContext: experimentalContext,
        experimentalInclude: include,
        internalOptions: _internal,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateText<OutputValue: Sendable>(
    model: any LanguageModelV4,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    stopWhen: [StopCondition] = [stepCountIs(1)],
    experimentalOutput output: Output.Specification<OutputValue, JSONValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalPrepareStep: PrepareStepFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    experimentalContext: JSONValue? = nil,
    experimentalInclude include: GenerateTextInclude? = nil,
    internalOptions _internal: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStepFinish: GenerateTextOnStepFinishCallback? = nil,
    onFinish: GenerateTextOnFinishCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<OutputValue> {
    try await generateText(
        model: .v4(model),
        tools: tools,
        toolChoice: toolChoice,
        system: system,
        prompt: prompt,
        messages: messages,
        stopWhen: stopWhen,
        experimentalOutput: output,
        experimentalTelemetry: telemetry,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalPrepareStep: experimentalPrepareStep,
        prepareStep: prepareStep,
        experimentalRepairToolCall: repairToolCall,
        experimentalDownload: download,
        experimentalContext: experimentalContext,
        experimentalInclude: include,
        internalOptions: _internal,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        settings: settings
    )
}

// MARK: - streamText V4 convenience

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText(
    model: any LanguageModelV4,
    prompt: String,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalContext: JSONValue? = nil,
    experimentalInclude include: StreamTextInclude? = nil,
    includeRawChunks: Bool = false,
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil,
    internalOptions _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<JSONValue, JSONValue> {
    try streamText(
        model: .v4(model),
        prompt: prompt,
        tools: tools,
        toolChoice: toolChoice,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalOutput: nil as SwiftAISDK.Output.Specification<JSONValue, JSONValue>?,
        experimentalTelemetry: telemetry,
        experimentalApprove: approve,
        experimentalTransform: transforms,
        experimentalDownload: download,
        experimentalRepairToolCall: repairToolCall,
        prepareStep: prepareStep,
        experimentalContext: experimentalContext,
        experimentalInclude: include,
        includeRawChunks: includeRawChunks,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError,
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText(
    model: any LanguageModelV4,
    system: String?,
    prompt: String,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalContext: JSONValue? = nil,
    experimentalInclude include: StreamTextInclude? = nil,
    includeRawChunks: Bool = false,
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil,
    internalOptions _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<JSONValue, JSONValue> {
    try streamText(
        model: .v4(model),
        system: system,
        prompt: prompt,
        tools: tools,
        toolChoice: toolChoice,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalOutput: nil as SwiftAISDK.Output.Specification<JSONValue, JSONValue>?,
        experimentalTelemetry: telemetry,
        experimentalApprove: approve,
        experimentalTransform: transforms,
        experimentalDownload: download,
        experimentalRepairToolCall: repairToolCall,
        prepareStep: prepareStep,
        experimentalContext: experimentalContext,
        experimentalInclude: include,
        includeRawChunks: includeRawChunks,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError,
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText(
    model: any LanguageModelV4,
    system: String? = nil,
    messages: [ModelMessage],
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalContext: JSONValue? = nil,
    experimentalInclude include: StreamTextInclude? = nil,
    includeRawChunks: Bool = false,
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil,
    internalOptions _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<JSONValue, JSONValue> {
    try streamText(
        model: .v4(model),
        system: system,
        messages: messages,
        tools: tools,
        toolChoice: toolChoice,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalOutput: nil as SwiftAISDK.Output.Specification<JSONValue, JSONValue>?,
        experimentalTelemetry: telemetry,
        experimentalApprove: approve,
        experimentalTransform: transforms,
        experimentalDownload: download,
        experimentalRepairToolCall: repairToolCall,
        prepareStep: prepareStep,
        experimentalContext: experimentalContext,
        experimentalInclude: include,
        includeRawChunks: includeRawChunks,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError,
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model: any LanguageModelV4,
    prompt: String,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalOutput output: SwiftAISDK.Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalContext: JSONValue? = nil,
    experimentalInclude include: StreamTextInclude? = nil,
    includeRawChunks: Bool = false,
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil,
    internalOptions _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<OutputValue, PartialOutputValue> {
    try streamText(
        model: .v4(model),
        prompt: prompt,
        tools: tools,
        toolChoice: toolChoice,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalOutput: output,
        experimentalTelemetry: telemetry,
        experimentalApprove: approve,
        experimentalTransform: transforms,
        experimentalDownload: download,
        experimentalRepairToolCall: repairToolCall,
        prepareStep: prepareStep,
        experimentalContext: experimentalContext,
        experimentalInclude: include,
        includeRawChunks: includeRawChunks,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError,
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model: any LanguageModelV4,
    system: String? = nil,
    messages: [ModelMessage],
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalOutput output: SwiftAISDK.Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalContext: JSONValue? = nil,
    experimentalInclude include: StreamTextInclude? = nil,
    includeRawChunks: Bool = false,
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil,
    internalOptions _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<OutputValue, PartialOutputValue> {
    try streamText(
        model: .v4(model),
        system: system,
        messages: messages,
        tools: tools,
        toolChoice: toolChoice,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalOutput: output,
        experimentalTelemetry: telemetry,
        experimentalApprove: approve,
        experimentalTransform: transforms,
        experimentalDownload: download,
        experimentalRepairToolCall: repairToolCall,
        prepareStep: prepareStep,
        experimentalContext: experimentalContext,
        experimentalInclude: include,
        includeRawChunks: includeRawChunks,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError,
        internalOptions: _internal,
        settings: settings
    )
}

// MARK: - generateObject V4 convenience

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ResultValue, PartialValue, ElementStream>(
    model: any LanguageModelV4,
    output: GenerateObjectOutputSpec<ResultValue, PartialValue, ElementStream>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions _internal: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<ResultValue> {
    try await generateObject(
        model: .v4(model),
        output: output,
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ObjectResult: Codable & Sendable>(
    model: any LanguageModelV4,
    schema type: ObjectResult.Type,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<ObjectResult> {
    try await generateObject(
        model: .v4(model),
        schema: type,
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ObjectResult>(
    model: any LanguageModelV4,
    schema: FlexibleSchema<ObjectResult>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<ObjectResult> {
    try await generateObject(
        model: .v4(model),
        schema: schema,
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectArray<ElementResult: Codable & Sendable>(
    model: any LanguageModelV4,
    schema elementType: ElementResult.Type,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<[ElementResult]> {
    try await generateObjectArray(
        model: .v4(model),
        schema: elementType,
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectArray<ElementResult>(
    model: any LanguageModelV4,
    schema: FlexibleSchema<ElementResult>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<[ElementResult]> {
    try await generateObjectArray(
        model: .v4(model),
        schema: schema,
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectEnum(
    model: any LanguageModelV4,
    values: [String],
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<String> {
    try await generateObjectEnum(
        model: .v4(model),
        values: values,
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObjectNoSchema(
    model: any LanguageModelV4,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) async throws -> GenerateObjectResult<JSONValue> {
    try await generateObjectNoSchema(
        model: .v4(model),
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        internalOptions: internalOptions,
        settings: settings
    )
}

// MARK: - streamObject V4 convenience

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ResultValue, PartialValue, ElementStream>(
    model: any LanguageModelV4,
    output: GenerateObjectOutputSpec<ResultValue, PartialValue, ElementStream>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<ResultValue>? = nil,
    internalOptions _internal: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<PartialValue, ResultValue, ElementStream> {
    try streamObject(
        model: .v4(model),
        output: output,
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onError: onError,
        onFinish: onFinish,
        internalOptions: _internal,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ObjectResult: Codable & Sendable>(
    model: any LanguageModelV4,
    schema type: ObjectResult.Type,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<ObjectResult>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<[String: JSONValue], ObjectResult, Never> {
    try streamObject(
        model: .v4(model),
        schema: type,
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObject<ObjectResult>(
    model: any LanguageModelV4,
    schema: FlexibleSchema<ObjectResult>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<ObjectResult>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<[String: JSONValue], ObjectResult, Never> {
    try streamObject(
        model: .v4(model),
        schema: schema,
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObjectNoSchema(
    model: any LanguageModelV4,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<JSONValue>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<JSONValue, JSONValue, Never> {
    try streamObjectNoSchema(
        model: .v4(model),
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObjectArray<ElementResult: Codable & Sendable>(
    model: any LanguageModelV4,
    schema elementType: ElementResult.Type,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<[ElementResult]>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<[ElementResult], [ElementResult], AsyncIterableStream<ElementResult>> {
    try streamObjectArray(
        model: .v4(model),
        schema: elementType,
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObjectArray<ElementResult>(
    model: any LanguageModelV4,
    schema: FlexibleSchema<ElementResult>,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    schemaName: String? = nil,
    schemaDescription: String? = nil,
    mode: GenerateObjectJSONMode = .auto,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<[ElementResult]>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<[ElementResult], [ElementResult], AsyncIterableStream<ElementResult>> {
    try streamObjectArray(
        model: .v4(model),
        schema: schema,
        system: system,
        prompt: prompt,
        messages: messages,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        mode: mode,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamObjectEnum(
    model: any LanguageModelV4,
    values: [String],
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    experimentalRepairText repairText: RepairTextFunction? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    providerOptions: ProviderOptions? = nil,
    onError: StreamObjectOnErrorCallback? = nil,
    onFinish: StreamObjectOnFinishCallback<String>? = nil,
    internalOptions: GenerateObjectInternalOptions = GenerateObjectInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> StreamObjectResult<String, String, Never> {
    try streamObjectEnum(
        model: .v4(model),
        values: values,
        system: system,
        prompt: prompt,
        messages: messages,
        experimentalRepairText: repairText,
        experimentalTelemetry: telemetry,
        experimentalDownload: download,
        providerOptions: providerOptions,
        onError: onError,
        onFinish: onFinish,
        internalOptions: internalOptions,
        settings: settings
    )
}
