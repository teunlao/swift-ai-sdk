import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 What streaming step results retain.

 Port of `StreamTextInclude` from `@ai-sdk/ai/src/generate-text/stream-text.ts`.
 Everything defaults to `false`.
 */
public struct StreamTextInclude: Sendable {
    /// Retain the request body in step results.
    public var requestBody: Bool?

    /// Retain the request messages in step results.
    public var requestMessages: Bool?

    /// Forward raw provider chunks as `raw` stream parts.
    public var rawChunks: Bool?

    public init(requestBody: Bool? = nil, requestMessages: Bool? = nil, rawChunks: Bool? = nil) {
        self.requestBody = requestBody
        self.requestMessages = requestMessages
        self.rawChunks = rawChunks
    }
}

/// Internal knobs for tests: id generators and clocks.
public struct StreamTextInternalOptions: Sendable {
    /// Millisecond clock used for performance measurements.
    public var now: @Sendable () -> Double

    /// Generates response ids, approval ids and unique part ids (default prefix `aitxt`).
    public var generateId: IDGenerator

    /// Generates the call id of the operation (default prefix `call`).
    public var generateCallId: IDGenerator

    /// Clock used for response timestamps when the provider sends none.
    public var currentDate: @Sendable () -> Date

    public init(
        now: @escaping @Sendable () -> Double = { SwiftAISDK.now() },
        generateId: IDGenerator? = nil,
        generateCallId: IDGenerator? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
        self.generateId = generateId ?? (try! createIDGenerator(prefix: "aitxt", size: 24))
        self.generateCallId = generateCallId ?? (try! createIDGenerator(prefix: "call", size: 24))
        self.currentDate = currentDate
    }
}

/// Options passed to a stream transform.
public struct StreamTextTransformOptions: Sendable {
    /// The tools of the call.
    public var tools: ToolSet?

    /// Stops the stream: no further parts are emitted after the transform's own.
    public var stopStream: @Sendable () -> Void

    public init(tools: ToolSet?, stopStream: @escaping @Sendable () -> Void) {
        self.tools = tools
        self.stopStream = stopStream
    }
}

/**
 Transforms the stream parts of `streamText` (e.g. `smoothStream`).

 Port of `StreamTextTransform`. Each retry attempt of a step is transformed
 separately.
 */
public typealias StreamTextTransform = @Sendable (
    _ stream: AsyncThrowingStream<TextStreamPart, Error>,
    _ options: StreamTextTransformOptions
) -> AsyncThrowingStream<TextStreamPart, Error>

/// Called for each stream part.
public typealias StreamTextOnChunkCallback = @Sendable (TextStreamPart) async throws -> Void

/// Result of `onError`: request a retry of the failed model stream (requires `streamRetries`).
public struct StreamTextOnErrorResult: Sendable, Equatable {
    public let retry: Bool

    public init(retry: Bool) {
        self.retry = retry
    }

    public static let retry = StreamTextOnErrorResult(retry: true)
}

/**
 Called for errors in the stream. Returning `.retry` restarts a failed model
 stream once when `streamRetries` is set.

 Port of `StreamTextOnErrorCallback` / `StreamTextOnErrorRetryCallback`.
 */
public typealias StreamTextOnErrorCallback = @Sendable (any Error) async throws -> StreamTextOnErrorResult?

/**
 Event passed to `onEnd` of `streamText`: the end event with the parsed output.

 Port of `StreamTextEndEvent` from `@ai-sdk/ai/src/generate-text/stream-text.ts`.
 */
@dynamicMemberLookup
public struct StreamTextEndEvent<OutputValue: Sendable>: Sendable {
    public let event: GenerateTextEndEvent

    /// The parsed output; `nil` when it could not be parsed.
    public let output: OutputValue?

    public init(event: GenerateTextEndEvent, output: OutputValue?) {
        self.event = event
        self.output = output
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<GenerateTextEndEvent, T>) -> T {
        event[keyPath: keyPath]
    }
}

public typealias StreamTextOnEndCallback<OutputValue: Sendable> = @Sendable (StreamTextEndEvent<OutputValue>) async throws -> Void

