import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Convenience overloads for LanguageModel to match TypeScript API.

 These overloads allow passing `LanguageModelV3` or `LanguageModelV2` directly
 without wrapping in `.v3()` or `.v2()`, matching the TypeScript union type behavior.

 TypeScript:
 ```typescript
 type LanguageModel = string | LanguageModelV3 | LanguageModelV2;
 generateText({ model: openai('gpt-4o'), ... })  // ✓ works
 ```

 Swift (with these overloads):
 ```swift
 generateText(model: openai("gpt-4o"), ...)  // ✓ works (calls .v3() internally)
 generateText(model: .v3(openai("gpt-4o")), ...)  // ✓ also works (explicit)
 ```
 */

// MARK: - generateText overloads

/**
 Generate text with a LanguageModelV3 directly (simple text generation without structured output).

 Convenience overload for the most common use case - simple text generation.
 This version doesn't require specifying the OutputValue generic parameter.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateText(
    model: any LanguageModelV3,
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
    internalOptions _internal: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStepFinish: GenerateTextOnStepFinishCallback? = nil,
    onFinish: GenerateTextOnFinishCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<JSONValue> {
    return try await generateText(
        model: .v3(model),
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
        internalOptions: _internal,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        settings: settings
    )
}

/**
 Generate text with a LanguageModelV3 directly (with structured output).

 Convenience overload that wraps the model in `LanguageModel.v3()`.
 Use this version when you need structured output via `experimentalOutput`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateText<OutputValue: Sendable>(
    model: any LanguageModelV3,
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
    internalOptions _internal: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStepFinish: GenerateTextOnStepFinishCallback? = nil,
    onFinish: GenerateTextOnFinishCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<OutputValue> {
    return try await generateText(
        model: .v3(model),
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
        internalOptions: _internal,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        settings: settings
    )
}

/**
 Generate text with a LanguageModelV2 directly (simple text generation without structured output).

 Convenience overload for the most common use case - simple text generation.
 This version doesn't require specifying the OutputValue generic parameter.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateText(
    model: any LanguageModelV2,
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
    internalOptions _internal: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStepFinish: GenerateTextOnStepFinishCallback? = nil,
    onFinish: GenerateTextOnFinishCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<JSONValue> {
    return try await generateText(
        model: .v2(model),
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
        internalOptions: _internal,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        settings: settings
    )
}

/**
 Generate text with a LanguageModelV2 directly (with structured output).

 Convenience overload that wraps the model in `LanguageModel.v2()`.
 Use this version when you need structured output via `experimentalOutput`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateText<OutputValue: Sendable>(
    model: any LanguageModelV2,
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
    internalOptions _internal: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStepFinish: GenerateTextOnStepFinishCallback? = nil,
    onFinish: GenerateTextOnFinishCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<OutputValue> {
    return try await generateText(
        model: .v2(model),
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
        internalOptions: _internal,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        settings: settings
    )
}

// MARK: - streamText overloads

/**
 Stream text with a LanguageModelV3 directly (simple streaming without structured output).

 Convenience overload for the most common use case - simple text streaming.
 This version doesn't require specifying the OutputValue/PartialOutputValue generic parameters.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText(
    model: any LanguageModelV3,
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
    return try streamText(
        model: .v3(model),
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

/**
 Stream text with a LanguageModelV3 directly (with structured output).

 Convenience overload that wraps the model in `LanguageModel.v3()`.
 Use this version when you need structured output via `experimentalOutput`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model: any LanguageModelV3,
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
    return try streamText(
        model: .v3(model),
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

/**
 Stream text with a LanguageModelV2 directly (simple streaming without structured output).

 Convenience overload for the most common use case - simple text streaming.
 This version doesn't require specifying the OutputValue/PartialOutputValue generic parameters.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText(
    model: any LanguageModelV2,
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
    return try streamText(
        model: .v2(model),
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

/**
 Stream text with a LanguageModelV2 directly (with structured output).

 Convenience overload that wraps the model in `LanguageModel.v2()`.
 Use this version when you need structured output via `experimentalOutput`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model: any LanguageModelV2,
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
    return try streamText(
        model: .v2(model),
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

// MARK: - generateObject overloads

/**
 Generate object with a LanguageModelV3 directly.

 Convenience overload that wraps the model in `LanguageModel.v3()`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ObjectResult>(
    model: any LanguageModelV3,
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
        model: .v3(model),
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

/**
 Generate object with a LanguageModelV2 directly.

 Convenience overload that wraps the model in `LanguageModel.v2()`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateObject<ObjectResult>(
    model: any LanguageModelV2,
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
        model: .v2(model),
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
