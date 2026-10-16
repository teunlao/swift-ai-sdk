import Foundation
import AISDKProvider
import AISDKProviderUtils

/// A stream part with the partial output parsed so far.
public struct EnrichedStreamPart<PartialOutput: Sendable>: Sendable {
    public let part: TextStreamPart
    public let partialOutput: PartialOutput?
}

/// Parts of the stitched step streams: public parts and retry attempt boundaries.
enum InternalStreamPart: Sendable {
    case part(TextStreamPart)
    case retryBoundary(request: LanguageModelRequestMetadata, warnings: [CallWarning])
}

private enum InternalEnrichedPart<PartialOutput: Sendable>: Sendable {
    case enriched(EnrichedStreamPart<PartialOutput>)
    case retryBoundary(request: LanguageModelRequestMetadata, warnings: [CallWarning])
}

/**
 The result of `streamText`.

 Port of `DefaultStreamTextResult` from `@ai-sdk/ai/src/generate-text/stream-text.ts`.
 Every stream replays all parts from the start. Awaiting a result property
 consumes the stream.
 */
public final class DefaultStreamTextResult<OutputValue: Sendable, PartialOutput: Sendable>: StreamTextResult, @unchecked Sendable {
    public typealias Output = OutputValue

    private let engine: StreamTextEngine<OutputValue, PartialOutput>
    private let outputLock = NSLock()
    private var outputTask: Task<OutputValue, Error>?

    init(configuration: StreamTextConfiguration<OutputValue, PartialOutput>, maxRetries: Int) {
        self.engine = StreamTextEngine(configuration: configuration, maxRetries: maxRetries)
        engine.start()
    }

    var tools: ToolSet? { engine.configuration.tools }

    // MARK: - Streams

    /// All stream parts.
    public var fullStream: AsyncThrowingStream<TextStreamPart, Error> {
        mapStream(engine.replay.stream()) { $0.part }
    }

    /// The text deltas.
    public var textStream: AsyncThrowingStream<String, Error> {
        mapStream(engine.replay.stream()) { enriched -> String? in
            if case .textDelta(_, let text, _) = enriched.part { return text }
            return nil
        }
    }

    /// Partial outputs as they are parsed.
    public var partialOutputStream: AsyncThrowingStream<PartialOutput, Error> {
        mapStream(engine.replay.stream()) { $0.partialOutput }
    }

    /**
     Completed array elements as they are streamed.

     - Throws: `UnsupportedFunctionalityError` when the output is not an array output.
     */
    public func elementStream() throws -> AsyncThrowingStream<JSONValue, Error> {
        guard let newElements = engine.configuration.output.newElements else {
            throw UnsupportedFunctionalityError(
                functionality: "element streams in \(engine.configuration.output.name) mode"
            )
        }
        let source = engine.replay.stream()
        let published = PublishedCounter()
        return pullTransform(source) { enriched in
            guard let partial = enriched.partialOutput else { return [] }
            let elements = try newElements(partial, published.value)
            published.value += elements.count
            return elements
        }
    }

    /// Reads the stream to the end, so result properties resolve.
    public func consumeStream(options: ConsumeStreamOptions? = nil) async {
        do {
            for try await _ in fullStream {}
        } catch {
            engine.rejectResultPromises(error)
            options?.onError?(error)
        }
    }

    private func consume() {
        engine.replay.start()
        Task { await self.consumeStream() }
    }

    // MARK: - Result properties

    public var steps: [StepResult] {
        get async throws {
            consume()
            return try await engine.steps.task.value
        }
    }

    public var finalStep: StepResult {
        get async throws {
            let steps = try await self.steps
            return steps[steps.count - 1]
        }
    }

    public var content: [ContentPart] {
        get async throws { try await steps.flatMap(\.content) }
    }

    public var warnings: [CallWarning]? {
        get async throws { try await steps.flatMap { $0.warnings ?? [] } }
    }

    public var providerMetadata: ProviderMetadata? {
        get async throws { try await finalStep.providerMetadata }
    }

    public var text: String {
        get async throws { try await finalStep.text }
    }

    public var reasoningText: String? {
        get async throws { try await finalStep.reasoningText }
    }

    public var reasoning: [ReasoningOutput] {
        get async throws { try await finalStep.reasoning }
    }

    public var sources: [Source] {
        get async throws { try await steps.flatMap(\.sources) }
    }

    public var files: [GeneratedFile] {
        get async throws { try await steps.flatMap(\.files) }
    }

    public var toolCalls: [TypedToolCall] {
        get async throws { try await steps.flatMap(\.toolCalls) }
    }

    public var staticToolCalls: [StaticToolCall] {
        get async throws { try await steps.flatMap(\.staticToolCalls) }
    }

    public var dynamicToolCalls: [DynamicToolCall] {
        get async throws { try await steps.flatMap(\.dynamicToolCalls) }
    }

    public var toolResults: [TypedToolResult] {
        get async throws { try await steps.flatMap(\.toolResults) }
    }

    public var staticToolResults: [StaticToolResult] {
        get async throws { try await steps.flatMap(\.staticToolResults) }
    }

    public var dynamicToolResults: [DynamicToolResult] {
        get async throws { try await steps.flatMap(\.dynamicToolResults) }
    }

    public var usage: LanguageModelUsage {
        get async throws { try await totalUsage }
    }

    public var totalUsage: LanguageModelUsage {
        get async throws {
            consume()
            return try await engine.totalUsage.task.value
        }
    }

    public var finishReason: FinishReason {
        get async throws {
            consume()
            return try await engine.finishReason.task.value
        }
    }

    public var rawFinishReason: String? {
        get async throws {
            consume()
            return try await engine.rawFinishReason.task.value
        }
    }

    public var request: LanguageModelRequestMetadata {
        get async throws { try await finalStep.request }
    }

    public var response: StepResultResponse {
        get async throws { try await finalStep.response }
    }

    public var responseMessages: [ResponseMessage] {
        get async throws {
            let steps = try await self.steps
            let initial = try await engine.initialResponseMessages.task.value
            return initial + steps.flatMap(\.response.messages)
        }
    }

    /// The parsed output of the final step.
    public var output: OutputValue {
        get async throws { try await outputPromise().value }
    }

    func outputPromise() -> Task<OutputValue, Error> {
        outputLock.lock()
        defer { outputLock.unlock() }
        if let outputTask { return outputTask }
        let task = Task<OutputValue, Error> {
            let step = try await self.finalStep
            return try await self.engine.configuration.output.parseOutput(
                text: step.text,
                response: step.response.metadata,
                usage: step.usage,
                finishReason: step.finishReason
            )
        }
        outputTask = task
        return task
    }

    // MARK: - Responses

    public func pipeTextStreamToResponse(
        _ response: any StreamTextResponseWriter,
        init initOptions: TextStreamResponseInit?
    ) {
        SwiftAISDK.pipeTextStreamToResponse(
            response: response,
            status: initOptions?.status,
            statusText: initOptions?.statusText,
            headers: initOptions?.headers,
            textStream: textStream
        )
    }

    public func toTextStreamResponse(init initOptions: TextStreamResponseInit?) -> TextStreamResponse {
        SwiftAISDK.createTextStreamResponse(
            status: initOptions?.status,
            statusText: initOptions?.statusText,
            headers: initOptions?.headers,
            textStream: textStream
        )
    }

    public func toSSEStream(includeUsage: Bool) -> AsyncThrowingStream<String, Error> {
        makeStreamTextSSEStream(from: fullStream, includeUsage: includeUsage)
    }

    public func toUIMessageStream<Message: UIMessageConvertible>(
        options: UIMessageStreamOptions<Message>?
    ) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
        SwiftAISDK.toUIMessageStream(
            stream: fullStream, tools: tools, options: options ?? UIMessageStreamOptions<Message>()
        )
    }

    public func pipeUIMessageStreamToResponse<Message: UIMessageConvertible>(
        _ response: any StreamTextResponseWriter,
        options: StreamTextUIResponseOptions<Message>?
    ) async throws {
        let stream = toUIMessageStream(options: options?.streamOptions)
        try await SwiftAISDK.pipeUIMessageStreamToResponse(
            response: response,
            stream: stream,
            options: options
        )
    }

    public func toUIMessageStreamResponse<Message: UIMessageConvertible>(
        options: StreamTextUIResponseOptions<Message>?
    ) throws -> UIMessageStreamResponse<Message> {
        let stream = toUIMessageStream(options: options?.streamOptions)
        return try SwiftAISDK.createUIMessageStreamResponse(stream: stream, options: options)
    }
}

private final class PublishedCounter: @unchecked Sendable {
    var value = 0
}

/// Maps a stream, dropping `nil` results.
func mapStream<Input: Sendable, Output: Sendable>(
    _ stream: AsyncThrowingStream<Input, Error>,
    _ transform: @escaping @Sendable (Input) -> Output?
) -> AsyncThrowingStream<Output, Error> {
    pullTransform(stream) { input in transform(input).map { [$0] } ?? [] }
}

// MARK: - Engine

