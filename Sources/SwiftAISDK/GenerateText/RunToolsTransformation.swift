import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Orchestrate tool execution events within the generate-text streaming pipeline.

 Port of `@ai-sdk/ai/src/generate-text/run-tools-transformation.ts`.

 The upstream implementation converts the raw language-model stream into a new
 stream that interleaves:
 - original text/reasoning/tool-input chunks
 - parsed tool calls (with validation/repair)
 - locally executed tool results
 - approval requests for tools requiring confirmation
 - provider-generated tool results/errors
 - final finish metadata (delayed until all tool executions complete)

 This Swift port mirrors that behavior using `AsyncThrowingStream`, preserving
 ordering guarantees and the delayed finish emission semantics crucial for
 downstream consumers (e.g. smooth streaming, response assembly).
 */
public func runToolsTransformation(
    tools: ToolSet?,
    generatorStream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
    tracer: any Tracer,
    telemetry: TelemetrySettings?,
    system: String?,
    messages: [ModelMessage],
    abortSignal: (@Sendable () -> Bool)?,
    repairToolCall: ToolCallRepairFunction?,
    experimentalContext: JSONValue?,
    generateId: @escaping IDGenerator
) -> AsyncThrowingStream<SingleRequestTextStreamPart, Error> {
    AsyncThrowingStream { continuation in
        let state = RunToolsTransformationState()
        var toolInputs: [String: JSONValue] = [:]
        var toolCallsById: [String: TypedToolCall] = [:]

        let emit: @Sendable (SingleRequestTextStreamPart) -> Void = { part in
            continuation.yield(part)
        }

        let handleCloseAction: @Sendable (RunToolsTransformationState.CloseAction) -> Void = { action in
            if let finishChunk = action.finishChunk {
                continuation.yield(finishChunk)
            }
            continuation.finish()
        }

        let processingTask = Task {
            do {
                for try await chunk in generatorStream {
                    if Task.isCancelled {
                        break
                    }

                    switch chunk {
                    case .streamStart(let warnings):
                        emit(.streamStart(warnings: warnings))

                    case .textStart(let id, let providerMetadata):
                        emit(.textStart(id: id, providerMetadata: providerMetadata))

                    case .textDelta(let id, let delta, let providerMetadata):
                        emit(.textDelta(id: id, delta: delta, providerMetadata: providerMetadata))

                    case .textEnd(let id, let providerMetadata):
                        emit(.textEnd(id: id, providerMetadata: providerMetadata))

                    case .reasoningStart(let id, let providerMetadata):
                        emit(.reasoningStart(id: id, providerMetadata: providerMetadata))

                    case .reasoningDelta(let id, let delta, let providerMetadata):
                        emit(.reasoningDelta(id: id, delta: delta, providerMetadata: providerMetadata))

                    case .reasoningEnd(let id, let providerMetadata):
                        emit(.reasoningEnd(id: id, providerMetadata: providerMetadata))

                    case .toolInputStart(let id, let toolName, let providerMetadata, let providerExecuted, let dynamic, let title):
                        emit(.toolInputStart(
                            id: id,
                            toolName: toolName,
                            providerMetadata: providerMetadata,
                            providerExecuted: providerExecuted,
                            dynamic: dynamic,
                            title: title
                        ))

                    case .toolInputDelta(let id, let delta, let providerMetadata):
                        emit(.toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata))

                    case .toolInputEnd(let id, let providerMetadata):
                        emit(.toolInputEnd(id: id, providerMetadata: providerMetadata))

                    case .source(let source):
                        emit(.source(source))

                    case .file(let fileChunk):
                        let generatedFile: GeneratedFile
                        switch fileChunk.data {
                        case .base64(let base64):
                            generatedFile = DefaultGeneratedFileWithType(base64: base64, mediaType: fileChunk.mediaType)
                        case .binary(let data):
                            generatedFile = DefaultGeneratedFileWithType(data: data, mediaType: fileChunk.mediaType)
                        }
                        emit(.file(generatedFile))

                    case .responseMetadata(let id, let modelId, let timestamp):
                        emit(.responseMetadata(id: id, timestamp: timestamp, modelId: modelId))

                    case .finish(let finishReason, let usage, let providerMetadata):
                        let finishPart: SingleRequestTextStreamPart = .finish(
                            finishReason: finishReason,
                            usage: asLanguageModelUsage(usage),
                            providerMetadata: providerMetadata
                        )
                        state.storeFinishChunk(finishPart)

                    case .raw(let rawValue):
                        emit(.raw(rawValue))

                    case .error(let errorValue):
                        emit(.error(ToolResultJSONError(value: errorValue)))

                    case .toolCall(let languageModelToolCall):
                        do {
                            let typedToolCall = await parseToolCall(
                                toolCall: languageModelToolCall,
                                tools: tools,
                                repairToolCall: repairToolCall,
                                system: system,
                                messages: messages
                            )

                            toolInputs[typedToolCall.toolCallId] = typedToolCall.input
                            toolCallsById[typedToolCall.toolCallId] = typedToolCall
                            emit(.toolCall(typedToolCall))

                            if typedToolCall.invalid == true {
                                let error = makeInvalidToolCallError(from: typedToolCall)
                                emit(.toolError(error))
                                continue
                            }

                            guard let tools, let tool = tools[typedToolCall.toolName] else {
                                continue
                            }

                            if let onInputAvailable = tool.onInputAvailable {
                                let options = ToolCallInputOptions(
                                    input: typedToolCall.input,
                                    toolCallId: typedToolCall.toolCallId,
                                    messages: messages,
                                    abortSignal: abortSignal,
                                    experimentalContext: experimentalContext
                                )
                                try await onInputAvailable(options)
                            }

                            if await isApprovalNeeded(
                                tool: tool,
                                toolCall: typedToolCall,
                                messages: messages,
                                experimentalContext: experimentalContext
                            ) {
                                let approval = ToolApprovalRequestOutput(
                                    approvalId: generateId(),
                                    toolCall: typedToolCall
                                )
                                emit(.toolApprovalRequest(approval))
                                continue
                            }

                            guard tool.execute != nil, typedToolCall.providerExecuted != true else {
                                continue
                            }

                            let toolExecutionId = generateId()
                            guard state.prepareToolExecution(id: toolExecutionId) else {
                                continue
                            }

                            let executionTask = Task {
                                defer {
                                    if let action = state.completeToolExecution(id: toolExecutionId) {
                                        handleCloseAction(action)
                                    }
                                }

                                let output = await executeToolCall(
                                    toolCall: typedToolCall,
                                    tools: tools,
                                    tracer: tracer,
                                    telemetry: telemetry,
                                    messages: messages,
                                    abortSignal: abortSignal,
                                    experimentalContext: experimentalContext,
                                    onPreliminaryToolResult: { result in
                                        emit(.toolResult(result))
                                    }
                                )

                                guard let output else { return }

                                switch output {
                                case .result(let result):
                                    emit(.toolResult(result))
                                case .error(let error):
                                    emit(.toolError(error))
                                }
                            }

                            state.attachTask(executionTask, to: toolExecutionId)
                        } catch {
                            emit(.error(error))
                        }

                    case .toolApprovalRequest(let request):
                        guard let toolCall = toolCallsById[request.toolCallId] else {
                            emit(.error(ToolCallNotFoundForApprovalError(
                                toolCallId: request.toolCallId,
                                approvalId: request.approvalId
                            )))
                            continue
                        }

                        emit(.toolApprovalRequest(ToolApprovalRequestOutput(
                            approvalId: request.approvalId,
                            toolCall: toolCall
                        )))

                    case .toolResult(let toolResultChunk):
                        let toolCallId = toolResultChunk.toolCallId
                        let storedCall = toolCallsById[toolCallId]
                        let input = toolInputs[toolCallId] ?? storedCall?.input ?? .null

                        if toolResultChunk.isError == true {
                            let errorPayload = ToolResultJSONError(value: toolResultChunk.result)
                            let typedError = makeProviderToolError(
                                storedCall: storedCall,
                                fallbackToolName: toolResultChunk.toolName,
                                toolCallId: toolCallId,
                                input: input,
                                providerExecuted: toolResultChunk.providerExecuted,
                                error: errorPayload
                            )
                            emit(.toolError(typedError))
                        } else {
                            let typedResult = makeProviderToolResult(
                                storedCall: storedCall,
                                fallbackToolName: toolResultChunk.toolName,
                                toolCallId: toolCallId,
                                input: input,
                                output: toolResultChunk.result,
                                providerExecuted: toolResultChunk.providerExecuted,
                                preliminary: toolResultChunk.preliminary,
                                providerMetadata: nil
                            )
                            emit(.toolResult(typedResult))
                        }
                    }
                }

                if let action = state.markGeneratorFinished() {
                    handleCloseAction(action)
                }
            } catch {
                state.cancelAllTasks()
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            state.cancelAllTasks()
            processingTask.cancel()
        }
    }
}