/// Everything a `streamText` call is configured with.
struct StreamTextConfiguration<OutputValue: Sendable, PartialOutput: Sendable>: Sendable {
    var model: any LanguageModelV4
    var modelArgument: LanguageModel
    var tools: ToolSet?
    var toolChoice: ToolChoice?
    var instructions: Instructions?
    var prompt: String?
    var messages: [ModelMessage]?
    var allowSystemInMessages: Bool?
    var stopWhen: [StopCondition]
    var output: Output.Specification<OutputValue, PartialOutput>
    var outputIsDefault: Bool
    var toolApproval: ToolApprovalConfiguration?
    var toolApprovalSecret: ToolApprovalSecret?
    var telemetry: TelemetryOptions?
    var providerOptions: ProviderOptions?
    var activeTools: [String]?
    var toolOrder: [String]?
    var toolCallConcurrency: Int?
    var prepareStep: PrepareStepFunction?
    var repairToolCall: ToolCallRepairFunction?
    var refineToolInput: ToolInputRefinement?
    var transforms: [StreamTextTransform]
    var download: DownloadFunction?
    var runtimeContext: Context
    var toolsContext: ToolsContext
    var include: StreamTextInclude
    var internalOptions: StreamTextInternalOptions
    var streamRetries: Int?
    var onChunk: StreamTextOnChunkCallback?
    var onError: StreamTextOnErrorCallback?
    var onEnd: StreamTextOnEndCallback<OutputValue>?
    var onAbort: GenerateTextOnAbortCallback?
    var onStepEnd: GenerateTextOnStepEndCallback?
    var onStart: GenerateTextOnStartCallback?
    var onStepStart: GenerateTextOnStepStartCallback?
    var onLanguageModelCallStart: OnLanguageModelCallStartCallback?
    var onLanguageModelCallEnd: OnLanguageModelCallEndCallback?
    var onToolExecutionStart: OnToolExecutionStartCallback?
    var onToolExecutionEnd: OnToolExecutionEndCallback?
    var settings: CallSettings
}

/**
 Streams text and tool calls from a language model.

 Port of `@ai-sdk/ai/src/generate-text/stream-text.ts`. The result is returned
 at once; setup failures surface as `error` stream parts. The model stream is
 read only when the result is consumed (a stream is iterated or a result
 property is awaited).

 - Throws: `InvalidArgumentError` for an invalid `toolCallConcurrency` or retry setting.
 */
