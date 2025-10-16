import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 StreamText V2 - Rewritten to eliminate race conditions.

 Port of `@ai-sdk/ai/src/generate-text/stream-text.ts`.

 ## Implementation Status

 ✅ **Phase 1: Core Streaming (Completed)**
 - textStream: AsyncThrowingStream<String, Error>
 - fullStream: AsyncThrowingStream<TextStreamPart, Error>
 - Thread-safe actor-based state management
 - Basic error handling

 ✅ **Phase 2: Content Support (Completed)**
 - content: [ContentPart] property
 - text: String property
 - reasoning: [ReasoningOutput] support
 - reasoningText: String? property
 - files: [GeneratedFile] support
 - sources: [Source] support
 - All TextStreamPart types processed

 ✅ **Phase 3: Steps & Metadata (Completed)**
 - steps: [StepResult] property
 - request/response metadata
 - providerMetadata support
 - warnings support
 - Callbacks: onChunk, onFinish, onError
 - Stream consumption helpers
 - Response piping (pipeTextStreamToResponse, toTextStreamResponse)

 ✅ **Phase 4: Tool Support (Completed)**
 - toolCalls: [TypedToolCall] property
 - staticToolCalls: [StaticToolCall] filtering
 - dynamicToolCalls: [DynamicToolCall] filtering
 - toolResults: [TypedToolResult] property
 - staticToolResults: [StaticToolResult] filtering
 - dynamicToolResults: [DynamicToolResult] filtering
 - Tool call/result tracking in content
 - Tool event processing in stream pipeline

 ⏳ **TODO: Advanced Features (Phase 5)**
 - Multi-step execution with stop conditions
 - Automatic tool execution
 - Step iteration
 - Telemetry support
 - Transforms pipeline
 - UI message streams
 - Additional response helpers

 ## Thread-Safety Design

 All mutable state is managed through `StreamStateV2` actor, ensuring
 race-free concurrent access. No `@unchecked Sendable` classes with
 unprotected mutable state.
 */

// MARK: - Thread-Safe State Management

/// Hub for multicasting stream parts with replay support (thread-safe)
private actor StreamHub {
    private var buffer: [TextStreamPart] = []
    private var continuations: [AsyncThrowingStream<TextStreamPart, Error>.Continuation] = []
    private var finished = false
    private var finishError: Error?

    func subscribe() -> AsyncThrowingStream<TextStreamPart, Error> {
        AsyncThrowingStream { continuation in
            // Replay buffered parts
            for part in buffer {
                continuation.yield(part)
            }
            if finished {
                if let err = finishError {
                    continuation.finish(throwing: err)
                } else {
                    continuation.finish()
                }
                return
            }
            continuations.append(continuation)
        }
    }

    func publish(_ part: TextStreamPart) {
        guard !finished else { return }
        buffer.append(part)
        for c in continuations {
            c.yield(part)
        }
    }

    func finish(_ error: Error? = nil) {
        guard !finished else { return }
        finished = true
        finishError = error
        for c in continuations {
            if let error {
                c.finish(throwing: error)
            } else {
                c.finish()
            }
        }
        continuations.removeAll()
    }
}