private struct ToolCallNotFoundForApprovalError: LocalizedError, Sendable {
    let toolCallId: String
    let approvalId: String

    var errorDescription: String? {
        "Tool call not found for approval: toolCallId=\(toolCallId) approvalId=\(approvalId)"
    }
}

// MARK: - State Management

private final class RunToolsTransformationState: @unchecked Sendable {
    struct CloseAction: Sendable {
        let finishChunk: SingleRequestTextStreamPart?
    }

    private let lock = NSLock()
    private var outstandingToolExecutionIds: Set<String> = []
    private var toolExecutionTasks: [String: Task<Void, Never>] = [:]
    private var finishChunk: SingleRequestTextStreamPart?
    private var generatorFinished = false
    private var closed = false

    func storeFinishChunk(_ chunk: SingleRequestTextStreamPart) {
        lock.lock()
        finishChunk = chunk
        lock.unlock()
    }

    func prepareToolExecution(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !closed else {
            return false
        }

        outstandingToolExecutionIds.insert(id)
        return true
    }

    func attachTask(_ task: Task<Void, Never>, to id: String) {
        lock.lock()
        let shouldCancel: Bool
        if closed {
            shouldCancel = true
        } else {
            toolExecutionTasks[id] = task
            shouldCancel = false
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func completeToolExecution(id: String) -> CloseAction? {
        lock.lock()
        toolExecutionTasks[id] = nil
        outstandingToolExecutionIds.remove(id)
        let action = evaluateCloseLocked()
        lock.unlock()
        return action
    }

    func markGeneratorFinished() -> CloseAction? {
        lock.lock()
        generatorFinished = true
        let action = evaluateCloseLocked()
        lock.unlock()
        return action
    }

    func cancelAllTasks() {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }

        closed = true
        let tasks = Array(toolExecutionTasks.values)
        toolExecutionTasks.removeAll()
        outstandingToolExecutionIds.removeAll()
        lock.unlock()

        for task in tasks {
            task.cancel()
        }
    }

    private func evaluateCloseLocked() -> CloseAction? {
        guard !closed else {
            return nil
        }

        guard generatorFinished, outstandingToolExecutionIds.isEmpty else {
            return nil
        }

        closed = true
        let chunk = finishChunk
        finishChunk = nil
        return CloseAction(finishChunk: chunk)
    }
}

// MARK: - Helpers

// MARK: - Error Wrappers

private struct ToolResultJSONError: LocalizedError, Sendable {
    let value: JSONValue

    var errorDescription: String? {
        switch value {
        case .string(let string):
            return string
        default:
            if let data = try? JSONEncoder().encode(value),
               let jsonString = String(data: data, encoding: .utf8) {
                return jsonString
            }
            return String(describing: value)
        }
    }
}
