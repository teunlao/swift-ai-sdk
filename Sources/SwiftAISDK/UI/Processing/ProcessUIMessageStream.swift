import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Streaming helpers for building UI messages from streamed chunks.

 Port of `@ai-sdk/ai/src/ui/process-ui-message-stream.ts`.

 **Adaptations**:
 - Streams are represented as `AsyncThrowingStream` instead of Web `ReadableStream`.
 - Tool input/output payloads remain type-erased via `JSONValue`.
 - `onToolCall` receives the raw chunk (typed as `AnyUIMessageChunk`) since Swift lacks
   the higher-kinded generic inference used by the TypeScript version.
 */

public struct UIMessageStreamWriteOptions: Sendable, Equatable {
    public var updateStatus: Bool?

    public init(updateStatus: Bool? = nil) { self.updateStatus = updateStatus }
}

public struct StreamingUIMessageJobContext<Message: UIMessageConvertible>: Sendable {
    public let state: StreamingUIMessageState<Message>
    private let writeMessage: @Sendable (UIMessageStreamWriteOptions?) -> Void

    public init(state: StreamingUIMessageState<Message>, write: @escaping @Sendable () -> Void) {
        self.state = state
        self.writeMessage = { _ in write() }
    }

    public init(state: StreamingUIMessageState<Message>, writeWithOptions: @escaping @Sendable (UIMessageStreamWriteOptions?) -> Void) {
        self.state = state
        self.writeMessage = writeWithOptions
    }

    public func write(_ options: UIMessageStreamWriteOptions? = nil) { writeMessage(options) }
}

public typealias StreamingUIMessageJob<Message: UIMessageConvertible> =
    @Sendable (StreamingUIMessageJobContext<Message>) async throws -> Void

public final class StreamingUIMessageState<Message: UIMessageConvertible>: @unchecked Sendable {
    public var message: Message
    var activeTextPartIndices: [String: Int]
    var activeReasoningPartIndices: [String: Int]
    var partialToolCalls: [String: PartialToolCall]
    public var finishReason: FinishReason? = nil
    var didStart = false

    init(
        message: Message,
        activeTextPartIndices: [String: Int] = [:],
        activeReasoningPartIndices: [String: Int] = [:],
        partialToolCalls: [String: PartialToolCall] = [:]
    ) {
        self.message = message
        self.activeTextPartIndices = activeTextPartIndices
        self.activeReasoningPartIndices = activeReasoningPartIndices
        self.partialToolCalls = partialToolCalls
    }

    @discardableResult
    func appendPart(_ part: UIMessagePart) -> Int {
        message.parts.append(part)
        return message.parts.count - 1
    }
}

public struct PartialToolCall: Sendable {
    public var text: String
    public var toolName: String
    public var dynamic: Bool
    public var title: String?
    public var toolMetadata: JSONObject?
    public var inputEncoding: UIToolInputEncoding?

    public init(text: String, toolName: String, dynamic: Bool, title: String? = nil,
                toolMetadata: JSONObject? = nil, inputEncoding: UIToolInputEncoding? = nil) {
        self.toolMetadata = toolMetadata
        self.inputEncoding = inputEncoding
        self.text = text
        self.toolName = toolName
        self.dynamic = dynamic
        self.title = title
    }
}

public func createStreamingUIMessageState<Message: UIMessageConvertible>(
    lastMessage: Message?,
    messageId: String
) -> StreamingUIMessageState<Message> {
    if let lastMessage, lastMessage.role == .assistant {
        let state = StreamingUIMessageState(message: lastMessage.clone())
        let step = (lastMessage.parts.lastIndex(of: .stepStart) ?? -1) + 1
        for part in lastMessage.parts.dropFirst(step) {
            switch part {
            case .tool(let tool) where tool.state == .inputStreaming:
                state.partialToolCalls[tool.toolCallId] = PartialToolCall(
                    text: rawToolInput(tool.rawInput), toolName: tool.toolName, dynamic: false,
                    title: tool.title, toolMetadata: tool.toolMetadata, inputEncoding: tool.inputEncoding
                )
            case .dynamicTool(let tool) where tool.state == .inputStreaming:
                state.partialToolCalls[tool.toolCallId] = PartialToolCall(
                    text: rawToolInput(tool.rawInput), toolName: tool.toolName, dynamic: true,
                    title: tool.title, toolMetadata: tool.toolMetadata, inputEncoding: tool.inputEncoding
                )
            default: break
            }
        }
        return state
    }

    let message = Message(id: messageId, role: .assistant, metadata: nil, parts: [])
    return StreamingUIMessageState(message: message)
}

public typealias UIMessageToolCallHandler = @Sendable (AnyUIMessageChunk) async throws -> Void