public func streamText<OutputValue: Sendable, PartialOutput: Sendable>(
    model modelArg: LanguageModel,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    instructions: Instructions? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    allowSystemInMessages: Bool? = nil,
    stopWhen: [StopCondition] = [isStepCount(1)],
    output: Output.Specification<OutputValue, PartialOutput>,
    toolApproval: ToolApprovalConfiguration? = nil,
    toolApprovalSecret: ToolApprovalSecret? = nil,
    telemetry: TelemetryOptions? = nil,
    providerOptions: ProviderOptions? = nil,
    activeTools: [String]? = nil,
    toolOrder: [String]? = nil,
    toolCallConcurrency: Int? = nil,
    prepareStep: PrepareStepFunction? = nil,
    repairToolCall: ToolCallRepairFunction? = nil,
    refineToolInput: ToolInputRefinement? = nil,
    transform: [StreamTextTransform] = [],
    download: DownloadFunction? = nil,
    runtimeContext: Context = [:],
    toolsContext: ToolsContext = [:],
    include: StreamTextInclude? = nil,
    streamRetries: Int? = nil,
    internalOptions: StreamTextInternalOptions = StreamTextInternalOptions(),
    onChunk: StreamTextOnChunkCallback? = nil,
    onError: StreamTextOnErrorCallback? = nil,
    onEnd: StreamTextOnEndCallback<OutputValue>? = nil,
    onAbort: GenerateTextOnAbortCallback? = nil,
    onStepEnd: GenerateTextOnStepEndCallback? = nil,
    onStart: GenerateTextOnStartCallback? = nil,
    onStepStart: GenerateTextOnStepStartCallback? = nil,
    onLanguageModelCallStart: OnLanguageModelCallStartCallback? = nil,
    onLanguageModelCallEnd: OnLanguageModelCallEndCallback? = nil,
    onToolExecutionStart: OnToolExecutionStartCallback? = nil,
    onToolExecutionEnd: OnToolExecutionEndCallback? = nil,
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<OutputValue, PartialOutput> {
    try makeStreamTextResult(StreamTextConfiguration(
        model: try resolveLanguageModelV4(modelArg),
        modelArgument: modelArg,
        tools: tools,
        toolChoice: toolChoice,
        instructions: instructions,
        prompt: prompt,
        messages: messages,
        allowSystemInMessages: allowSystemInMessages,
        stopWhen: stopWhen,
        output: output,
        outputIsDefault: false,
        toolApproval: toolApproval,
        toolApprovalSecret: toolApprovalSecret,
        telemetry: telemetry,
        providerOptions: providerOptions,
        activeTools: activeTools,
        toolOrder: toolOrder,
        toolCallConcurrency: try prepareToolCallConcurrency(toolCallConcurrency),
        prepareStep: prepareStep,
        repairToolCall: repairToolCall,
        refineToolInput: refineToolInput,
        transforms: transform,
        download: download,
        runtimeContext: runtimeContext,
        toolsContext: toolsContext,
        include: StreamTextInclude(
            requestBody: include?.requestBody ?? false,
            requestMessages: include?.requestMessages ?? false,
            rawChunks: include?.rawChunks ?? false
        ),
        internalOptions: internalOptions,
        streamRetries: streamRetries,
        onChunk: onChunk,
        onError: onError,
        onEnd: onEnd,
        onAbort: onAbort,
        onStepEnd: onStepEnd,
        onStart: onStart,
        onStepStart: onStepStart,
        onLanguageModelCallStart: onLanguageModelCallStart,
        onLanguageModelCallEnd: onLanguageModelCallEnd,
        onToolExecutionStart: onToolExecutionStart,
        onToolExecutionEnd: onToolExecutionEnd,
        settings: settings
    ))
}

/**
 Streams text without a structured output; `output` resolves to the final text.

 Same as `streamText(model:output:…)` with `Output.text()`.
 */
public func streamText(
    model modelArg: LanguageModel,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    instructions: Instructions? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    allowSystemInMessages: Bool? = nil,
    stopWhen: [StopCondition] = [isStepCount(1)],
    toolApproval: ToolApprovalConfiguration? = nil,
    toolApprovalSecret: ToolApprovalSecret? = nil,
    telemetry: TelemetryOptions? = nil,
    providerOptions: ProviderOptions? = nil,
    activeTools: [String]? = nil,
    toolOrder: [String]? = nil,
    toolCallConcurrency: Int? = nil,
    prepareStep: PrepareStepFunction? = nil,
    repairToolCall: ToolCallRepairFunction? = nil,
    refineToolInput: ToolInputRefinement? = nil,
    transform: [StreamTextTransform] = [],
    download: DownloadFunction? = nil,
    runtimeContext: Context = [:],
    toolsContext: ToolsContext = [:],
    include: StreamTextInclude? = nil,
    streamRetries: Int? = nil,
    internalOptions: StreamTextInternalOptions = StreamTextInternalOptions(),
    onChunk: StreamTextOnChunkCallback? = nil,
    onError: StreamTextOnErrorCallback? = nil,
    onEnd: StreamTextOnEndCallback<String>? = nil,
    onAbort: GenerateTextOnAbortCallback? = nil,
    onStepEnd: GenerateTextOnStepEndCallback? = nil,
    onStart: GenerateTextOnStartCallback? = nil,
    onStepStart: GenerateTextOnStepStartCallback? = nil,
    onLanguageModelCallStart: OnLanguageModelCallStartCallback? = nil,
    onLanguageModelCallEnd: OnLanguageModelCallEndCallback? = nil,
    onToolExecutionStart: OnToolExecutionStartCallback? = nil,
    onToolExecutionEnd: OnToolExecutionEndCallback? = nil,
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<String, String> {
    try makeStreamTextResult(StreamTextConfiguration(
        model: try resolveLanguageModelV4(modelArg),
        modelArgument: modelArg,
        tools: tools,
        toolChoice: toolChoice,
        instructions: instructions,
        prompt: prompt,
        messages: messages,
        allowSystemInMessages: allowSystemInMessages,
        stopWhen: stopWhen,
        output: Output.text(),
        outputIsDefault: true,
        toolApproval: toolApproval,
        toolApprovalSecret: toolApprovalSecret,
        telemetry: telemetry,
        providerOptions: providerOptions,
        activeTools: activeTools,
        toolOrder: toolOrder,
        toolCallConcurrency: try prepareToolCallConcurrency(toolCallConcurrency),
        prepareStep: prepareStep,
        repairToolCall: repairToolCall,
        refineToolInput: refineToolInput,
        transforms: transform,
        download: download,
        runtimeContext: runtimeContext,
        toolsContext: toolsContext,
        include: StreamTextInclude(
            requestBody: include?.requestBody ?? false,
            requestMessages: include?.requestMessages ?? false,
            rawChunks: include?.rawChunks ?? false
        ),
        internalOptions: internalOptions,
        streamRetries: streamRetries,
        onChunk: onChunk,
        onError: onError,
        onEnd: onEnd,
        onAbort: onAbort,
        onStepEnd: onStepEnd,
        onStart: onStart,
        onStepStart: onStepStart,
        onLanguageModelCallStart: onLanguageModelCallStart,
        onLanguageModelCallEnd: onLanguageModelCallEnd,
        onToolExecutionStart: onToolExecutionStart,
        onToolExecutionEnd: onToolExecutionEnd,
        settings: settings
    ))
}

private func makeStreamTextResult<OutputValue: Sendable, PartialOutput: Sendable>(
    _ configuration: StreamTextConfiguration<OutputValue, PartialOutput>
) throws -> DefaultStreamTextResult<OutputValue, PartialOutput> {
    let maxRetries = try prepareRetries(maxRetries: configuration.settings.maxRetries, abortSignal: nil).maxRetries
    if let streamRetries = configuration.streamRetries, streamRetries < 0 {
        throw InvalidArgumentError(
            parameter: "streamRetries",
            value: .number(Double(streamRetries)),
            message: "streamRetries must be >= 0"
        )
    }
    return DefaultStreamTextResult(configuration: configuration, maxRetries: maxRetries)
}