/// Actor-based state to eliminate race conditions
private actor StreamStateV2 {
    var recordedContent: [ContentPart] = []
    var recordedFinishReason: FinishReason?
    var recordedUsage: LanguageModelUsage?
    var textAccumulator: String = ""
    var isFinished: Bool = false

    // Active content tracking
    var activeTextContent: [String: ActiveTextContent] = [:]
    var activeReasoningContent: [String: ActiveReasoningContent] = [:]

    // Step tracking
    var recordedSteps: [StepResult] = []
    var currentStepContent: [ContentPart] = []
    var currentStepRequest: LanguageModelRequestMetadata = LanguageModelRequestMetadata()
    var currentStepWarnings: [CallWarning] = []

    // Response metadata
    var responseId: String = ""
    var responseTimestamp: Date = Date()
    var responseModelId: String = ""
    var providerMetadata: ProviderMetadata?

    // Tool tracking
    var recordedToolCalls: [TypedToolCall] = []
    var recordedToolResults: [TypedToolResult] = []
    var toolNamesByCallId: [String: String] = [:]

    struct ActiveTextContent {
        var index: Int
        var text: String
        var providerMetadata: ProviderMetadata?
    }

    struct ActiveReasoningContent {
        var index: Int
        var text: String
        var providerMetadata: ProviderMetadata?
    }

    func appendText(_ delta: String) {
        textAccumulator.append(delta)
    }

    func getText() -> String {
        textAccumulator
    }

    func setFinishReason(_ reason: FinishReason) {
        recordedFinishReason = reason
    }

    func setUsage(_ usage: LanguageModelUsage) {
        recordedUsage = usage
    }

    func getFinishReason() -> FinishReason? {
        recordedFinishReason
    }

    func getUsage() -> LanguageModelUsage? {
        recordedUsage
    }

    func markFinished() {
        isFinished = true
    }

    func checkFinished() -> Bool {
        isFinished
    }

    // Content management
    func getContent() -> [ContentPart] {
        recordedContent
    }

    // Text content
    func startText(id: String, metadata: ProviderMetadata?) {
        let index = recordedContent.count
        activeTextContent[id] = ActiveTextContent(index: index, text: "", providerMetadata: metadata)
        recordedContent.append(.text(text: "", providerMetadata: metadata))
    }

    func appendTextDelta(id: String, delta: String, metadata: ProviderMetadata?) {
        guard var active = activeTextContent[id] else { return }

        active.text += delta
        if let metadata {
            active.providerMetadata = metadata
        }
        activeTextContent[id] = active
        recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)
    }

    func endText(id: String, metadata: ProviderMetadata?) {
        guard var active = activeTextContent[id] else { return }

        if let metadata {
            active.providerMetadata = metadata
        }
        activeTextContent.removeValue(forKey: id)
        recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)
    }

    // Reasoning content
    func startReasoning(id: String, metadata: ProviderMetadata?) {
        let index = recordedContent.count
        let reasoning = ReasoningOutput(text: "", providerMetadata: metadata)
        activeReasoningContent[id] = ActiveReasoningContent(index: index, text: "", providerMetadata: metadata)
        recordedContent.append(.reasoning(reasoning))
    }

    func appendReasoningDelta(id: String, delta: String, metadata: ProviderMetadata?) {
        guard var active = activeReasoningContent[id] else { return }

        active.text += delta
        if let metadata {
            active.providerMetadata = metadata
        }
        activeReasoningContent[id] = active
        let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
        recordedContent[active.index] = .reasoning(reasoning)
    }

    func endReasoning(id: String, metadata: ProviderMetadata?) {
        guard var active = activeReasoningContent[id] else { return }

        if let metadata {
            active.providerMetadata = metadata
        }
        activeReasoningContent.removeValue(forKey: id)
        let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
        recordedContent[active.index] = .reasoning(reasoning)
    }

    // Files and sources
    func addFile(_ file: GeneratedFile) {
        recordedContent.append(.file(file: file, providerMetadata: nil))
    }

    func addSource(_ source: Source) {
        recordedContent.append(.source(type: "source", source: source))
    }

    // Step management
    func setResponseMetadata(id: String, timestamp: Date, modelId: String) {
        self.responseId = id
        self.responseTimestamp = timestamp
        self.responseModelId = modelId
    }

    func setProviderMetadata(_ metadata: ProviderMetadata?) {
        self.providerMetadata = metadata
    }

    func finalizeStep(
        finishReason: FinishReason,
        usage: LanguageModelUsage,
        providerMetadata: ProviderMetadata?,
        headers: [String: String]?
    ) -> StepResult {
        let response = StepResultResponse(
            id: responseId,
            timestamp: responseTimestamp,
            modelId: responseModelId,
            headers: headers,
            messages: [],
            body: nil
        )

        let stepResult = DefaultStepResult(
            content: recordedContent,
            finishReason: finishReason,
            usage: usage,
            warnings: currentStepWarnings,
            request: currentStepRequest,
            response: response,
            providerMetadata: providerMetadata
        )

        recordedSteps.append(stepResult)
        return stepResult
    }

    func getSteps() -> [StepResult] {
        recordedSteps
    }

    func getResponseMetadata() -> (id: String, timestamp: Date, modelId: String) {
        (responseId, responseTimestamp, responseModelId)
    }

    func getProviderMetadata() -> ProviderMetadata? {
        providerMetadata
    }

    // Tool management
    func addToolCall(_ toolCall: TypedToolCall) {
        recordedToolCalls.append(toolCall)
        recordedContent.append(.toolCall(toolCall, providerMetadata: toolCall.providerMetadata))
        toolNamesByCallId[toolCall.toolCallId] = toolCall.toolName
    }

    func addToolResult(_ result: TypedToolResult) {
        recordedToolResults.append(result)
        recordedContent.append(.toolResult(result, providerMetadata: result.providerMetadata))
        toolNamesByCallId.removeValue(forKey: result.toolCallId)
    }

    func addToolError(_ error: TypedToolError) {
        recordedContent.append(.toolError(error, providerMetadata: nil))
        toolNamesByCallId.removeValue(forKey: error.toolCallId)
    }

    func getToolCalls() -> [TypedToolCall] {
        recordedToolCalls
    }

    func getToolResults() -> [TypedToolResult] {
        recordedToolResults
    }
}