/// Runs one `streamText` call: the step loop, the stream pipeline and the result promises.
final class StreamTextEngine<OutputValue: Sendable, PartialOutput: Sendable>: @unchecked Sendable {
    let configuration: StreamTextConfiguration<OutputValue, PartialOutput>
    private let maxRetries: Int
    private let streamRetries: Int
    private let canRetryStreamViaOnError: Bool

    let totalUsage = DelayedPromise<LanguageModelUsage>()
    let finishReason = DelayedPromise<FinishReason>()
    let rawFinishReason = DelayedPromise<String?>()
    let steps = DelayedPromise<[StepResult]>()
    let initialResponseMessages = DelayedPromise<[ResponseMessage]>()

    let replay: ReplayBuffer<EnrichedStreamPart<PartialOutput>>
    private let stitcher = StreamStitcher<InternalStreamPart>()
    private let dispatcher: TelemetryDispatcher
    private let callId: String

    private let abortController: StreamAbortController?
    private let abortSignal: (@Sendable () -> Bool)?
    private let abortWatcher: AbortSignalWatcher?
    private let stepTimer: AbortTimer?
    private let firstChunkTimer: AbortTimer?
    private let chunkTimer: AbortTimer?

    private let lock = NSLock()
    private var pumpStarted = false
    private var runtimeContext: Context
    private var toolsContext: ToolsContext
    private var recordedSteps: [StepResult] = []
    private var initialResponses: [ResponseMessage] = []
    private var stepMessagesForNextStep: [ModelMessage]?
    private var currentStepMessages: [ModelMessage] = []
    private var instructionsForNextStep: Instructions?
    private var currentStepModel: ModelInfo
    private var stepFinish: DelayedPromise<Void>?
    private var pendingDeferredToolCalls: [String: String] = [:]
    private var isAborted = false
    private var usedTextPartIds: Set<String> = []
    private var usedReasoningPartIds: Set<String> = []
    private var errorsHandledForStreamRetry: [String] = []