/// Processes a UI message stream and yields the original chunks while updating UI message state.
///
/// Port of `@ai-sdk/ai/src/ui/process-ui-message-stream.ts`.
public func processUIMessageStream<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    runUpdateMessageJob: @escaping @Sendable (_ job: @escaping StreamingUIMessageJob<Message>) async throws -> Void,
    onError: ErrorHandler?,
    messageMetadataSchema: FlexibleSchema<JSONValue>? = nil,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]? = nil,
    onToolCall: UIMessageToolCallHandler? = nil,
    onData: (@Sendable (DataUIPart) -> Void)? = nil,
    resetStateOnMessageIdChange: Bool = false,
    resetStateOnFirstMessageStart: Bool = false
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    processUIMessageStreamImpl(
        stream: stream,
        runUpdateMessageJob: runUpdateMessageJob,
        onError: onError,
        messageMetadataSchema: messageMetadataSchema,
        dataPartSchemas: dataPartSchemas,
        onToolCall: onToolCall,
        onData: onData,
        resetStateOnMessageIdChange: resetStateOnMessageIdChange,
        resetStateOnFirstMessageStart: resetStateOnFirstMessageStart,
        onChunk: nil
    )
}

// Internal-only hook used by stream wrappers that need to run side effects in the
// processing task (e.g. to preserve upstream backpressure semantics).
func processUIMessageStreamInternal<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    runUpdateMessageJob: @escaping @Sendable (_ job: @escaping StreamingUIMessageJob<Message>) async throws -> Void,
    onError: ErrorHandler?,
    messageMetadataSchema: FlexibleSchema<JSONValue>? = nil,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]? = nil,
    onToolCall: UIMessageToolCallHandler? = nil,
    onData: (@Sendable (DataUIPart) -> Void)? = nil,
    onChunk: (@Sendable (AnyUIMessageChunk) async -> Void)?
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    processUIMessageStreamImpl(
        stream: stream,
        runUpdateMessageJob: runUpdateMessageJob,
        onError: onError,
        messageMetadataSchema: messageMetadataSchema,
        dataPartSchemas: dataPartSchemas,
        onToolCall: onToolCall,
        onData: onData,
        resetStateOnMessageIdChange: false,
        resetStateOnFirstMessageStart: false,
        onChunk: onChunk
    )
}

private func processUIMessageStreamImpl<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    runUpdateMessageJob: @escaping @Sendable (_ job: @escaping StreamingUIMessageJob<Message>) async throws -> Void,
    onError: ErrorHandler?,
    messageMetadataSchema: FlexibleSchema<JSONValue>?,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]?,
    onToolCall: UIMessageToolCallHandler?,
    onData: (@Sendable (DataUIPart) -> Void)?,
    resetStateOnMessageIdChange: Bool,
    resetStateOnFirstMessageStart: Bool,
    onChunk: (@Sendable (AnyUIMessageChunk) async -> Void)?
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    // Pull-based like upstream's TransformStream: a chunk is processed when the consumer reads it.
    pullTransform(stream) { chunk in
        try await runUpdateMessageJob { context in
            try await handleChunk(
                chunk,
                context: context,
                onError: onError,
                messageMetadataSchema: messageMetadataSchema,
                dataPartSchemas: dataPartSchemas,
                onToolCall: onToolCall,
                onData: onData,
                resetStateOnMessageIdChange: resetStateOnMessageIdChange,
                resetStateOnFirstMessageStart: resetStateOnFirstMessageStart
            )
        }

        if let onChunk {
            await onChunk(chunk)
        }

        return [chunk]
    }
}

// MARK: - Chunk Handling