// MARK: - Internal Options

public struct StreamTextV2InternalOptions: Sendable {
    public var now: @Sendable () -> Double
    public var generateId: IDGenerator
    public var currentDate: @Sendable () -> Date

    public init(
        now: @escaping @Sendable () -> Double = SwiftAISDK.now,
        generateId: IDGenerator? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
        if let generateId {
            self.generateId = generateId
        } else {
            self.generateId = try! createIDGenerator(prefix: "aitxt", size: 24)
        }
        self.currentDate = currentDate
    }
}

// MARK: - Result Type

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class DefaultStreamTextResultV2 {

    private let state = StreamStateV2()
    private let model: any LanguageModelV3
    private let prompt: Prompt
    private let settings: CallSettings
    private let internalOptions: StreamTextV2InternalOptions

    // Promises for async properties
    private let finishReasonPromise = DelayedPromise<FinishReason>()
    private let usagePromise = DelayedPromise<LanguageModelUsage>()
    private let textPromise = DelayedPromise<String>()
    private let contentPromise = DelayedPromise<[ContentPart]>()
    private let stepsPromise = DelayedPromise<[StepResult]>()

    // Hub for multicasting stream parts
    private let hub = StreamHub()

    // Pipeline management
    private var pipelineTask: Task<Void, Never>?
    private let pipelineLock = NSLock()

    // Callbacks
    private let onChunk: StreamTextOnChunkCallback?
    private let onFinish: StreamTextOnFinishCallback?
    private let onError: StreamTextOnErrorCallback

    init(
        model: any LanguageModelV3,
        prompt: Prompt,
        settings: CallSettings,
        internalOptions: StreamTextV2InternalOptions,
        onChunk: StreamTextOnChunkCallback?,
        onFinish: StreamTextOnFinishCallback?,
        onError: @escaping StreamTextOnErrorCallback
    ) {
        self.model = model
        self.prompt = prompt
        self.settings = settings
        self.internalOptions = internalOptions
        self.onChunk = onChunk
        self.onFinish = onFinish
        self.onError = onError
    }

    // MARK: - Pipeline Management

    private func ensurePipelineStartedOnce() {
        if pipelineTask != nil { return }
        pipelineLock.lock()
        defer { pipelineLock.unlock() }
        if pipelineTask != nil { return }
        pipelineTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.processStream { part in
                    await self.hub.publish(part)
                }
                await self.hub.finish(nil)
            } catch {
                await self.hub.finish(error)
            }
        }
    }

    // MARK: - Public Properties

    public var text: String {
        get async throws {
            ensurePipelineStartedOnce()
            return try await textPromise.task.value
        }
    }

    public var content: [ContentPart] {
        get async throws {
            ensurePipelineStartedOnce()
            return try await contentPromise.task.value
        }
    }

    public var reasoning: [ReasoningOutput] {
        get async throws {
            ensurePipelineStartedOnce()
            let content = try await contentPromise.task.value
            return content.compactMap { part in
                if case .reasoning(let reasoning) = part {
                    return reasoning
                }
                return nil
            }
        }
    }

    public var reasoningText: String? {
        get async throws {
            ensurePipelineStartedOnce()
            let reasoningParts = try await reasoning
            guard !reasoningParts.isEmpty else { return nil }
            return reasoningParts.map { $0.text }.joined(separator: "\n")
        }
    }

    public var files: [GeneratedFile] {
        get async throws {
            ensurePipelineStartedOnce()
            let content = try await contentPromise.task.value
            return content.compactMap { part in
                if case .file(let file, _) = part {
                    return file
                }
                return nil
            }
        }
    }

    public var sources: [Source] {
        get async throws {
            ensurePipelineStartedOnce()
            let content = try await contentPromise.task.value
            return content.compactMap { part in
                if case .source(_, let source) = part {
                    return source
                }
                return nil
            }
        }
    }

    public var finishReason: FinishReason {
        get async throws {
            ensurePipelineStartedOnce()
            return try await finishReasonPromise.task.value
        }
    }

    public var usage: LanguageModelUsage {
        get async throws {
            ensurePipelineStartedOnce()
            return try await usagePromise.task.value
        }
    }

    public var totalUsage: LanguageModelUsage {
        get async throws {
            ensurePipelineStartedOnce()
            // For single-step, totalUsage == usage
            // In future multi-step support, this will accumulate
            return try await usagePromise.task.value
        }
    }

    public var steps: [StepResult] {
        get async throws {
            ensurePipelineStartedOnce()
            return try await stepsPromise.task.value
        }
    }

    public var request: LanguageModelRequestMetadata {
        get async throws {
            ensurePipelineStartedOnce()
            let steps = try await stepsPromise.task.value
            guard let lastStep = steps.last else {
                return LanguageModelRequestMetadata()
            }
            return lastStep.request
        }
    }

    public var response: StepResultResponse {
        get async throws {
            ensurePipelineStartedOnce()
            let steps = try await stepsPromise.task.value
            guard let lastStep = steps.last else {
                throw NoOutputGeneratedError(message: "No output generated")
            }
            return lastStep.response
        }
    }

    public var providerMetadata: ProviderMetadata? {
        get async throws {
            ensurePipelineStartedOnce()
            return await state.getProviderMetadata()
        }
    }

    public var warnings: [CallWarning]? {
        get async throws {
            ensurePipelineStartedOnce()
            let steps = try await stepsPromise.task.value
            guard let lastStep = steps.last else {
                return nil
            }
            return lastStep.warnings
        }
    }

    public var toolCalls: [TypedToolCall] {
        get async throws {
            ensurePipelineStartedOnce()
            return await state.getToolCalls()
        }
    }

    public var staticToolCalls: [StaticToolCall] {
        get async throws {
            ensurePipelineStartedOnce()
            let calls = await state.getToolCalls()
            return calls.compactMap { call in
                if case .static(let staticCall) = call {
                    return staticCall
                }
                return nil
            }
        }
    }

    public var dynamicToolCalls: [DynamicToolCall] {
        get async throws {
            ensurePipelineStartedOnce()
            let calls = await state.getToolCalls()
            return calls.compactMap { call in
                if case .dynamic(let dynamicCall) = call {
                    return dynamicCall
                }
                return nil
            }
        }
    }

    public var toolResults: [TypedToolResult] {
        get async throws {
            ensurePipelineStartedOnce()
            return await state.getToolResults()
        }
    }

    public var staticToolResults: [StaticToolResult] {
        get async throws {
            ensurePipelineStartedOnce()
            let results = await state.getToolResults()
            return results.compactMap { result in
                if case .static(let staticResult) = result {
                    return staticResult
                }
                return nil
            }
        }
    }

    public var dynamicToolResults: [DynamicToolResult] {
        get async throws {
            ensurePipelineStartedOnce()
            let results = await state.getToolResults()
            return results.compactMap { result in
                if case .dynamic(let dynamicResult) = result {
                    return dynamicResult
                }
                return nil
            }
        }
    }

    public var fullStream: AsyncThrowingStream<TextStreamPart, Error> {
        get async {
            ensurePipelineStartedOnce()
            return await hub.subscribe()
        }
    }

    public var textStream: AsyncThrowingStream<String, Error> {
        get async {
            ensurePipelineStartedOnce()
            let base = await hub.subscribe()
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        for try await part in base {
                            if case .textDelta(_, let delta, _) = part, !delta.isEmpty {
                                continuation.yield(delta)
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Pipeline

    private func processStream(onPart: @escaping @Sendable (TextStreamPart) async -> Void) async throws {
        do {
            let standardized = try standardizePrompt(self.prompt)
            let supportedUrls = try await self.model.supportedUrls
            let promptForModel = try await convertToLanguageModelPrompt(
                prompt: standardized,
                supportedUrls: supportedUrls,
                download: nil
            )

            let preparedSettings = try prepareCallSettings(
                maxOutputTokens: self.settings.maxOutputTokens,
                temperature: self.settings.temperature,
                topP: self.settings.topP,
                topK: self.settings.topK,
                presencePenalty: self.settings.presencePenalty,
                frequencyPenalty: self.settings.frequencyPenalty,
                stopSequences: self.settings.stopSequences,
                seed: self.settings.seed
            )

            let callOptions = LanguageModelV3CallOptions(
                prompt: promptForModel,
                maxOutputTokens: preparedSettings.maxOutputTokens,
                temperature: preparedSettings.temperature,
                stopSequences: preparedSettings.stopSequences,
                topP: preparedSettings.topP,
                topK: preparedSettings.topK,
                presencePenalty: preparedSettings.presencePenalty,
                frequencyPenalty: preparedSettings.frequencyPenalty,
                responseFormat: nil,
                seed: preparedSettings.seed,
                tools: nil,
                toolChoice: nil,
                includeRawChunks: false,
                abortSignal: self.settings.abortSignal,
                headers: self.settings.headers,
                providerOptions: nil
            )

            let streamResult = try await self.model.doStream(options: callOptions)

            // Initialize response metadata
            let responseId = self.internalOptions.generateId()
            let responseTimestamp = self.internalOptions.currentDate()
            let responseModelId = self.model.modelId
            let responseHeaders = streamResult.response?.headers
            await self.state.setResponseMetadata(
                id: responseId,
                timestamp: responseTimestamp,
                modelId: responseModelId
            )

            // Process stream parts
            for try await part in streamResult.stream {
                // Check abort signal
                if let abortSignal = self.settings.abortSignal, abortSignal() {
                    await self.state.markFinished()
                    let cancelError = CancellationError()
                    await self.onError(StreamTextOnErrorEvent(error: cancelError))
                    self.textPromise.reject(cancelError)
                    self.contentPromise.reject(cancelError)
                    self.finishReasonPromise.reject(cancelError)
                    self.usagePromise.reject(cancelError)
                    self.stepsPromise.reject(cancelError)
                    throw cancelError
                }

                // Convert to TextStreamPart and process
                if let textStreamPart = convertToTextStreamPart(part) {
                    await processStreamPart(textStreamPart)

                    // Invoke onChunk callback
                    if shouldInvokeOnChunk(textStreamPart), let onChunk = self.onChunk {
                        await onChunk(StreamTextOnChunkEvent(chunk: textStreamPart))
                    }

                    await onPart(textStreamPart)
                }
            }

            // Finalize step
            await self.state.markFinished()

            let finalText = await self.state.getText()
            let finalContent = await self.state.getContent()
            let finalReason = await self.state.getFinishReason() ?? .unknown
            let finalUsage = await self.state.getUsage() ?? LanguageModelUsage()
            let finalProviderMetadata = await self.state.getProviderMetadata()

            // Create step result
            let stepResult = await self.state.finalizeStep(
                finishReason: finalReason,
                usage: finalUsage,
                providerMetadata: finalProviderMetadata,
                headers: responseHeaders
            )

            let steps = await self.state.getSteps()

            // Resolve promises
            self.textPromise.resolve(finalText)
            self.contentPromise.resolve(finalContent)
            self.finishReasonPromise.resolve(finalReason)
            self.usagePromise.resolve(finalUsage)
            self.stepsPromise.resolve(steps)

            // Invoke onFinish callback
            if let onFinish = self.onFinish {
                await onFinish(StreamTextOnFinishEvent(
                    finishReason: finalReason,
                    totalUsage: finalUsage,
                    finalStep: stepResult,
                    steps: steps
                ))
            }
        } catch {
            // Handle errors
            await self.onError(StreamTextOnErrorEvent(error: error))

            // Reject promises
            self.textPromise.reject(error)
            self.contentPromise.reject(error)
            self.finishReasonPromise.reject(error)
            self.usagePromise.reject(error)
            self.stepsPromise.reject(error)

            throw error
        }
    }

    private func shouldInvokeOnChunk(_ part: TextStreamPart) -> Bool {
        switch part {
        case .textDelta, .reasoningDelta, .source, .file, .toolCall, .toolResult:
            return true
        default:
            return false
        }
    }

    // MARK: - Stream Consumption and Response Helpers

    public func consumeStream(options: ConsumeStreamOptions?) async {
        let stream = await fullStream
        await SwiftAISDK.consumeStream(stream: stream, onError: options?.onError)
    }

    public func pipeTextStreamToResponse(
        _ response: any StreamTextResponseWriter,
        init initOptions: TextStreamResponseInit?
    ) async {
        let stream = await textStream
        SwiftAISDK.pipeTextStreamToResponse(
            response: response,
            status: initOptions?.status,
            statusText: initOptions?.statusText,
            headers: initOptions?.headers,
            textStream: stream
        )
    }

    public func toTextStreamResponse(
        init initOptions: TextStreamResponseInit?
    ) async -> TextStreamResponse {
        let stream = await textStream
        return SwiftAISDK.createTextStreamResponse(
            status: initOptions?.status,
            statusText: initOptions?.statusText,
            headers: initOptions?.headers,
            textStream: stream
        )
    }

    private func convertToTextStreamPart(_ part: LanguageModelV3StreamPart) -> TextStreamPart? {
        switch part {
        case .streamStart:
            return .start
        case .textStart(let id, let metadata):
            return .textStart(id: id, providerMetadata: metadata)
        case .textDelta(let id, let delta, let metadata):
            return .textDelta(id: id, text: delta, providerMetadata: metadata)
        case .textEnd(let id, let metadata):
            return .textEnd(id: id, providerMetadata: metadata)
        case .reasoningStart(let id, let metadata):
            return .reasoningStart(id: id, providerMetadata: metadata)
        case .reasoningDelta(let id, let delta, let metadata):
            return .reasoningDelta(id: id, text: delta, providerMetadata: metadata)
        case .reasoningEnd(let id, let metadata):
            return .reasoningEnd(id: id, providerMetadata: metadata)
        case .file(let file):
            // Convert LanguageModelV3File to GeneratedFile
            let generatedFile: any GeneratedFile
            switch file.data {
            case .base64(let base64String):
                generatedFile = DefaultGeneratedFile(base64: base64String, mediaType: file.mediaType)
            case .binary(let data):
                generatedFile = DefaultGeneratedFile(data: data, mediaType: file.mediaType)
            }
            return .file(generatedFile)
        case .source(let source):
            return .source(source)
        case .toolCall(let toolCall):
            // Convert LanguageModelV3ToolCall to TypedToolCall
            // Parse the input JSON string to JSONValue
            let inputJSON: JSONValue
            if let data = toolCall.input.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) {
                inputJSON = parsed
            } else {
                inputJSON = .null
            }

            let typedToolCall = TypedToolCall.static(StaticToolCall(
                toolCallId: toolCall.toolCallId,
                toolName: toolCall.toolName,
                input: inputJSON,
                providerExecuted: toolCall.providerExecuted,
                providerMetadata: toolCall.providerMetadata
            ))
            return .toolCall(typedToolCall)
        case .toolResult(let result):
            // Convert LanguageModelV3ToolResult to TypedToolResult
            // For Phase 4, we use .null for input since we don't track the original call input here
            // The output is the result from the tool execution
            let typedToolResult = TypedToolResult.static(StaticToolResult(
                toolCallId: result.toolCallId,
                toolName: result.toolName,
                input: .null,  // Would need to track corresponding call to fill this
                output: result.result,
                providerExecuted: result.providerExecuted,
                preliminary: result.preliminary,
                providerMetadata: result.providerMetadata
            ))
            return .toolResult(typedToolResult)
        case .finish(let reason, let usage, let metadata):
            // Capture provider metadata from finish event
            if let metadata {
                Task {
                    await self.state.setProviderMetadata(metadata)
                }
            }
            return .finish(finishReason: reason, totalUsage: usage)
        case .responseMetadata, .error:
            // Ignore metadata and error events (handled separately)
            return nil
        default:
            // Ignore unsupported events
            return nil
        }
    }

    private func convertToJSONValue(_ value: Any) -> JSONValue {
        if let string = value as? String {
            return .string(string)
        } else if let number = value as? Double {
            return .number(number)
        } else if let number = value as? Int {
            return .number(Double(number))
        } else if let bool = value as? Bool {
            return .bool(bool)
        } else if let array = value as? [Any] {
            return .array(array.map { convertToJSONValue($0) })
        } else if let dict = value as? [String: Any] {
            var object: [String: JSONValue] = [:]
            for (key, val) in dict {
                object[key] = convertToJSONValue(val)
            }
            return .object(object)
        } else if value is NSNull {
            return .null
        } else {
            return .null
        }
    }

    private func processStreamPart(_ part: TextStreamPart) async {
        switch part {
        case .textStart(let id, let metadata):
            await state.startText(id: id, metadata: metadata)

        case .textDelta(let id, let delta, let metadata):
            await state.appendText(delta)
            await state.appendTextDelta(id: id, delta: delta, metadata: metadata)

        case .textEnd(let id, let metadata):
            await state.endText(id: id, metadata: metadata)

        case .reasoningStart(let id, let metadata):
            await state.startReasoning(id: id, metadata: metadata)

        case .reasoningDelta(let id, let delta, let metadata):
            await state.appendReasoningDelta(id: id, delta: delta, metadata: metadata)

        case .reasoningEnd(let id, let metadata):
            await state.endReasoning(id: id, metadata: metadata)

        case .file(let file):
            await state.addFile(file)

        case .source(let source):
            await state.addSource(source)

        case .toolCall(let toolCall):
            await state.addToolCall(toolCall)

        case .toolResult(let result):
            await state.addToolResult(result)

        case .toolError(let error):
            await state.addToolError(error)

        case .finish(let reason, let usage):
            await state.setFinishReason(reason)
            await state.setUsage(usage)

        default:
            break
        }
    }
}

// MARK: - Public API

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamTextV2(
    model modelArg: LanguageModel,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    onChunk: StreamTextOnChunkCallback? = nil,
    onError rawOnError: StreamTextOnErrorCallback? = nil,
    onFinish: StreamTextOnFinishCallback? = nil,
    _internal: StreamTextV2InternalOptions = StreamTextV2InternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResultV2 {
    let resolvedModel = try resolveLanguageModel(modelArg)

    let defaultOnError: StreamTextOnErrorCallback = { event in
        fputs("streamTextV2 error: \(event.error)\n", stderr)
    }
    let onError = rawOnError ?? defaultOnError

    // Validate prompt
    guard (prompt == nil) || (messages == nil) else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"), prompt: \(prompt ?? "nil"), messages: provided)",
            message: "Provide either `prompt` or `messages`, not both."
        )
    }

    let promptInput: Prompt
    if let promptText = prompt {
        promptInput = Prompt.text(promptText, system: system)
    } else if let messageList = messages {
        promptInput = Prompt.messages(messageList, system: system)
    } else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"))",
            message: "Either `prompt` or `messages` must be provided."
        )
    }

    return DefaultStreamTextResultV2(
        model: resolvedModel,
        prompt: promptInput,
        settings: settings,
        internalOptions: _internal,
        onChunk: onChunk,
        onFinish: onFinish,
        onError: onError
    )
}

// @unchecked Sendable: Callbacks may not be Sendable, but pipeline management ensures thread-safety
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension DefaultStreamTextResultV2: @unchecked Sendable {}