    init(configuration: StreamTextConfiguration<OutputValue, PartialOutput>, maxRetries: Int) {
        self.configuration = configuration
        self.maxRetries = maxRetries
        self.streamRetries = configuration.streamRetries ?? 0
        self.canRetryStreamViaOnError = configuration.streamRetries != nil && configuration.onError != nil
        self.dispatcher = TelemetryDispatcher(telemetry: configuration.telemetry)
        self.callId = configuration.internalOptions.generateCallId()
        self.runtimeContext = configuration.runtimeContext
        self.toolsContext = configuration.toolsContext
        self.currentStepModel = ModelInfo(provider: configuration.model.provider, modelId: configuration.model.modelId)

        let timeout = configuration.settings.timeout
        let hasTimeouts = [
            getTotalTimeoutMs(timeout), getStepTimeoutMs(timeout),
            getFirstChunkTimeoutMs(timeout), getChunkTimeoutMs(timeout),
        ].contains { $0 != nil }

        if configuration.settings.abortSignal != nil || hasTimeouts {
            let controller = StreamAbortController()
            abortController = controller
            abortSignal = { controller.isAborted }
            abortWatcher = configuration.settings.abortSignal.map {
                AbortSignalWatcher(signal: $0, controller: controller)
            }
            stepTimer = getStepTimeoutMs(timeout).map { _ in AbortTimer(controller: controller, label: "Step") }
            firstChunkTimer = getFirstChunkTimeoutMs(timeout).map { _ in AbortTimer(controller: controller, label: "First chunk") }
            chunkTimer = getChunkTimeoutMs(timeout).map { _ in AbortTimer(controller: controller, label: "Chunk") }
            if let totalTimeoutMs = getTotalTimeoutMs(timeout) {
                AbortTimer(controller: controller, label: "Total").arm(totalTimeoutMs)
            }
        } else {
            abortController = nil
            abortSignal = nil
            abortWatcher = nil
            stepTimer = nil
            firstChunkTimer = nil
            chunkTimer = nil
        }

        let pumpStarter = PumpStarter()
        self.replay = ReplayBuffer(onStart: { pumpStarter.start() })
        pumpStarter.engine = { [unowned self] in self.startPump() }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: Promises

    func rejectResultPromises(_ error: any Error) {
        for reject in [
            { if self.finishReason.isPending() { self.finishReason.reject(error) } },
            { if self.rawFinishReason.isPending() { self.rawFinishReason.reject(error) } },
            { if self.totalUsage.isPending() { self.totalUsage.reject(error) } },
            { if self.steps.isPending() { self.steps.reject(error) } },
            { if self.initialResponseMessages.isPending() { self.initialResponseMessages.reject(error) } },
        ] {
            reject()
        }
    }

    // MARK: Start

    func start() {
        abortController?.onAbort { [weak self] reason in
            guard let self else { return }
            // Result promises settle before any potentially stalled callback.
            self.rejectResultPromises(reason ?? CancellationError())
            self.stitcher.terminate()
            self.stepTimer?.clear()
            self.firstChunkTimer?.clear()
            self.chunkTimer?.clear()
        }

        Task { await self.run() }
    }

    private func startPump() {
        let shouldStart: Bool = withLock {
            let start = !pumpStarted
            pumpStarted = true
            return start
        }
        guard shouldStart else { return }

        let stream = processedStream()
        Task {
            do {
                for try await part in stream {
                    self.replay.append(part)
                }
                self.replay.finish()
            } catch {
                self.replay.finish(throwing: error)
            }
            self.abortWatcher?.stop()
        }
    }

    // MARK: Setup and step loop

    private func run() async {
        do {
            let initialPrompt = try standardizePrompt(Prompt(
                instructions: configuration.instructions,
                system: configuration.system,
                allowSystemInMessages: configuration.allowSystemInMessages,
                prompt: configuration.prompt.map(PromptContent.text),
                messages: configuration.messages
            ))

            let callSettings = try configuration.settings.languageModelCallOptions.prepared()
            withLock { instructionsForNextStep = initialPrompt.instructions }

            let startEvent = GenerateTextStartEvent(
                callId: callId,
                operationId: "ai.streamText",
                provider: configuration.model.provider,
                modelId: configuration.model.modelId,
                instructions: initialPrompt.instructions,
                messages: initialPrompt.messages,
                tools: configuration.tools,
                toolChoice: configuration.toolChoice,
                activeTools: configuration.activeTools,
                toolOrder: configuration.toolOrder,
                callOptions: callSettings,
                maxRetries: maxRetries,
                timeout: configuration.settings.timeout,
                headers: configuration.settings.headers,
                providerOptions: configuration.providerOptions,
                output: configuration.output,
                toolsContext: configuration.toolsContext,
                runtimeContext: configuration.runtimeContext
            )
            await notify(
                invoke(configuration.onStart, with: startEvent),
                { await self.dispatcher.onStart(.generateText(startEvent)) }
            )

            try await runInitialToolApprovals(initialMessages: initialPrompt.messages)
            initialResponseMessages.resolve(withLock { initialResponses })

            try await streamStep(
                stepNumber: 0,
                usage: LanguageModelUsage(),
                initialPrompt: initialPrompt,
                callSettings: callSettings
            )
        } catch {
            await dispatcher.onError(callId: callId, error: error)
            if initialResponseMessages.isPending() {
                initialResponseMessages.reject(error)
            }
            stitcher.addStream(AsyncThrowingStream { continuation in
                continuation.yield(.part(.error(error)))
                continuation.finish()
            })
            stitcher.close()
        }
    }

    /// Executes approved tool calls and reports denied ones before the first step.
    private func runInitialToolApprovals(initialMessages: [ModelMessage]) async throws {
        let collected = try collectToolApprovals(messages: initialMessages)
        guard !collected.deniedToolApprovals.isEmpty || !collected.approvedToolApprovals.isEmpty else {
            return
        }

        let (runtimeContext, toolsContext) = withLock { (self.runtimeContext, self.toolsContext) }
        let tools = configuration.tools

        let validated = try await validateApprovedToolApprovals(
            collected.approvedToolApprovals.filter { $0.toolCall.providerExecuted != true },
            tools: tools,
            toolApproval: configuration.toolApproval,
            messages: initialMessages,
            toolsContext: toolsContext,
            runtimeContext: runtimeContext,
            toolApprovalSecret: configuration.toolApprovalSecret,
            refineToolInput: configuration.refineToolInput
        )

        let localDenied = collected.deniedToolApprovals.filter { $0.toolCall.providerExecuted != true } + validated.denied
        let localDeniedWithoutResults = localDenied.filter { $0.existingToolResult == nil }
        let deniedProviderExecuted = collected.deniedToolApprovals.filter { $0.toolCall.providerExecuted == true }

        let (stream, continuation) = AsyncThrowingStream<InternalStreamPart, Error>.makeStream()
        stitcher.addStream(stream)
        defer { continuation.finish() }

        for approval in localDenied + deniedProviderExecuted {
            continuation.yield(.part(.toolOutputDenied(ToolOutputDenied(
                toolCallId: approval.toolCall.toolCallId,
                toolName: approval.toolCall.toolName
            ))))
        }

        for invalid in validated.invalid {
            let toolCall = invalid.approval.toolCall
            let error = InvalidToolCallMessageError(message: AISDKProvider.getErrorMessage(invalid.error))
            continuation.yield(.part(.toolError(toolCall.isDynamic
                ? .dynamic(DynamicToolError(
                    toolCallId: toolCall.toolCallId, toolName: toolCall.toolName, title: toolCall.title,
                    input: toolCall.input, error: error, toolMetadata: toolCall.toolMetadata
                ))
                : .static(StaticToolError(
                    toolCallId: toolCall.toolCallId, toolName: toolCall.toolName, title: toolCall.title,
                    input: toolCall.input, error: error, toolMetadata: toolCall.toolMetadata
                ))
            )))
        }

        let outputs = try await mapWithConcurrency(
            validated.approved,
            concurrency: configuration.toolCallConcurrency,
            abortSignal: abortSignal
        ) { approval, _ -> ToolOutput? in
            let result = try await executeToolCall(
                toolCall: approval.toolCall,
                tools: tools,
                toolsContext: toolsContext,
                callId: self.callId,
                messages: initialMessages,
                abortSignal: self.abortSignal,
                timeout: self.configuration.settings.timeout,
                telemetry: self.dispatcher,
                onToolExecutionStart: self.configuration.onToolExecutionStart,
                onToolExecutionEnd: self.configuration.onToolExecutionEnd,
                onPreliminaryToolResult: { continuation.yield(.part(.toolResult($0))) }
            )
            if let output = result?.output {
                continuation.yield(.part(output.streamPart))
            }
            return result?.output
        }.compactMap { $0 }

        guard !outputs.isEmpty || !localDeniedWithoutResults.isEmpty || !validated.invalid.isEmpty else {
            return
        }

        var toolContent: [ToolContentPart] = []
        for output in outputs {
            let isError: Bool
            let value: Any?
            switch output {
            case .result(let result):
                isError = false
                value = result.output
            case .error(let error):
                isError = true
                value = error.error
            }
            toolContent.append(.toolResult(ToolResultPart(
                toolCallId: output.toolCallId,
                toolName: output.toolName,
                output: try await createToolModelOutput(
                    toolCallId: output.toolCallId,
                    input: output.input,
                    output: value,
                    tool: tools?[output.toolName],
                    errorMode: isError ? .text : .none
                )
            )))
        }

        // Invalid approved calls are reported to the model without executing them:
        // repairing the input after approval would change the authorized operation.
        for invalid in validated.invalid {
            let toolCall = invalid.approval.toolCall
            toolContent.append(.toolResult(ToolResultPart(
                toolCallId: toolCall.toolCallId,
                toolName: toolCall.toolName,
                output: try await createToolModelOutput(
                    toolCallId: toolCall.toolCallId,
                    input: toolCall.input,
                    output: invalid.error,
                    tool: tools?[toolCall.toolName],
                    errorMode: .text
                )
            )))
        }

        for denied in localDeniedWithoutResults {
            toolContent.append(.toolResult(ToolResultPart(
                toolCallId: denied.toolCall.toolCallId,
                toolName: denied.toolCall.toolName,
                output: .executionDenied(reason: denied.approvalResponse.reason)
            )))
        }

        withLock { initialResponses.append(.tool(ToolModelMessage(content: toolContent))) }
    }

    /// Prepares a step, starts its model call, and adds its stream to the stitched stream.
    private func streamStep(
        stepNumber: Int,
        usage: LanguageModelUsage,
        initialPrompt: StandardizedPrompt,
        callSettings: LanguageModelCallOptions
    ) async throws {
        let stepTimeoutMs = getStepTimeoutMs(configuration.settings.timeout)
        stepTimer?.arm(stepTimeoutMs)

        do {
            let stepFinish = DelayedPromise<Void>()
            let (recordedSteps, initialResponses, stepInputMessages, instructions, runtimeContext, toolsContext) = withLock {
                self.stepFinish = stepFinish
                return (
                    self.recordedSteps,
                    self.initialResponses,
                    self.stepMessagesForNextStep ?? (initialPrompt.messages + self.initialResponses.map { $0.modelMessage }),
                    self.instructionsForNextStep,
                    self.runtimeContext,
                    self.toolsContext
                )
            }

            let prepareStepResult = try await configuration.prepareStep?(PrepareStepOptions(
                steps: recordedSteps,
                stepNumber: recordedSteps.count,
                model: configuration.modelArgument,
                instructions: instructions,
                initialInstructions: initialPrompt.instructions,
                messages: stepInputMessages,
                initialMessages: initialPrompt.messages,
                responseMessages: initialResponses + recordedSteps.flatMap(\.response.messages),
                toolsContext: toolsContext,
                runtimeContext: runtimeContext
            ))

            let stepRuntimeContext = prepareStepResult?.runtimeContext ?? runtimeContext
            let stepToolsContext = prepareStepResult?.toolsContext ?? toolsContext
            let stepModel = try prepareStepResult?.model.map(resolveLanguageModelV4) ?? configuration.model
            let stepActiveTools = prepareStepResult?.activeTools ?? configuration.activeTools
            let stepExecutionTools = filterActiveTools(configuration.tools, activeTools: stepActiveTools)
            let stepToolOrder = prepareStepResult?.toolOrder ?? configuration.toolOrder
            let stepToolChoice = prepareStepResult?.toolChoice ?? configuration.toolChoice
            let stepMessages = prepareStepResult?.messages ?? stepInputMessages
            let stepInstructions = prepareStepResult?.resolvedInstructions ?? instructions
            let stepProviderOptions = mergeProviderOptions(configuration.providerOptions, prepareStepResult?.providerOptions)
            let stepCallSettings = try callSettings.overridden(by: prepareStepResult?.callOptions)

            withLock {
                self.runtimeContext = stepRuntimeContext
                self.toolsContext = stepToolsContext
                self.currentStepModel = ModelInfo(provider: stepModel.provider, modelId: stepModel.modelId)
                self.currentStepMessages = stepMessages
                self.instructionsForNextStep = stepInstructions
            }

            let stepStartTimestampMs = configuration.internalOptions.now()
            let responseFormat = try await configuration.output.responseFormat()
            let retry = try prepareRetries(maxRetries: maxRetries, abortSignal: abortSignal).retry
            let notifiedStepStart = OnceFlag()

            let callLanguageModel: @Sendable () async throws -> LanguageModelCallStream = { [self] in
                try await retry.call { [self] in
                    try await streamLanguageModelCall(
                        model: stepModel,
                        tools: stepExecutionTools,
                        toolOrder: stepToolOrder,
                        responseFormat: responseFormat,
                        toolChoice: stepToolChoice,
                        instructions: stepInstructions,
                        messages: stepMessages,
                        download: configuration.download,
                        abortSignal: abortSignal,
                        headers: withUserAgentSuffix(configuration.settings.headers ?? [:], "ai/\(VERSION)"),
                        includeRawChunks: configuration.include.rawChunks ?? false,
                        providerOptions: stepProviderOptions,
                        repairToolCall: configuration.repairToolCall,
                        refineToolInput: configuration.refineToolInput,
                        callId: callId,
                        toolsContext: stepToolsContext,
                        callOptions: stepCallSettings,
                        telemetry: dispatcher,
                        generateId: configuration.internalOptions.generateId,
                        now: configuration.internalOptions.now,
                        onStart: { promptMessages, stepTools, preparedToolChoice in
                            guard notifiedStepStart.claim() else { return }
                            let event = GenerateTextStepStartEvent(
                                callId: self.callId,
                                provider: stepModel.provider,
                                modelId: stepModel.modelId,
                                stepNumber: recordedSteps.count,
                                instructions: stepInstructions,
                                messages: stepMessages,
                                tools: self.configuration.tools,
                                toolChoice: stepToolChoice,
                                activeTools: stepActiveTools,
                                toolOrder: stepToolOrder,
                                steps: recordedSteps,
                                providerOptions: stepProviderOptions,
                                output: self.configuration.output,
                                runtimeContext: stepRuntimeContext,
                                toolsContext: stepToolsContext,
                                promptMessages: promptMessages,
                                stepTools: stepTools,
                                stepToolChoice: preparedToolChoice
                            )
                            await notify(
                                invoke(self.configuration.onStepStart, with: event),
                                { await self.dispatcher.onStepStart(event) }
                            )
                        },
                        onLanguageModelCallStart: configuration.onLanguageModelCallStart,
                        onLanguageModelCallEnd: configuration.onLanguageModelCallEnd
                    )
                }
            }

            let initialCall = try await callLanguageModel()

            let step = StreamStepState(
                stepNumber: stepNumber,
                usage: usage,
                stepStartTimestampMs: stepStartTimestampMs,
                stepModel: ModelInfo(provider: stepModel.provider, modelId: stepModel.modelId),
                stepMessages: stepMessages,
                stepExecutionTools: stepExecutionTools,
                stepToolsContext: stepToolsContext,
                stepRuntimeContext: stepRuntimeContext,
                stepFinish: stepFinish,
                initialCall: initialCall,
                generateId: configuration.internalOptions.generateId,
                currentDate: configuration.internalOptions.currentDate
            )

            firstChunkTimer?.arm(getFirstChunkTimeoutMs(configuration.settings.timeout))

            let modelStream = retryingModelStream(step: step, callLanguageModel: callLanguageModel)
            let withToolCallbacks = invokeToolCallbacks(
                modelStream,
                tools: stepExecutionTools,
                messages: stepMessages,
                toolsContext: stepToolsContext
            )
            let withToolResults = executeTools(
                withToolCallbacks,
                tools: stepExecutionTools,
                messages: stepMessages,
                toolsContext: stepToolsContext,
                runtimeContext: stepRuntimeContext
            )

            stitcher.addStream(pullTransformLive(
                withToolResults,
                transform: { [self] part, emit in self.processStepPart(part, step: step, emit: emit) },
                flush: { [self] emit in
                    try await self.finishStep(
                        step: step,
                        emit: emit,
                        initialPrompt: initialPrompt,
                        callSettings: callSettings
                    )
                }
            ))
        } catch {
            clearStepTimers()
            throw error
        }
    }

    private func clearStepTimers() {
        stepTimer?.clear()
        firstChunkTimer?.clear()
        chunkTimer?.clear()
    }

    // MARK: Model stream with retries

    /**
     Reads the model stream of a step, retrying failed streams.

     Port of the `languageModelStream` of `streamStep` in `stream-text.ts`: tool
     parts are buffered while a retry is possible, open text and reasoning parts
     are closed before a retry, and each retry attempt starts with a boundary.
     First-content and chunk timeouts are tracked on semantic output.
     */
    private func retryingModelStream(
        step: StreamStepState,
        callLanguageModel: @escaping @Sendable () async throws -> LanguageModelCallStream
    ) -> AsyncThrowingStream<StepStreamPart, Error> {
        let reader = RetryingStreamReader(stream: step.initialCall.stream)
        let shouldBufferToolParts = streamRetries > 0 || canRetryStreamViaOnError

        return pullTransform(AsyncThrowingStream(unfolding: { [self] () async throws -> [StepStreamPart]? in
            var output: [StepStreamPart] = []

            func enqueueAttemptPart(_ part: StepStreamPart) {
                if case .part(let textPart) = part {
                    switch textPart {
                    case .textStart(let id, _): reader.openTextParts.append(id)
                    case .textEnd(let id, _, _): reader.openTextParts.removeAll { $0 == id }
                    case .reasoningStart(let id, _): reader.openReasoningParts.append(id)
                    case .reasoningEnd(let id, _): reader.openReasoningParts.removeAll { $0 == id }
                    default: break
                    }
                }
                output.append(part)
            }

            func flushBuffered() {
                let buffered = reader.buffered
                reader.buffered = []
                buffered.forEach(enqueueAttemptPart)
            }

            if reader.done {
                return nil
            }

            while true {
                let value: StepStreamPart?
                do {
                    value = try await reader.next()
                } catch {
                    firstChunkTimer?.clear()
                    chunkTimer?.clear()
                    throw error
                }

                if reader.enqueueBoundary {
                    var warnings: [CallWarning] = []
                    if case .modelCallStart(let startWarnings)? = value {
                        warnings = startWarnings
                    }
                    output.append(.retryAttemptBoundary(warnings: warnings))
                    reader.enqueueBoundary = false
                }

                guard let value else {
                    firstChunkTimer?.clear()
                    chunkTimer?.clear()
                    flushBuffered()
                    reader.done = true
                    return output
                }

                if case .modelCallEnd = value {
                    firstChunkTimer?.clear()
                    chunkTimer?.clear()
                    flushBuffered()
                    enqueueAttemptPart(value)
                    return output
                }

                // Observe model output before buffering; replaying buffered parts must not re-arm timers.
                if value.isOutputChunk {
                    firstChunkTimer?.clear()
                    chunkTimer?.arm(getChunkTimeoutMs(configuration.settings.timeout))
                }

                let isError: Bool
                let isToolPart: Bool
                if case .part(let part) = value {
                    if case .error = part { isError = true } else { isError = false }
                    switch part {
                    case .toolInputStart, .toolInputDelta, .toolInputEnd, .toolCall,
                         .toolApprovalRequest, .toolApprovalResponse, .toolResult, .toolError:
                        isToolPart = true
                    default:
                        isToolPart = false
                    }
                } else {
                    isError = false
                    isToolPart = false
                }

                if shouldBufferToolParts, !isError, isToolPart || !reader.buffered.isEmpty {
                    reader.buffered.append(value)
                    continue
                }

                if !isError {
                    enqueueAttemptPart(value)
                    return output
                }

                guard case .part(.error(let rawError)) = value else { return output }

                firstChunkTimer?.clear()
                chunkTimer?.clear()
                await notify(invoke(configuration.onChunk, with: TextStreamPart.error(rawError)))

                let error = (wrapGatewayError(rawError) as? Error) ?? rawError
                let isToolChoiceViolation = ToolChoiceViolationError.isInstance(error)
                let onErrorResult = try? await configuration.onError?(error)
                let callbackRequestedRetry = canRetryStreamViaOnError && onErrorResult?.retry == true
                let automaticRetry = !isToolChoiceViolation && reader.automaticRetryCount < streamRetries
                let callbackRetry = !isToolChoiceViolation && !automaticRetry
                    && callbackRequestedRetry && reader.callbackRetryCount < 1

                if !automaticRetry && !callbackRetry {
                    flushBuffered()
                    withLock { errorsHandledForStreamRetry.append(errorIdentity(rawError)) }
                    output.append(value)
                    return output
                }

                if automaticRetry {
                    reader.automaticRetryCount += 1
                } else {
                    reader.callbackRetryCount += 1
                }

                reader.buffered = []
                for id in reader.openTextParts {
                    output.append(.part(.textEnd(id: id, providerMetadata: nil)))
                }
                reader.openTextParts = []
                for id in reader.openReasoningParts {
                    output.append(.part(.reasoningEnd(id: id, providerMetadata: nil)))
                }
                reader.openReasoningParts = []

                let retryCall: LanguageModelCallStream
                do {
                    retryCall = try await callLanguageModel()
                } catch {
                    output.append(.part(.error(error)))
                    reader.done = true
                    return output
                }
                step.request = retryCall.request
                step.response = retryCall.response
                reader.replace(stream: retryCall.stream)
                firstChunkTimer?.arm(getFirstChunkTimeoutMs(configuration.settings.timeout))
                reader.enqueueBoundary = true
            }
        })) { $0 }
    }

    // MARK: Tool callbacks

    /**
     Calls the tools' input lifecycle callbacks.

     Port of `@ai-sdk/ai/src/generate-text/invoke-tool-callbacks-from-stream.ts`.
     */
    private func invokeToolCallbacks(
        _ stream: AsyncThrowingStream<StepStreamPart, Error>,
        tools: ToolSet?,
        messages: [ModelMessage],
        toolsContext: ToolsContext
    ) -> AsyncThrowingStream<StepStreamPart, Error> {
        guard let tools else { return stream }
        let state = ToolCallbackState()
        let abortSignal = self.abortSignal

        @Sendable func validatedContext(toolCallId: String, toolName: String) async throws -> Context? {
            if let cached = state.validatedContexts[toolCallId]?[toolName] {
                return cached
            }
            let context = try await validateToolContext(
                toolName: toolName,
                context: toolsContext[toolName],
                contextSchema: tools[toolName]?.contextSchema
            )
            if state.ongoingToolNames[toolCallId] != nil {
                state.validatedContexts[toolCallId, default: [:]][toolName] = .some(context)
            }
            return context
        }

        return pullTransform(stream) { part in
            switch part {
            case .retryAttemptBoundary:
                state.ongoingToolNames = [:]
                state.validatedContexts = [:]

            case .part(.toolInputStart(let id, let toolName, _, _, _, _, _, _)):
                state.ongoingToolNames[id] = toolName
                state.validatedContexts[id] = [:]
                if let onInputStart = tools[toolName]?.onInputStart {
                    try await onInputStart(ToolExecutionOptions(
                        toolCallId: id,
                        messages: messages,
                        abortSignal: abortSignal,
                        context: try await validatedContext(toolCallId: id, toolName: toolName)
                    ))
                }

            case .part(.toolInputDelta(let id, let delta, _)):
                if let toolName = state.ongoingToolNames[id], let onInputDelta = tools[toolName]?.onInputDelta {
                    try await onInputDelta(ToolCallDeltaOptions(
                        inputTextDelta: delta,
                        toolCallId: id,
                        messages: messages,
                        abortSignal: abortSignal,
                        context: try await validatedContext(toolCallId: id, toolName: toolName)
                    ))
                }

            case .part(.toolCall(let toolCall)):
                if toolCall.invalid != true, let onInputAvailable = tools[toolCall.toolName]?.onInputAvailable {
                    let context = try await validatedContext(toolCallId: toolCall.toolCallId, toolName: toolCall.toolName)
                    state.ongoingToolNames[toolCall.toolCallId] = nil
                    state.validatedContexts[toolCall.toolCallId] = nil
                    try await onInputAvailable(ToolCallInputOptions(
                        input: toolCall.input,
                        toolCallId: toolCall.toolCallId,
                        messages: messages,
                        abortSignal: abortSignal,
                        context: context
                    ))
                } else {
                    state.ongoingToolNames[toolCall.toolCallId] = nil
                    state.validatedContexts[toolCall.toolCallId] = nil
                }

            default:
                break
            }
            return [part]
        }
    }

    // MARK: Tool execution

    /**
     Resolves tool approvals and executes client tool calls when the model call ends.

     Port of `@ai-sdk/ai/src/generate-text/execute-tools-from-stream.ts`.
     */
    private func executeTools(
        _ stream: AsyncThrowingStream<StepStreamPart, Error>,
        tools: ToolSet?,
        messages: [ModelMessage],
        toolsContext: ToolsContext,
        runtimeContext: Context
    ) -> AsyncThrowingStream<StepStreamPart, Error> {
        let pending = PendingToolCalls()

        return pullTransformLive(stream) { [self] part, emit in
            emit(part)

            switch part {
            case .retryAttemptBoundary:
                pending.calls = []

            case .part(.toolCall(let toolCall)):
                guard toolCall.invalid != true, let tool = tools?[toolCall.toolName] else { return }

                let status = try await resolveToolApproval(
                    tools: tools,
                    toolCall: toolCall,
                    toolApproval: configuration.toolApproval,
                    messages: messages,
                    toolsContext: toolsContext,
                    runtimeContext: runtimeContext
                )

                // Tools without approval must not consume an approval id, keeping id sequences stable.
                if status == .notApplicable {
                    if tool.execute != nil, toolCall.providerExecuted != true {
                        pending.calls.append(toolCall)
                    }
                    return
                }

                let approvalId = configuration.internalOptions.generateId()
                let signature = try maybeSignApproval(
                    secret: configuration.toolApprovalSecret,
                    approvalId: approvalId,
                    toolCall: toolCall
                )

                switch status {
                case .userApproval(let reason):
                    emit(.part(.toolApprovalRequest(ToolApprovalRequestOutput(
                        approvalId: approvalId, toolCall: toolCall, reason: reason, signature: signature
                    ))))
                    return

                case .denied(let reason):
                    emit(.part(.toolApprovalRequest(ToolApprovalRequestOutput(
                        approvalId: approvalId, toolCall: toolCall, isAutomatic: true, signature: signature
                    ))))
                    emit(.part(.toolApprovalResponse(ToolApprovalResponseOutput(
                        approvalId: approvalId, toolCall: toolCall, approved: false,
                        reason: reason, providerExecuted: toolCall.providerExecuted
                    ))))
                    emit(.part(.toolOutputDenied(ToolOutputDenied(
                        toolCallId: toolCall.toolCallId, toolName: toolCall.toolName
                    ))))
                    return

                case .approved(let reason):
                    emit(.part(.toolApprovalRequest(ToolApprovalRequestOutput(
                        approvalId: approvalId, toolCall: toolCall, isAutomatic: true, signature: signature
                    ))))
                    emit(.part(.toolApprovalResponse(ToolApprovalResponseOutput(
                        approvalId: approvalId, toolCall: toolCall, approved: true,
                        reason: reason, providerExecuted: toolCall.providerExecuted
                    ))))

                case .notApplicable:
                    break
                }

                if tool.execute != nil, toolCall.providerExecuted != true {
                    pending.calls.append(toolCall)
                }

            case .modelCallEnd(let finishReason, _, _, _, _):
                guard isToolExecutionAllowedFinishReason(finishReason) else { return }

                _ = try await mapWithConcurrency(
                    pending.calls,
                    concurrency: configuration.toolCallConcurrency,
                    abortSignal: abortSignal
                ) { toolCall, _ in
                    do {
                        let result = try await executeToolCall(
                            toolCall: toolCall,
                            tools: tools,
                            toolsContext: toolsContext,
                            callId: self.callId,
                            messages: messages,
                            abortSignal: self.abortSignal,
                            timeout: self.configuration.settings.timeout,
                            telemetry: self.dispatcher,
                            onToolExecutionStart: self.configuration.onToolExecutionStart,
                            onToolExecutionEnd: self.configuration.onToolExecutionEnd,
                            onPreliminaryToolResult: { emit(.part(.toolResult($0))) }
                        )
                        if let result {
                            emit(.toolExecutionEnd(toolCallId: result.output.toolCallId, toolExecutionMs: result.toolExecutionMs))
                            emit(.part(result.output.streamPart))
                        }
                    } catch {
                        emit(.part(.error(error)))
                    }
                }

            default:
                break
            }
        }
    }

    // MARK: Step output

    /// Converts step parts to public parts. Port of the step transform of `streamStep` in `stream-text.ts`.
    private func processStepPart(_ part: StepStreamPart, step: StreamStepState, emit: @Sendable (InternalStreamPart) -> Void) {
        switch part {
        case .retryAttemptBoundary(let warnings):
            step.resetForRetry(warnings: warnings)
            emit(.retryBoundary(request: stepRequest(step), warnings: warnings))
            return

        case .modelCallStart(let warnings):
            step.warnings = warnings
            return

        default:
            break
        }

        if step.isFirstChunk {
            step.isFirstChunk = false
            emit(.part(.startStep(request: stepRequest(step), warnings: step.warnings ?? [])))
        }

        if part.isOutputChunk {
            step.hasReceivedOutputChunk = true
        }

        switch part {
        case .part(let textPart):
            switch textPart {
            case .file, .custom, .source, .reasoningFile, .toolInputStart, .toolInputEnd, .toolInputDelta,
                 .toolApprovalRequest, .toolOutputDenied:
                emit(.part(textPart))

            case .textStart(let id, let metadata):
                let uniqueId = reservePartId(id, reasoning: false)
                step.textPartIds[id] = uniqueId
                emit(.part(.textStart(id: uniqueId, providerMetadata: metadata)))

            case .textDelta(let id, let text, let metadata):
                if !text.isEmpty || metadata != nil {
                    emit(.part(.textDelta(id: step.textPartIds[id] ?? id, text: text, providerMetadata: metadata)))
                }

            case .textEnd(let id, let metadata, let citations):
                emit(.part(.textEnd(id: step.textPartIds[id] ?? id, providerMetadata: metadata, citations: citations)))
                step.textPartIds[id] = nil

            case .reasoningStart(let id, let metadata):
                let uniqueId = reservePartId(id, reasoning: true)
                step.reasoningPartIds[id] = uniqueId
                emit(.part(.reasoningStart(id: uniqueId, providerMetadata: metadata)))

            case .reasoningDelta(let id, let text, let metadata):
                emit(.part(.reasoningDelta(id: step.reasoningPartIds[id] ?? id, text: text, providerMetadata: metadata)))

            case .reasoningEnd(let id, let metadata):
                emit(.part(.reasoningEnd(id: step.reasoningPartIds[id] ?? id, providerMetadata: metadata)))
                step.reasoningPartIds[id] = nil

            case .toolCall(let toolCall):
                emit(.part(textPart))
                step.toolCalls.append(toolCall)

            case .toolApprovalResponse(let response):
                emit(.part(textPart))
                step.toolApprovalResponses.append(response)

            case .toolResult(let result):
                emit(.part(textPart))
                if result.preliminary != true {
                    step.toolOutputs.append(.result(result))
                }

            case .toolError(let error):
                emit(.part(textPart))
                step.toolOutputs.append(.error(error))

            case .error:
                step.hasReceivedTerminalChunk = true
                emit(.part(textPart))
                step.finishReason = .error

            case .raw:
                if configuration.include.rawChunks == true {
                    emit(.part(textPart))
                }

            case .startStep, .finishStep, .start, .finish, .abort:
                break
            }

        case .toolExecutionEnd(let toolCallId, let toolExecutionMs):
            step.toolExecutionMs[toolCallId] = toolExecutionMs

        case .modelCallResponseMetadata(let id, let timestamp, let modelId):
            step.responseId = id ?? step.responseId
            step.responseTimestamp = timestamp ?? step.responseTimestamp
            step.responseModelId = modelId ?? step.responseModelId

        case .modelCallEnd(let finishReason, let rawFinishReason, let usage, let providerMetadata, let performance):
            step.hasReceivedTerminalChunk = true
            step.usage = usage
            step.finishReason = finishReason
            step.rawFinishReason = rawFinishReason
            step.providerMetadata = providerMetadata
            step.modelCallPerformance = performance

        case .modelCallStart, .retryAttemptBoundary:
            break
        }
    }

    private func stepRequest(_ step: StreamStepState) -> LanguageModelRequestMetadata {
        LanguageModelRequestMetadata(
            messages: configuration.include.requestMessages == true ? step.stepMessages : nil,
            body: configuration.include.requestBody == true
                ? step.request?.body.flatMap { try? jsonValue(from: $0) }
                : nil
        )
    }

    /// Provider part ids are unique only within one model call; colliding ids get a generated id.
    private func reservePartId(_ id: String, reasoning: Bool) -> String {
        withLock {
            var used = reasoning ? usedReasoningPartIds : usedTextPartIds
            defer {
                if reasoning { usedReasoningPartIds = used } else { usedTextPartIds = used }
            }
            if !used.contains(id) {
                used.insert(id)
                return id
            }
            let generated = configuration.internalOptions.generateId()
            var uniqueId = generated
            var suffix = 0
            while used.contains(uniqueId) {
                suffix += 1
                uniqueId = "\(generated)-\(suffix)"
            }
            used.insert(uniqueId)
            return uniqueId
        }
    }

    /// Emits `finish-step`, waits for the step to be recorded, then continues or finishes.
    private func finishStep(
        step: StreamStepState,
        emit: @escaping @Sendable (InternalStreamPart) -> Void,
        initialPrompt: StandardizedPrompt,
        callSettings: LanguageModelCallOptions
    ) async throws {
        // An incomplete model stream without output is an error, not an empty step.
        if !step.hasReceivedTerminalChunk && !step.hasReceivedOutputChunk {
            emit(.part(.error(NoOutputGeneratedError(
                message: "No output generated. The model stream ended without a finish chunk."
            ))))
            clearStepTimers()
            stitcher.close()
            return
        }

        let performance = StepResultPerformance(
            effectiveOutputTokensPerSecond: step.modelCallPerformance.effectiveOutputTokensPerSecond,
            outputTokensPerSecond: step.modelCallPerformance.outputTokensPerSecond,
            inputTokensPerSecond: step.modelCallPerformance.inputTokensPerSecond,
            effectiveTotalTokensPerSecond: step.modelCallPerformance.effectiveTotalTokensPerSecond,
            stepTimeMs: configuration.internalOptions.now() - step.stepStartTimestampMs,
            responseTimeMs: step.modelCallPerformance.responseTimeMs,
            toolExecutionMs: step.toolExecutionMs,
            timeToFirstOutputMs: step.modelCallPerformance.timeToFirstOutputMs,
            timeBetweenOutputChunksMs: step.modelCallPerformance.timeBetweenOutputChunksMs
        )

        emit(.part(.finishStep(
            response: LanguageModelResponseMetadata(
                id: step.responseId,
                timestamp: step.responseTimestamp,
                modelId: step.responseModelId,
                headers: step.response?.headers
            ),
            usage: step.usage,
            performance: performance,
            finishReason: step.finishReason,
            rawFinishReason: step.rawFinishReason,
            providerMetadata: step.providerMetadata
        )))

        let combinedUsage = addLanguageModelUsage(step.baseUsage, step.usage)

        // The event processor records the step before the continuation is decided.
        try await step.stepFinish.task.value

        let clientToolCalls = step.toolCalls.filter { $0.providerExecuted != true }
        let clientToolOutputs = step.toolOutputs.filter { $0.providerExecuted != true }
        let deniedResponses = step.toolApprovalResponses.filter { !$0.approved }

        let (pendingDeferred, recordedSteps): ([String: String], [StepResult]) = withLock {
            for toolCall in step.toolCalls where toolCall.providerExecuted == true {
                guard let tool = step.stepExecutionTools?[toolCall.toolName],
                      tool.type == .provider, tool.supportsDeferredResults == true else { continue }
                if !step.toolOutputs.contains(where: { $0.toolCallId == toolCall.toolCallId }) {
                    pendingDeferredToolCalls[toolCall.toolCallId] = toolCall.toolName
                }
            }
            for output in step.toolOutputs {
                pendingDeferredToolCalls[output.toolCallId] = nil
            }
            return (pendingDeferredToolCalls, self.recordedSteps)
        }

        clearStepTimers()

        var shouldContinue = clientToolCalls.count == clientToolOutputs.count + deniedResponses.count
            && (!clientToolCalls.isEmpty || !pendingDeferred.isEmpty)
        if shouldContinue {
            shouldContinue = try await !isStopConditionMet(stopConditions: configuration.stopWhen, steps: recordedSteps)
        }

        if shouldContinue {
            do {
                try await streamStep(
                    stepNumber: step.stepNumber + 1,
                    usage: combinedUsage,
                    initialPrompt: initialPrompt,
                    callSettings: callSettings
                )
            } catch {
                emit(.part(.error(error)))
                stitcher.close()
            }
        } else {
            emit(.part(.finish(
                finishReason: step.finishReason,
                rawFinishReason: step.rawFinishReason,
                totalUsage: combinedUsage
            )))
            stitcher.close()
        }
    }

    // MARK: Output pipeline

    private func processedStream() -> AsyncThrowingStream<EnrichedStreamPart<PartialOutput>, Error> {
        let abortable = abortableStream()
        let gated = StopGate()
        let gatedStream = pullTransform(abortable) { part in gated.isRunning ? [part] : [] }
        let transformed = applyTransforms(gatedStream, stopStream: { [self] in
            gated.isRunning = false
            stitcher.terminate()
        })
        let enriched = outputTransform(transformed)
        return eventProcessor(enriched)
    }

    /// Adds the `start` part and turns an abort into an `abort` part.
    private func abortableStream() -> AsyncThrowingStream<InternalStreamPart, Error> {
        let source = SharedIterator(stream: stitcher.stream)
        let state = AbortableState()

        return AsyncThrowingStream(unfolding: { [self] in
            if !state.started {
                state.started = true
                return .part(.start)
            }
            if state.done {
                return nil
            }

            do {
                let value = try await readUntilAbort(source)
                if abortController?.isAborted == true {
                    state.done = true
                    return await abortPart()
                }
                guard let value else {
                    state.done = true
                    return nil
                }
                return value
            } catch {
                if abortController?.isAborted == true {
                    state.done = true
                    return await abortPart()
                }
                state.done = true
                await dispatcher.onError(callId: callId, error: error)
                throw error
            }
        })
    }

    private func readUntilAbort(_ source: SharedIterator<InternalStreamPart>) async throws -> InternalStreamPart? {
        guard let controller = abortController else {
            return try await source.next()
        }
        return try await withThrowingTaskGroup(of: InternalStreamPart?.self) { group in
            group.addTask { try await source.next() }
            // The abort waiter must end on cancellation, or the group outlives the read.
            group.addTask {
                await controller.waitForAbort()
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func abortPart() async -> InternalStreamPart {
        let reason = abortController?.reason
        let steps = withLock {
            isAborted = true
            return recordedSteps
        }
        let event = GenerateTextAbortEvent(callId: callId, steps: steps, reason: reason)
        await notify(
            invoke(configuration.onAbort, with: event),
            { await self.dispatcher.onAbort(event) }
        )
        return .part(.abort(reason: reason.map { AISDKProvider.getErrorMessage($0) }))
    }

    /// Applies the user transforms to each retry attempt separately.
    private func applyTransforms(
        _ stream: AsyncThrowingStream<InternalStreamPart, Error>,
        stopStream: @escaping @Sendable () -> Void
    ) -> AsyncThrowingStream<InternalStreamPart, Error> {
        let transforms = configuration.transforms
        guard !transforms.isEmpty else { return stream }

        let source = SharedIterator(stream: stream)
        let state = TransformSegmentState()
        let options = StreamTextTransformOptions(tools: configuration.tools, stopStream: stopStream)

        @Sendable func makeSegment() -> AsyncThrowingStream<TextStreamPart, Error>.AsyncIterator {
            var segment = AsyncThrowingStream<TextStreamPart, Error>(unfolding: {
                guard !state.sourceDone else { return nil }
                guard let value = try await source.next() else {
                    state.sourceDone = true
                    return nil
                }
                switch value {
                case .part(let part):
                    return part
                case .retryBoundary:
                    state.pendingBoundary = value
                    return nil
                }
            })
            for transform in transforms {
                segment = transform(segment, options)
            }
            return segment.makeAsyncIterator()
        }

        return AsyncThrowingStream(unfolding: {
            while true {
                if state.segment == nil {
                    if state.sourceDone { return nil }
                    state.segment = makeSegment()
                }
                var segment = state.segment!
                let value = try await segment.next()
                state.segment = segment
                if let value {
                    return .part(value)
                }
                state.segment = nil
                if let boundary = state.pendingBoundary {
                    state.pendingBoundary = nil
                    return boundary
                }
                if state.sourceDone {
                    return nil
                }
            }
        })
    }

    /**
     Parses partial outputs from the first text part of each step.

     Port of `createOutputTransformStream` from `stream-text.ts`.
     */
    private func outputTransform(
        _ stream: AsyncThrowingStream<InternalStreamPart, Error>
    ) -> AsyncThrowingStream<InternalEnrichedPart<PartialOutput>, Error> {
        let output = configuration.output
        let state = OutputTransformState()

        @Sendable func publish(_ partialOutput: PartialOutput?) -> InternalEnrichedPart<PartialOutput> {
            let part = InternalEnrichedPart<PartialOutput>.enriched(EnrichedStreamPart(
                part: .textDelta(id: state.firstTextChunkId!, text: state.textChunk, providerMetadata: state.textProviderMetadata),
                partialOutput: partialOutput
            ))
            state.textChunk = ""
            return part
        }

        @Sendable func plain(_ part: TextStreamPart) -> InternalEnrichedPart<PartialOutput> {
            .enriched(EnrichedStreamPart(part: part, partialOutput: nil))
        }

        return pullTransform(stream) { value in
            guard case .part(let chunk) = value else {
                state.reset()
                if case .retryBoundary(let request, let warnings) = value {
                    return [.retryBoundary(request: request, warnings: warnings)]
                }
                return []
            }

            var results: [InternalEnrichedPart<PartialOutput>] = []

            if case .startStep = chunk {
                state.reset()
            }

            // Publish the last text chunk before the step finishes.
            if case .finishStep = chunk, !state.textChunk.isEmpty {
                results.append(publish(nil))
            }

            let textId: String
            switch chunk {
            case .textStart(let id, _), .textDelta(let id, _, _), .textEnd(let id, _, _):
                textId = id
            default:
                results.append(plain(chunk))
                return results
            }

            // The first text part of a step carries the output.
            if state.firstTextChunkId == nil {
                state.firstTextChunkId = textId
            } else if textId != state.firstTextChunkId {
                results.append(plain(chunk))
                return results
            }

            switch chunk {
            case .textStart:
                results.append(plain(chunk))
                return results

            case .textEnd:
                if !state.textChunk.isEmpty {
                    results.append(publish(nil))
                }
                results.append(plain(chunk))
                return results

            case .textDelta(_, let text, let metadata):
                state.text += text
                state.textChunk += text
                state.textProviderMetadata = metadata ?? state.textProviderMetadata

                if text.isEmpty && metadata != nil {
                    results.append(plain(chunk))
                    return results
                }

                if let partial = try await output.parsePartial(text: state.text) {
                    let currentValue = (partial as? String) ?? partialOutputKey(partial)
                    if !state.hasPublishedValue || currentValue != state.lastPublishedValue {
                        results.append(publish(partial))
                        state.lastPublishedValue = currentValue
                        state.hasPublishedValue = true
                    }
                }
                return results

            default:
                return results
            }
        }
    }

    /**
     Records content and steps, notifies chunk, error and step callbacks, and
     settles the result promises at the end.

     Port of the `eventProcessor` of `DefaultStreamTextResult` in `stream-text.ts`.
     */
    private func eventProcessor(
        _ stream: AsyncThrowingStream<InternalEnrichedPart<PartialOutput>, Error>
    ) -> AsyncThrowingStream<EnrichedStreamPart<PartialOutput>, Error> {
        let state = EventProcessorState()

        return pullTransform(stream, transform: { [self] value in
            let chunk: EnrichedStreamPart<PartialOutput>
            switch value {
            case .retryBoundary(let request, let warnings):
                state.recordedContent = []
                state.activeText = [:]
                state.activeReasoning = [:]
                state.recordedRequest = request
                state.recordedWarnings = warnings
                return []
            case .enriched(let enriched):
                chunk = enriched
            }

            var results = [chunk]
            let part = chunk.part

            let handledForRetry: Bool
            if case .error(let error) = part {
                handledForRetry = withLock {
                    if let index = errorsHandledForStreamRetry.firstIndex(of: errorIdentity(error)) {
                        errorsHandledForStreamRetry.remove(at: index)
                        return true
                    }
                    return false
                }
            } else {
                handledForRetry = false
            }

            if !handledForRetry {
                await notify(invoke(configuration.onChunk, with: part))
            }

            if case .error(let rawError) = part {
                let error = (wrapGatewayError(rawError) as? Error) ?? rawError
                if let noOutput = error as? NoOutputGeneratedError {
                    state.recordedNoOutputError = noOutput
                }
                if !handledForRetry {
                    if let onError = configuration.onError {
                        _ = try? await onError(error)
                    } else {
                        print(error)
                    }
                }
            }

            switch part {
            case .custom(let kind, let metadata):
                state.recordedContent.append(.custom(kind: kind, providerMetadata: metadata))
            case .source(let source):
                state.recordedContent.append(.source(type: "source", source: source))
            case .toolCall(let toolCall):
                state.recordedContent.append(.toolCall(toolCall, providerMetadata: toolCall.providerMetadata))
            case .toolApprovalRequest(let request):
                state.recordedContent.append(.toolApprovalRequest(request))
            case .toolApprovalResponse(let response):
                state.recordedContent.append(.toolApprovalResponse(response))
            case .toolError(let error):
                state.recordedContent.append(.toolError(error, providerMetadata: error.providerMetadata))
            case .toolResult(let result) where result.preliminary != true:
                state.recordedContent.append(.toolResult(result, providerMetadata: result.providerMetadata))

            case .textStart(let id, let metadata):
                state.recordedContent.append(.text(text: "", providerMetadata: metadata))
                state.activeText[id] = state.recordedContent.count - 1

            case .textDelta(let id, let text, let metadata):
                guard let index = state.activeText[id] else {
                    results.append(EnrichedStreamPart(part: .error(StreamPartNotFoundError(kind: "text", id: id)), partialOutput: nil))
                    return results
                }
                if case .text(let current, let citations, let currentMetadata) = state.recordedContent[index] {
                    state.recordedContent[index] = .text(
                        text: current + text, citations: citations, providerMetadata: metadata ?? currentMetadata
                    )
                }

            case .textEnd(let id, let metadata, let citations):
                guard let index = state.activeText[id] else {
                    results.append(EnrichedStreamPart(part: .error(StreamPartNotFoundError(kind: "text", id: id)), partialOutput: nil))
                    return results
                }
                if case .text(let current, let currentCitations, let currentMetadata) = state.recordedContent[index] {
                    state.recordedContent[index] = .text(
                        text: current, citations: citations ?? currentCitations, providerMetadata: metadata ?? currentMetadata
                    )
                }
                state.activeText[id] = nil

            case .reasoningStart(let id, let metadata):
                state.recordedContent.append(.reasoning(ReasoningOutput(text: "", providerMetadata: metadata)))
                state.activeReasoning[id] = state.recordedContent.count - 1

            case .reasoningDelta(let id, let text, let metadata):
                guard let index = state.activeReasoning[id] else {
                    results.append(EnrichedStreamPart(part: .error(StreamPartNotFoundError(kind: "reasoning", id: id)), partialOutput: nil))
                    return results
                }
                if case .reasoning(let current) = state.recordedContent[index] {
                    state.recordedContent[index] = .reasoning(ReasoningOutput(
                        text: current.text + text, providerMetadata: metadata ?? current.providerMetadata
                    ))
                }

            case .reasoningEnd(let id, let metadata):
                guard let index = state.activeReasoning[id] else {
                    results.append(EnrichedStreamPart(part: .error(StreamPartNotFoundError(kind: "reasoning", id: id)), partialOutput: nil))
                    return results
                }
                if case .reasoning(let current) = state.recordedContent[index] {
                    state.recordedContent[index] = .reasoning(ReasoningOutput(
                        text: current.text, providerMetadata: metadata ?? current.providerMetadata
                    ))
                }
                state.activeReasoning[id] = nil

            case .file(let file, let metadata):
                state.recordedContent.append(.file(file: file, providerMetadata: metadata))
            case .reasoningFile(let file, let metadata):
                state.recordedContent.append(.reasoningFile(file: file, providerMetadata: metadata))

            case .startStep(let request, let warnings):
                state.recordedContent = []
                state.activeText = [:]
                state.activeReasoning = [:]
                state.recordedRequest = request
                state.recordedWarnings = warnings

            case .finishStep(let response, let usage, let performance, let finishReason, let rawFinishReason, let providerMetadata):
                try await recordStep(
                    state: state,
                    response: response,
                    usage: usage,
                    performance: performance,
                    finishReason: finishReason,
                    rawFinishReason: rawFinishReason,
                    providerMetadata: providerMetadata
                )

            case .finish(let finishReason, let rawFinishReason, let totalUsage):
                state.recordedTotalUsage = totalUsage
                state.recordedFinishReason = finishReason
                state.recordedRawFinishReason = rawFinishReason

            default:
                break
            }

            return results
        }, flush: { [self] in
            try await finishProcessing(state: state)
            return []
        })
    }

    private func recordStep(
        state: EventProcessorState,
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        performance: StepResultPerformance,
        finishReason: FinishReason,
        rawFinishReason: String?,
        providerMetadata: ProviderMetadata?
    ) async throws {
        let stepResponseMessages = try await toResponseMessages(
            content: state.recordedContent,
            tools: configuration.tools
        )

        let (stepNumber, model, runtimeContext, toolsContext, currentStepMessages) = withLock {
            (recordedSteps.count, currentStepModel, self.runtimeContext, self.toolsContext, self.currentStepMessages)
        }

        let stepResult = DefaultStepResult(
            callId: callId,
            stepNumber: stepNumber,
            model: model,
            toolsContext: toolsContext,
            runtimeContext: runtimeContext,
            content: state.recordedContent,
            finishReason: finishReason,
            rawFinishReason: rawFinishReason,
            usage: usage,
            performance: performance,
            warnings: state.recordedWarnings,
            request: state.recordedRequest,
            response: StepResultResponse(from: response, messages: stepResponseMessages),
            providerMetadata: providerMetadata
        )

        await notify(
            invoke(configuration.onStepEnd, with: stepResult as StepResult),
            { await self.dispatcher.onStepEnd(stepResult) }
        )

        if !state.recordedWarnings.isEmpty {
            logWarnings(state.recordedWarnings.map(Warning.languageModel))
        }

        let stepFinish: DelayedPromise<Void>? = withLock {
            recordedSteps.append(stepResult)
            stepMessagesForNextStep = currentStepMessages + stepResponseMessages.map { $0.modelMessage }
            return self.stepFinish
        }
        stepFinish?.resolve(())
    }

    private func finishProcessing(state: EventProcessorState) async throws {
        let (recordedSteps, isAborted, initialResponses) = withLock {
            (self.recordedSteps, self.isAborted, self.initialResponses)
        }

        // No steps (e.g. an error before the first step) or an incomplete continuation step rejects the results.
        if recordedSteps.isEmpty || state.recordedNoOutputError != nil {
            let error: any Error = abortController?.isAborted == true
                ? (abortController?.reason ?? CancellationError())
                : (state.recordedNoOutputError ?? NoOutputGeneratedError(
                    message: "No output generated. Check the stream for errors."
                ))
            rejectResultPromises(error)
            return
        }

        let totalUsage = state.recordedTotalUsage ?? LanguageModelUsage()
        finishReason.resolve(state.recordedFinishReason ?? .other)
        rawFinishReason.resolve(state.recordedRawFinishReason)
        self.totalUsage.resolve(totalUsage)
        steps.resolve(recordedSteps)

        if isAborted {
            return
        }

        let endEvent = GenerateTextEndEvent(
            callId: callId,
            steps: recordedSteps,
            initialResponseMessages: initialResponses,
            totalUsage: totalUsage
        )

        let onEnd = configuration.onEnd
        let output = configuration.output
        let outputIsDefault = configuration.outputIsDefault
        var notifyOnEnd: (@Sendable () async throws -> Void)?
        if let onEnd {
            notifyOnEnd = {
                var parsedOutput: OutputValue?
                if !outputIsDefault {
                    let finalStep = recordedSteps[recordedSteps.count - 1]
                    parsedOutput = try? await output.parseOutput(
                        text: finalStep.text,
                        response: finalStep.response.metadata,
                        usage: finalStep.usage,
                        finishReason: finalStep.finishReason
                    )
                }
                try await onEnd(StreamTextEndEvent(event: endEvent, output: parsedOutput))
            }
        }
        await notify(notifyOnEnd, { await self.dispatcher.onEnd(.generateText(endEvent)) })
    }
}

// MARK: - Engine state

private final class PumpStarter: @unchecked Sendable {
    var engine: (() -> Void)?
    func start() { engine?() }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

private final class StopGate: @unchecked Sendable {
    var isRunning = true
}

private final class AbortableState: @unchecked Sendable {
    var started = false
    var done = false
}

private final class TransformSegmentState: @unchecked Sendable {
    var segment: AsyncThrowingStream<TextStreamPart, Error>.AsyncIterator?
    var pendingBoundary: InternalStreamPart?
    var sourceDone = false
}

private final class OutputTransformState: @unchecked Sendable {
    var firstTextChunkId: String?
    var text = ""
    var textChunk = ""
    var textProviderMetadata: ProviderMetadata?
    var lastPublishedValue: String?
    var hasPublishedValue = false

    func reset() {
        firstTextChunkId = nil
        text = ""
        textChunk = ""
        textProviderMetadata = nil
        lastPublishedValue = nil
        hasPublishedValue = false
    }
}

private final class EventProcessorState: @unchecked Sendable {
    var recordedContent: [ContentPart] = []
    var activeText: [String: Int] = [:]
    var activeReasoning: [String: Int] = [:]
    var recordedRequest = LanguageModelRequestMetadata()
    var recordedWarnings: [CallWarning] = []
    var recordedFinishReason: FinishReason?
    var recordedRawFinishReason: String?
    var recordedTotalUsage: LanguageModelUsage?
    var recordedNoOutputError: NoOutputGeneratedError?
}

private final class ToolCallbackState: @unchecked Sendable {
    var ongoingToolNames: [String: String] = [:]
    var validatedContexts: [String: [String: Context?]] = [:]
}

private final class PendingToolCalls: @unchecked Sendable {
    var calls: [TypedToolCall] = []
}

/// Reads a stream from several call sites, one at a time.
final class SharedIterator<Element: Sendable>: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<Element, Error>.AsyncIterator

    init(stream: AsyncThrowingStream<Element, Error>) {
        self.iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> Element? {
        try await iterator.next()
    }
}

/// The model stream of a step, replaceable on retry.
private final class RetryingStreamReader: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<StepStreamPart, Error>.AsyncIterator
    var buffered: [StepStreamPart] = []
    var openTextParts: [String] = []
    var openReasoningParts: [String] = []
    var enqueueBoundary = false
    var automaticRetryCount = 0
    var callbackRetryCount = 0
    var done = false

    init(stream: AsyncThrowingStream<StepStreamPart, Error>) {
        self.iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> StepStreamPart? {
        try await iterator.next()
    }

    func replace(stream: AsyncThrowingStream<StepStreamPart, Error>) {
        iterator = stream.makeAsyncIterator()
    }
}

/// State of one streaming step.
private final class StreamStepState: @unchecked Sendable {
    let stepNumber: Int
    let baseUsage: LanguageModelUsage
    let stepStartTimestampMs: Double
    let stepModel: ModelInfo
    let stepMessages: [ModelMessage]
    let stepExecutionTools: ToolSet?
    let stepToolsContext: ToolsContext
    let stepRuntimeContext: Context
    let stepFinish: DelayedPromise<Void>
    let initialCall: LanguageModelCallStream
    let generateId: IDGenerator
    let currentDate: @Sendable () -> Date

    var request: LanguageModelV4RequestInfo?
    var response: LanguageModelV4StreamResponseInfo?
    var warnings: [CallWarning]?
    var finishReason: FinishReason = .other
    var rawFinishReason: String?
    var hasReceivedTerminalChunk = false
    var hasReceivedOutputChunk = false
    var usage = LanguageModelUsage()
    var providerMetadata: ProviderMetadata?
    var modelCallPerformance = StreamStepState.emptyPerformance
    var toolExecutionMs: [String: Double] = [:]
    var responseId: String
    var responseTimestamp: Date
    var responseModelId: String
    var isFirstChunk = true
    var textPartIds: [String: String] = [:]
    var reasoningPartIds: [String: String] = [:]
    var toolCalls: [TypedToolCall] = []
    var toolOutputs: [ToolOutput] = []
    var toolApprovalResponses: [ToolApprovalResponseOutput] = []

    static let emptyPerformance = LanguageModelCallPerformance(
        responseTimeMs: 0,
        effectiveOutputTokensPerSecond: 0,
        effectiveTotalTokensPerSecond: 0
    )

    init(
        stepNumber: Int,
        usage: LanguageModelUsage,
        stepStartTimestampMs: Double,
        stepModel: ModelInfo,
        stepMessages: [ModelMessage],
        stepExecutionTools: ToolSet?,
        stepToolsContext: ToolsContext,
        stepRuntimeContext: Context,
        stepFinish: DelayedPromise<Void>,
        initialCall: LanguageModelCallStream,
        generateId: @escaping IDGenerator,
        currentDate: @escaping @Sendable () -> Date
    ) {
        self.stepNumber = stepNumber
        self.baseUsage = usage
        self.stepStartTimestampMs = stepStartTimestampMs
        self.stepModel = stepModel
        self.stepMessages = stepMessages
        self.stepExecutionTools = stepExecutionTools
        self.stepToolsContext = stepToolsContext
        self.stepRuntimeContext = stepRuntimeContext
        self.stepFinish = stepFinish
        self.initialCall = initialCall
        self.generateId = generateId
        self.currentDate = currentDate
        self.request = initialCall.request
        self.response = initialCall.response
        self.responseId = generateId()
        self.responseTimestamp = currentDate()
        self.responseModelId = stepModel.modelId
    }

    func resetForRetry(warnings: [CallWarning]) {
        self.warnings = warnings
        finishReason = .other
        rawFinishReason = nil
        hasReceivedTerminalChunk = false
        hasReceivedOutputChunk = false
        usage = LanguageModelUsage()
        providerMetadata = nil
        modelCallPerformance = StreamStepState.emptyPerformance
        responseId = generateId()
        responseTimestamp = currentDate()
        responseModelId = stepModel.modelId
        textPartIds = [:]
        reasoningPartIds = [:]
    }
}

/// A text or reasoning delta references a part that was not started.
struct StreamPartNotFoundError: LocalizedError, CustomStringConvertible, Sendable {
    let kind: String
    let id: String
    var description: String { "\(kind) part \(id) not found" }
    var errorDescription: String? { description }
}

/// Identity of an error instance, to recognize an error already handled for a retry decision.
private func errorIdentity(_ error: any Error) -> String {
    "\(ObjectIdentifier(type(of: error)))|\(String(describing: error))"
}

/// A stable comparison key of a partial output.
private func partialOutputKey<T>(_ value: T) -> String {
    if let json = value as? JSONValue {
        return json.jsonString
    }
    if let encodable = value as? Encodable,
       let data = try? JSONEncoder().encode(EncodableBox(encodable)) {
        return String(decoding: data, as: UTF8.self)
    }
    return String(describing: value)
}

private struct EncodableBox: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

extension ToolOutput {
    /// The output as a stream part.
    var streamPart: TextStreamPart {
        switch self {
        case .result(let result): return .toolResult(result)
        case .error(let error): return .toolError(error)
        }
    }
}