private func handleChunk<Message: UIMessageConvertible>(
    _ chunk: AnyUIMessageChunk,
    context: StreamingUIMessageJobContext<Message>,
    onError: ErrorHandler?,
    messageMetadataSchema: FlexibleSchema<JSONValue>?,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]?,
    onToolCall: UIMessageToolCallHandler?,
    onData: (@Sendable (DataUIPart) -> Void)?,
    resetStateOnMessageIdChange: Bool,
    resetStateOnFirstMessageStart: Bool
) async throws {
    switch chunk {
    case .textStart(let id, let providerMetadata):
        let part = TextUIPart(text: "", state: .streaming, providerMetadata: providerMetadata)
        let index = context.state.appendPart(.text(part))
        context.state.activeTextPartIndices[id] = index
        context.write()

    case .textDelta(let id, let delta, let providerMetadata):
        guard let index = context.state.activeTextPartIndices[id] else {
            throw UIMessageStreamError(
                chunkType: "text-delta",
                chunkId: id,
                message: "Received text-delta for missing text part with ID \"\(id)\". Ensure a \"text-start\" chunk is sent before any \"text-delta\" chunks."
            )
        }

        context.state.updateTextPart(at: index) { textPart in
            textPart.text += delta
            if let metadata = providerMetadata {
                textPart.providerMetadata = metadata
            }
        }
        context.write()

    case .textEnd(let id, let providerMetadata, let citations):
        guard let index = context.state.activeTextPartIndices.removeValue(forKey: id) else {
            throw UIMessageStreamError(
                chunkType: "text-end",
                chunkId: id,
                message: "Received text-end for missing text part with ID \"\(id)\". Ensure a \"text-start\" chunk is sent before any \"text-end\" chunks."
            )
        }

        context.state.updateTextPart(at: index) { textPart in
            textPart.state = .done
            if let citations { textPart.citations = citations }
            if let metadata = providerMetadata {
                textPart.providerMetadata = metadata
            }
        }
        context.write()

    case .reasoningStart(let id, let providerMetadata):
        let part = ReasoningUIPart(text: "", state: .streaming, providerMetadata: providerMetadata, id: id)
        let index = context.state.appendPart(.reasoning(part))
        context.state.activeReasoningPartIndices[id] = index
        context.write()

    case .reasoningDelta(let id, let delta, let providerMetadata):
        guard let index = context.state.activeReasoningPartIndices[id] else {
            throw UIMessageStreamError(
                chunkType: "reasoning-delta",
                chunkId: id,
                message: "Received reasoning-delta for missing reasoning part with ID \"\(id)\". Ensure a \"reasoning-start\" chunk is sent before any \"reasoning-delta\" chunks."
            )
        }

        context.state.updateReasoningPart(at: index) { reasoningPart in
            reasoningPart.text += delta
            if let metadata = providerMetadata {
                reasoningPart.providerMetadata = metadata
            }
        }
        context.write()

    case .reasoningEnd(let id, let providerMetadata):
        guard let index = context.state.activeReasoningPartIndices.removeValue(forKey: id) else {
            throw UIMessageStreamError(
                chunkType: "reasoning-end",
                chunkId: id,
                message: "Received reasoning-end for missing reasoning part with ID \"\(id)\". Ensure a \"reasoning-start\" chunk is sent before any \"reasoning-end\" chunks."
            )
        }

        context.state.updateReasoningPart(at: index) { reasoningPart in
            reasoningPart.state = .done
            if let metadata = providerMetadata {
                reasoningPart.providerMetadata = metadata
            }
        }
        context.write()

    case .custom(let kind, let providerMetadata):
        context.state.appendPart(.custom(CustomContentUIPart(kind: kind, providerMetadata: providerMetadata)))
        context.write()

    case .reasoningFile(let url, let mediaType, let providerMetadata):
        context.state.appendPart(.reasoningFile(ReasoningFileUIPart(mediaType: mediaType, url: url, providerMetadata: providerMetadata)))
        context.write()

    case .file(let url, let mediaType, let providerMetadata):
        let part = FileUIPart(mediaType: mediaType, filename: nil, url: url, providerMetadata: providerMetadata)
        context.state.appendPart(.file(part))
        context.write()

    case .sourceUrl(let sourceId, let url, let title, let providerMetadata):
        let part = SourceUrlUIPart(
            sourceId: sourceId,
            url: url,
            title: title,
            providerMetadata: providerMetadata
        )
        context.state.appendPart(.sourceURL(part))
        context.write()

    case .sourceDocument(let sourceId, let mediaType, let title, let filename, let providerMetadata):
        let part = SourceDocumentUIPart(
            sourceId: sourceId,
            mediaType: mediaType,
            title: title,
            filename: filename,
            providerMetadata: providerMetadata
        )
        context.state.appendPart(.sourceDocument(part))
        context.write()

    case .startStep:
        context.state.appendPart(.stepStart)

    case .finishStep:
        break

    case .resetStep:
        context.state.activeTextPartIndices.removeAll()
        context.state.activeReasoningPartIndices.removeAll()
        context.state.partialToolCalls.removeAll()
        let start = (context.state.message.parts.lastIndex(of: .stepStart) ?? -1) + 1
        if start < context.state.message.parts.count {
            context.state.message.parts.removeSubrange(start...)
            context.write()
        }

    case .toolInputStart(let toolCallId, let toolName, let providerExecuted, let providerMetadata, let dynamic, let title, let toolMetadata, let inputEncoding):
        let isDynamic = dynamic ?? false
        context.state.partialToolCalls[toolCallId] = PartialToolCall(
            text: "",
            toolName: toolName,
            dynamic: isDynamic,
            title: title,
            toolMetadata: toolMetadata,
            inputEncoding: inputEncoding
        )

        if isDynamic {
            context.state.upsertDynamicToolPart(
                toolCallId: toolCallId,
                toolName: toolName,
                state: .inputStreaming,
                input: nil,
                output: nil,
                errorText: nil,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: nil,
                title: title,
                toolMetadata: toolMetadata,
                inputEncoding: inputEncoding
            )
        } else {
            context.state.upsertToolPart(
                toolCallId: toolCallId,
                toolName: toolName,
                state: .inputStreaming,
                input: nil,
                output: nil,
                rawInput: nil,
                errorText: nil,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: nil,
                title: title,
                toolMetadata: toolMetadata,
                inputEncoding: inputEncoding
            )
        }

        context.write()

    case .toolInputDelta(let toolCallId, let inputTextDelta):
        guard var partial = context.state.partialToolCalls[toolCallId] else {
            throw UIMessageStreamError(
                chunkType: "tool-input-delta",
                chunkId: toolCallId,
                message: "Received tool-input-delta for missing tool call with ID \"\(toolCallId)\". Ensure a \"tool-input-start\" chunk is sent before any \"tool-input-delta\" chunks."
            )
        }

        partial.text += inputTextDelta
        context.state.partialToolCalls[toolCallId] = partial

        let partialInput: JSONValue?
        if partial.inputEncoding == .text {
            partialInput = .string(partial.text)
        } else {
            partialInput = await parsePartialJson(partial.text).value
        }

        if partial.dynamic {
            context.state.upsertDynamicToolPart(
                toolCallId: toolCallId,
                toolName: partial.toolName,
                state: .inputStreaming,
                input: partialInput,
                output: nil,
                errorText: nil,
                providerExecuted: nil,
                providerMetadata: nil,
                preliminary: nil,
                approval: nil,
                title: partial.title,
                toolMetadata: partial.toolMetadata,
                inputEncoding: partial.inputEncoding,
                streamingRawInput: partial.text
            )
        } else {
            context.state.upsertToolPart(
                toolCallId: toolCallId,
                toolName: partial.toolName,
                state: .inputStreaming,
                input: partialInput,
                output: nil,
                rawInput: nil,
                errorText: nil,
                providerExecuted: nil,
                providerMetadata: nil,
                preliminary: nil,
                approval: nil,
                title: partial.title,
                toolMetadata: partial.toolMetadata,
                inputEncoding: partial.inputEncoding,
                streamingRawInput: partial.text
            )
        }

        context.write()

    case .toolInputAvailable(
        let toolCallId,
        let toolName,
        let input,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let title,
        let toolMetadata
    ):
        let isDynamic = dynamic ?? false
        if isDynamic {
            context.state.upsertDynamicToolPart(
                toolCallId: toolCallId,
                toolName: toolName,
                state: .inputAvailable,
                input: input,
                output: nil,
                errorText: nil,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: nil,
                title: title,
                toolMetadata: toolMetadata
            )
        } else {
            context.state.upsertToolPart(
                toolCallId: toolCallId,
                toolName: toolName,
                state: .inputAvailable,
                input: input,
                output: nil,
                rawInput: nil,
                errorText: nil,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: nil,
                title: title,
                toolMetadata: toolMetadata
            )
        }

        context.write()

        if let onToolCall, providerExecuted != true {
            try await onToolCall(chunk)
        }

    case .toolInputError(
        let toolCallId,
        let toolName,
        let input,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let errorText,
        _,
        let toolMetadata
    ):
        let invocationKind = context.state.toolInvocationKind(for: toolCallId, currentStepOnly: true)
        let isDynamic = invocationKind == .dynamic ? true : invocationKind == .tool ? false : (dynamic ?? false)
        if isDynamic {
            context.state.upsertDynamicToolPart(
                toolCallId: toolCallId,
                toolName: toolName,
                state: .outputError,
                input: input,
                output: nil,
                errorText: errorText,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: nil,
                title: nil,
                toolMetadata: toolMetadata,
                currentStepOnly: true
            )
        } else {
            context.state.upsertToolPart(
                toolCallId: toolCallId,
                toolName: toolName,
                state: .outputError,
                input: input,
                output: nil,
                rawInput: nil,
                errorText: errorText,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: nil,
                title: nil,
                toolMetadata: toolMetadata,
                currentStepOnly: true
            )
        }

        context.write()

    case .toolApprovalRequest(let approvalId, let toolCallId, let descriptor, let inputSchemaInput, let reason, let isAutomatic, let signature):
        guard let invocationKind = context.state.toolInvocationKind(for: toolCallId) else {
            throw UIMessageStreamError(
                chunkType: "tool-invocation",
                chunkId: toolCallId,
                message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
            )
        }

        switch invocationKind {
        case .tool:
            context.state.updateToolPart(with: toolCallId) { part in
                part.state = .approvalRequested
                part.approval = UIToolApproval(id: approvalId, descriptor: descriptor == .null ? nil : descriptor,
                                               requestReason: reason, isAutomatic: isAutomatic == true ? true : nil,
                                               signature: signature, inputSchemaInput: inputSchemaInput)
            }
        case .dynamic:
            context.state.updateDynamicToolPart(with: toolCallId) { part in
                part.state = .approvalRequested
                part.approval = UIToolApproval(id: approvalId, descriptor: descriptor == .null ? nil : descriptor,
                                               requestReason: reason, isAutomatic: isAutomatic == true ? true : nil,
                                               signature: signature, inputSchemaInput: inputSchemaInput)
            }
        }
        context.write()

    case .toolApprovalResponse(let approvalId, let approved, let reason, let providerExecuted, let providerMetadata):
        guard let index = context.state.message.parts.firstIndex(where: { part in
            switch part {
            case .tool(let tool): return tool.approval?.id == approvalId
            case .dynamicTool(let tool): return tool.approval?.id == approvalId
            default: return false
            }
        }) else {
            throw UIMessageStreamError(chunkType: "tool-approval-response", chunkId: approvalId,
                                       message: "No tool invocation found for approval ID \"\(approvalId)\".")
        }
        switch context.state.message.parts[index] {
        case .tool(var part):
            part.state = .approvalResponded
            part.approval?.approved = approved
            if let reason { part.approval?.reason = reason }
            if let providerExecuted { part.providerExecuted = providerExecuted }
            if let providerMetadata { part.callProviderMetadata = providerMetadata }
            context.state.message.parts[index] = .tool(part)
        case .dynamicTool(var part):
            part.state = .approvalResponded
            part.approval?.approved = approved
            if let reason { part.approval?.reason = reason }
            if let providerExecuted { part.providerExecuted = providerExecuted }
            if let providerMetadata { part.callProviderMetadata = providerMetadata }
            context.state.message.parts[index] = .dynamicTool(part)
        default: break
        }
        context.write()

    case .toolOutputAvailable(
        let toolCallId,
        let output,
        let providerExecuted,
        let providerMetadata,
        _,
        let preliminary,
        let toolMetadata
    ):
        guard let invocationKind = context.state.toolInvocationKind(for: toolCallId) else {
            throw UIMessageStreamError(
                chunkType: "tool-invocation",
                chunkId: toolCallId,
                message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
            )
        }

        switch invocationKind {
        case .dynamic:
            guard let toolPart = context.state.dynamicToolPart(for: toolCallId) else {
                throw UIMessageStreamError(
                    chunkType: "tool-invocation",
                    chunkId: toolCallId,
                    message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
                )
            }
            context.state.upsertDynamicToolPart(
                toolCallId: toolCallId,
                toolName: toolPart.toolName,
                state: .outputAvailable,
                input: toolPart.input,
                output: output,
                errorText: nil,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: preliminary,
                approval: toolPart.approval,
                title: toolPart.title,
                toolMetadata: toolMetadata ?? toolPart.toolMetadata
            )
        case .tool:
            guard let toolPart = context.state.toolPart(for: toolCallId) else {
                throw UIMessageStreamError(
                    chunkType: "tool-invocation",
                    chunkId: toolCallId,
                    message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
                )
            }
            context.state.upsertToolPart(
                toolCallId: toolCallId,
                toolName: toolPart.toolName,
                state: .outputAvailable,
                input: toolPart.input,
                output: output,
                rawInput: nil,
                errorText: nil,
                providerExecuted: providerExecuted ?? toolPart.providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: preliminary,
                approval: toolPart.approval,
                title: toolPart.title,
                toolMetadata: toolMetadata ?? toolPart.toolMetadata
            )
        }

        context.write()

    case .toolOutputError(let toolCallId, let errorText, let providerExecuted, let providerMetadata, _, let toolMetadata):
        guard let invocationKind = context.state.toolInvocationKind(for: toolCallId) else {
            throw UIMessageStreamError(
                chunkType: "tool-invocation",
                chunkId: toolCallId,
                message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
            )
        }

        switch invocationKind {
        case .dynamic:
            guard let toolPart = context.state.dynamicToolPart(for: toolCallId) else {
                throw UIMessageStreamError(
                    chunkType: "tool-invocation",
                    chunkId: toolCallId,
                    message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
                )
            }
            context.state.upsertDynamicToolPart(
                toolCallId: toolCallId,
                toolName: toolPart.toolName,
                state: .outputError,
                input: toolPart.input,
                output: nil,
                errorText: errorText,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: toolPart.approval,
                title: toolPart.title,
                toolMetadata: toolMetadata ?? toolPart.toolMetadata
            )
        case .tool:
            guard let toolPart = context.state.toolPart(for: toolCallId) else {
                throw UIMessageStreamError(
                    chunkType: "tool-invocation",
                    chunkId: toolCallId,
                    message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
                )
            }
            context.state.upsertToolPart(
                toolCallId: toolCallId,
                toolName: toolPart.toolName,
                state: .outputError,
                input: toolPart.input,
                output: nil,
                rawInput: toolPart.rawInput,
                errorText: errorText,
                providerExecuted: providerExecuted ?? toolPart.providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: toolPart.approval,
                title: toolPart.title,
                toolMetadata: toolMetadata ?? toolPart.toolMetadata
            )
        }

        context.write()

    case .toolOutputDenied(let toolCallId):
        guard let invocationKind = context.state.toolInvocationKind(for: toolCallId) else {
            throw UIMessageStreamError(
                chunkType: "tool-invocation",
                chunkId: toolCallId,
                message: "No tool invocation found for tool call ID \"\(toolCallId)\"."
            )
        }

        switch invocationKind {
        case .tool:
            context.state.updateToolPart(with: toolCallId) { part in
                part.state = .outputDenied
            }
        case .dynamic:
            context.state.updateDynamicToolPart(with: toolCallId) { part in
                part.state = .outputDenied
            }
        }
        context.write()

    case .start(let messageId, let messageMetadata):
        let shouldReset = (resetStateOnFirstMessageStart && !context.state.didStart)
            || (resetStateOnMessageIdChange && messageId != nil && messageId != context.state.message.id)
        context.state.didStart = true
        if shouldReset {
            context.state.message = Message(id: messageId ?? context.state.message.id, role: .assistant, metadata: nil, parts: [])
            context.state.activeTextPartIndices.removeAll()
            context.state.activeReasoningPartIndices.removeAll()
            context.state.partialToolCalls.removeAll()
            context.state.finishReason = nil
        }
        if let messageId {
            context.state.message.id = messageId
        }

        if let metadata = messageMetadata {
            if let merged = try await mergeMetadata(
                existing: context.state.message.metadata,
                incoming: metadata,
                schema: messageMetadataSchema,
                messageId: context.state.message.id
            ) {
                context.state.message.metadata = merged
            }
        }

        if shouldReset || messageId != nil || (messageMetadata != nil && messageMetadata != .null) {
            context.write(UIMessageStreamWriteOptions(updateStatus: false))
        }

    case .finish(let finishReason, let messageMetadata):
        if let finishReason {
            context.state.finishReason = finishReason
        }
        if let metadata = messageMetadata {
            if let merged = try await mergeMetadata(
                existing: context.state.message.metadata,
                incoming: metadata,
                schema: messageMetadataSchema,
                messageId: context.state.message.id
            ) {
                context.state.message.metadata = merged
                context.write()
            }
        }

    case .messageMetadata(let metadata):
        if let merged = try await mergeMetadata(
            existing: context.state.message.metadata,
            incoming: metadata,
            schema: messageMetadataSchema,
            messageId: context.state.message.id
        ) {
            context.state.message.metadata = merged
            context.write()
        }

    case .error(let errorText):
        onError?(UIMessageChunkError(message: errorText))

    case .data(let dataChunk):
        if let schema = dataPartSchemas?[dataChunk.typeIdentifier] {
            let index = context.state.message.parts.firstIndex { part in
                if case .data(let data) = part {
                    return data.id == dataChunk.id && data.typeIdentifier == dataChunk.typeIdentifier
                }
                return false
            } ?? context.state.message.parts.count
            _ = try await validateTypes(
                ValidateTypesOptions(
                    value: jsonValueToAny(dataChunk.data),
                    schema: schema,
                    context: TypeValidationContext(field: "message.parts[\(index)].data",
                                                   entityName: dataChunk.typeIdentifier, entityId: dataChunk.id)
                )
            )
        }

        let dataUIPart = DataUIPart(
            typeIdentifier: dataChunk.typeIdentifier,
            id: dataChunk.id,
            data: dataChunk.data
        )

        if dataChunk.transient == true {
            onData?(dataUIPart)
            break
        }

        if let index = context.state.indexOfDataPart(
            typeIdentifier: dataChunk.typeIdentifier,
            id: dataChunk.id
        ) {
            context.state.updateDataPart(at: index) { part in
                part.data = dataChunk.data
            }
        } else {
            context.state.appendPart(.data(dataUIPart))
        }

        onData?(dataUIPart)
        context.write()

    case .abort:
        // handled by caller (needed only for onFinish metadata)
        break
    }
}

// MARK: - Helpers

private func rawToolInput(_ value: JSONValue?) -> String {
    if case .string(let text) = value { return text }
    return ""
}

private func mergeMetadata(
    existing: JSONValue?,
    incoming: JSONValue,
    schema: FlexibleSchema<JSONValue>?,
    messageId: String
) async throws -> JSONValue? {
    guard incoming != .null else { return nil }
    let merged: JSONValue

    switch (existing, incoming) {
    case (.object(let base), .object(let overrides)):
        let mergedDictionary = mergeJSONObjects(base, overrides)
        merged = .object(mergedDictionary)
    case (.some, _):
        merged = incoming
    case (.none, _):
        merged = incoming
    }

    if let schema {
        _ = try await validateTypes(
            ValidateTypesOptions(
                value: jsonValueToAny(merged),
                schema: schema,
                context: TypeValidationContext(field: "message.metadata", entityId: messageId)
            )
        )
    }

    return merged
}

private func mergeJSONObjects(
    _ base: [String: JSONValue],
    _ overrides: [String: JSONValue]
) -> [String: JSONValue] {
    var result = base

    for (key, value) in overrides {
        if case .object(let baseObject) = result[key],
           case .object(let overrideObject) = value {
            result[key] = .object(mergeJSONObjects(baseObject, overrideObject))
        } else {
            result[key] = value
        }
    }

    return result
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .string(let string):
        return string
    case .number(let number):
        return number
    case .bool(let bool):
        return bool
    case .null:
        return NSNull()
    case .array(let array):
        return array.map { jsonValueToAny($0) }
    case .object(let dictionary):
        var result: [String: Any] = [:]
        for (key, entry) in dictionary {
            result[key] = jsonValueToAny(entry)
        }
        return result
    }
}

private struct UIMessageChunkError: Error, LocalizedError, CustomStringConvertible {
    let message: String

    init(message: String) {
        self.message = message
    }

    var description: String { message }
    var errorDescription: String? { message }
}

private extension StreamingUIMessageState {
    enum ToolInvocationKind {
        case tool
        case dynamic
    }

    func updateTextPart(at index: Int, _ mutate: (inout TextUIPart) -> Void) {
        guard case .text(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .text(part)
    }

    func updateReasoningPart(at index: Int, _ mutate: (inout ReasoningUIPart) -> Void) {
        guard case .reasoning(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .reasoning(part)
    }

    func updateToolPart(with toolCallId: String, mutate: (inout UIToolUIPart) -> Void) {
        guard let index = toolPartIndex(for: toolCallId),
              case .tool(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .tool(part)
    }

    func updateDynamicToolPart(with toolCallId: String, mutate: (inout UIDynamicToolUIPart) -> Void) {
        guard let index = dynamicToolPartIndex(for: toolCallId),
              case .dynamicTool(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .dynamicTool(part)
    }

    func updateDataPart(at index: Int, mutate: (inout DataUIPart) -> Void) {
        guard case .data(var part) = message.parts[index] else {
            return
        }
        mutate(&part)
        message.parts[index] = .data(part)
    }

    func toolPartIndex(for toolCallId: String, currentStepOnly: Bool = false) -> Int? {
        let start = currentStepOnly ? (message.parts.lastIndex(of: .stepStart) ?? -1) + 1 : 0
        return message.parts.indices.reversed().first { index in
            guard index >= start else { return false }
            let part = message.parts[index]
            if case .tool(let tool) = part { return tool.toolCallId == toolCallId }
            return false
        }
    }

    func dynamicToolPartIndex(for toolCallId: String, currentStepOnly: Bool = false) -> Int? {
        let start = currentStepOnly ? (message.parts.lastIndex(of: .stepStart) ?? -1) + 1 : 0
        return message.parts.indices.reversed().first { index in
            guard index >= start else { return false }
            if case .dynamicTool(let tool) = message.parts[index] { return tool.toolCallId == toolCallId }
            return false
        }
    }

    func toolPart(for toolCallId: String) -> UIToolUIPart? {
        guard let index = toolPartIndex(for: toolCallId),
              case .tool(let part) = message.parts[index] else {
            return nil
        }
        return part
    }

    func dynamicToolPart(for toolCallId: String) -> UIDynamicToolUIPart? {
        guard let index = dynamicToolPartIndex(for: toolCallId),
              case .dynamicTool(let part) = message.parts[index] else {
            return nil
        }
        return part
    }

    func toolInvocationKind(for toolCallId: String, currentStepOnly: Bool = false) -> ToolInvocationKind? {
        let start = currentStepOnly ? (message.parts.lastIndex(of: .stepStart) ?? -1) + 1 : 0
        for part in message.parts.dropFirst(start).reversed() {
            switch part {
            case .tool(let toolPart) where toolPart.toolCallId == toolCallId:
                return .tool
            case .dynamicTool(let dynamicToolPart) where dynamicToolPart.toolCallId == toolCallId:
                return .dynamic
            default:
                continue
            }
        }

        return nil
    }

    func upsertToolPart(
        toolCallId: String,
        toolName: String,
        state: UIToolInvocationState,
        input: JSONValue?,
        output: JSONValue?,
        rawInput: JSONValue?,
        errorText: String?,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        preliminary: Bool?,
        approval: UIToolApproval?,
        title: String?,
        toolMetadata: JSONObject? = nil,
        inputEncoding: UIToolInputEncoding? = nil,
        streamingRawInput: String? = nil,
        currentStepOnly: Bool = false
    ) {
        if let index = toolPartIndex(for: toolCallId, currentStepOnly: currentStepOnly || state == .inputStreaming || state == .inputAvailable),
           case .tool(var part) = message.parts[index] {
            part.state = state
            if let toolMetadata { part.toolMetadata = toolMetadata }
            part.inputEncoding = inputEncoding
            part.input = input
            part.output = output
            part.rawInput = streamingRawInput.map(JSONValue.string) ?? rawInput
            part.errorText = errorText
            if let providerExecuted { part.providerExecuted = providerExecuted }
            if let providerMetadata {
                if state == .outputAvailable || state == .outputError {
                    part.resultProviderMetadata = providerMetadata
                } else {
                    part.callProviderMetadata = providerMetadata
                }
            }
            part.preliminary = preliminary
            if let approval { part.approval = approval }
            if let title { part.title = title }
            message.parts[index] = .tool(part)
        } else {
            let part = UIToolUIPart(
                toolName: toolName,
                toolCallId: toolCallId,
                state: state,
                input: input,
                output: output,
                rawInput: streamingRawInput.map(JSONValue.string) ?? rawInput,
                errorText: errorText,
                providerExecuted: providerExecuted,
                callProviderMetadata: state == .outputAvailable || state == .outputError ? nil : providerMetadata,
                resultProviderMetadata: state == .outputAvailable || state == .outputError ? providerMetadata : nil,
                preliminary: preliminary,
                approval: approval,
                title: title,
                toolMetadata: toolMetadata,
                inputEncoding: inputEncoding
            )
            appendPart(.tool(part))
        }
    }

    func upsertDynamicToolPart(
        toolCallId: String,
        toolName: String,
        state: UIDynamicToolInvocationState,
        input: JSONValue?,
        output: JSONValue?,
        errorText: String?,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        preliminary: Bool?,
        approval: UIToolApproval?,
        title: String?,
        toolMetadata: JSONObject? = nil,
        inputEncoding: UIToolInputEncoding? = nil,
        streamingRawInput: String? = nil,
        currentStepOnly: Bool = false
    ) {
        if let index = dynamicToolPartIndex(for: toolCallId, currentStepOnly: currentStepOnly || state == .inputStreaming || state == .inputAvailable),
           case .dynamicTool(var part) = message.parts[index] {
            part.state = state
            if let toolMetadata { part.toolMetadata = toolMetadata }
            part.inputEncoding = inputEncoding
            part.rawInput = streamingRawInput.map(JSONValue.string)
            part.input = input
            part.output = output
            part.errorText = errorText
            if let providerExecuted { part.providerExecuted = providerExecuted }
            if let providerMetadata {
                if state == .outputAvailable || state == .outputError {
                    part.resultProviderMetadata = providerMetadata
                } else {
                    part.callProviderMetadata = providerMetadata
                }
            }
            part.preliminary = preliminary
            if let approval { part.approval = approval }
            if let title { part.title = title }
            part.toolName = toolName
            message.parts[index] = .dynamicTool(part)
        } else {
            let part = UIDynamicToolUIPart(
                toolName: toolName,
                toolCallId: toolCallId,
                state: state,
                rawInput: streamingRawInput.map(JSONValue.string),
                input: input,
                output: output,
                errorText: errorText,
                providerExecuted: providerExecuted,
                callProviderMetadata: state == .outputAvailable || state == .outputError ? nil : providerMetadata,
                resultProviderMetadata: state == .outputAvailable || state == .outputError ? providerMetadata : nil,
                preliminary: preliminary,
                approval: approval,
                title: title,
                toolMetadata: toolMetadata,
                inputEncoding: inputEncoding
            )
            appendPart(.dynamicTool(part))
        }
    }

    func indexOfDataPart(typeIdentifier: String, id: String?) -> Int? {
        guard let id else { return nil }
        return message.parts.firstIndex {
            switch $0 {
            case .data(let part):
                if part.typeIdentifier != typeIdentifier {
                    return false
                }
                return part.id == id
            default:
                return false
            }
        }
    }
}
