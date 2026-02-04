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

public struct StreamingUIMessageJobContext<Message: UIMessageConvertible>: Sendable {
    public let state: StreamingUIMessageState<Message>
    public let write: @Sendable () -> Void

    public init(
        state: StreamingUIMessageState<Message>,
        write: @escaping @Sendable () -> Void
    ) {
        self.state = state
        self.write = write
    }
}

public typealias StreamingUIMessageJob<Message: UIMessageConvertible> =
    @Sendable (StreamingUIMessageJobContext<Message>) async throws -> Void

public final class StreamingUIMessageState<Message: UIMessageConvertible>: @unchecked Sendable {
    var message: Message
    var activeTextPartIndices: [String: Int]
    var activeReasoningPartIndices: [String: Int]
    var partialToolCalls: [String: PartialToolCall]
    var finishReason: FinishReason? = nil

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

    public init(text: String, toolName: String, dynamic: Bool, title: String? = nil) {
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
        return StreamingUIMessageState(message: lastMessage.clone())
    }

    let message = Message(id: messageId, role: .assistant, metadata: nil, parts: [])
    return StreamingUIMessageState(message: message)
}

public typealias UIMessageToolCallHandler = @Sendable (AnyUIMessageChunk) async -> Void

public func processUIMessageStream<Message: UIMessageConvertible>(
    stream: AsyncThrowingStream<AnyUIMessageChunk, Error>,
    runUpdateMessageJob: @escaping @Sendable (_ job: @escaping StreamingUIMessageJob<Message>) async throws -> Void,
    onError: ErrorHandler?,
    messageMetadataSchema: FlexibleSchema<JSONValue>? = nil,
    dataPartSchemas: [String: FlexibleSchema<JSONValue>]? = nil,
    onToolCall: UIMessageToolCallHandler? = nil,
    onData: (@Sendable (DataUIPart) -> Void)? = nil
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await chunk in stream {
                    try await runUpdateMessageJob { context in
                        try await handleChunk(
                            chunk,
                            context: context,
                            onError: onError,
                            messageMetadataSchema: messageMetadataSchema,
                            dataPartSchemas: dataPartSchemas,
                            onToolCall: onToolCall,
                            onData: onData
                        )
                    }

                    continuation.yield(chunk)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        // Ensure upstream processing halts promptly when the consumer cancels.
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                task.cancel()
            }
        }
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
    onData: (@Sendable (DataUIPart) -> Void)?
) async throws {
    switch chunk {
    case .textStart(let id, let providerMetadata):
        let part = TextUIPart(text: "", state: .streaming, providerMetadata: providerMetadata)
        let index = context.state.appendPart(.text(part))
        context.state.activeTextPartIndices[id] = index
        context.write()

    case .textDelta(let id, let delta, let providerMetadata):
        if let index = context.state.activeTextPartIndices[id] {
            context.state.updateTextPart(at: index) { textPart in
                textPart.text += delta
                if let metadata = providerMetadata {
                    textPart.providerMetadata = metadata
                }
            }
            context.write()
        }

    case .textEnd(let id, let providerMetadata):
        if let index = context.state.activeTextPartIndices.removeValue(forKey: id) {
            context.state.updateTextPart(at: index) { textPart in
                textPart.state = .done
                if let metadata = providerMetadata {
                    textPart.providerMetadata = metadata
                }
            }
            context.write()
        }

    case .reasoningStart(let id, let providerMetadata):
        let part = ReasoningUIPart(text: "", state: .streaming, providerMetadata: providerMetadata)
        let index = context.state.appendPart(.reasoning(part))
        context.state.activeReasoningPartIndices[id] = index
        context.write()

    case .reasoningDelta(let id, let delta, let providerMetadata):
        if let index = context.state.activeReasoningPartIndices[id] {
            context.state.updateReasoningPart(at: index) { reasoningPart in
                reasoningPart.text += delta
                if let metadata = providerMetadata {
                    reasoningPart.providerMetadata = metadata
                }
            }
            context.write()
        }

    case .reasoningEnd(let id, let providerMetadata):
        if let index = context.state.activeReasoningPartIndices.removeValue(forKey: id) {
            context.state.updateReasoningPart(at: index) { reasoningPart in
                reasoningPart.state = .done
                if let metadata = providerMetadata {
                    reasoningPart.providerMetadata = metadata
                }
            }
            context.write()
        }

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
        context.state.activeTextPartIndices.removeAll()
        context.state.activeReasoningPartIndices.removeAll()

    case .toolInputStart(let toolCallId, let toolName, let providerExecuted, let providerMetadata, let dynamic, let title):
        let isDynamic = dynamic ?? false
        context.state.partialToolCalls[toolCallId] = PartialToolCall(
            text: "",
            toolName: toolName,
            dynamic: isDynamic,
            title: title
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
                title: title
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
                title: title
            )
        }

        context.write()

    case .toolInputDelta(let toolCallId, let inputTextDelta):
        guard var partial = context.state.partialToolCalls[toolCallId] else {
            break
        }

        partial.text += inputTextDelta
        context.state.partialToolCalls[toolCallId] = partial

        let parsed = await parsePartialJson(partial.text)
        let partialInput = parsed.value

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
                title: partial.title
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
                title: partial.title
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
        let title
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
                title: title
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
                title: title
            )
        }

        context.write()

        if let onToolCall, providerExecuted != true {
            await onToolCall(chunk)
        }

    case .toolInputError(
        let toolCallId,
        let toolName,
        let input,
        let providerExecuted,
        let providerMetadata,
        let dynamic,
        let errorText,
        _
    ):
        let isDynamic = dynamic ?? false
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
                title: nil
            )
        } else {
            context.state.upsertToolPart(
                toolCallId: toolCallId,
                toolName: toolName,
                state: .outputError,
                input: nil,
                output: nil,
                rawInput: input,
                errorText: errorText,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata,
                preliminary: nil,
                approval: nil,
                title: nil
            )
        }

        context.write()

    case .toolApprovalRequest(let approvalId, let toolCallId):
        context.state.updateToolPart(with: toolCallId) { part in
            part.state = .approvalRequested
            part.approval = UIToolApproval(id: approvalId)
        }
        context.state.updateDynamicToolPart(with: toolCallId) { part in
            part.state = .approvalRequested
            part.approval = UIToolApproval(id: approvalId)
        }
        context.write()

    case .toolOutputAvailable(
        let toolCallId,
        let output,
        let providerExecuted,
        let dynamic,
        let preliminary
    ):
        if dynamic ?? false {
            guard let toolPart = context.state.dynamicToolPart(for: toolCallId) else {
                break
            }

            context.state.upsertDynamicToolPart(
                toolCallId: toolCallId,
                toolName: toolPart.toolName,
                state: .outputAvailable,
                input: toolPart.input,
                output: output,
                errorText: nil,
                providerExecuted: providerExecuted,
                providerMetadata: toolPart.callProviderMetadata,
                preliminary: preliminary,
                approval: toolPart.approval,
                title: toolPart.title
            )
        } else {
            guard let toolPart = context.state.toolPart(for: toolCallId) else {
                break
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
                providerMetadata: toolPart.callProviderMetadata,
                preliminary: preliminary,
                approval: toolPart.approval,
                title: toolPart.title
            )
        }

        context.write()

    case .toolOutputError(let toolCallId, let errorText, let providerExecuted, let dynamic):
        if dynamic ?? false {
            guard let toolPart = context.state.dynamicToolPart(for: toolCallId) else {
                break
            }

            context.state.upsertDynamicToolPart(
                toolCallId: toolCallId,
                toolName: toolPart.toolName,
                state: .outputError,
                input: toolPart.input,
                output: nil,
                errorText: errorText,
                providerExecuted: providerExecuted,
                providerMetadata: toolPart.callProviderMetadata,
                preliminary: toolPart.preliminary,
                approval: toolPart.approval,
                title: toolPart.title
            )
        } else {
            guard let toolPart = context.state.toolPart(for: toolCallId) else {
                break
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
                providerMetadata: toolPart.callProviderMetadata,
                preliminary: toolPart.preliminary,
                approval: toolPart.approval,
                title: toolPart.title
            )
        }

        context.write()

    case .toolOutputDenied(let toolCallId):
        context.state.updateToolPart(with: toolCallId) { part in
            part.state = .outputDenied
        }
        context.state.updateDynamicToolPart(with: toolCallId) { part in
            part.state = .outputDenied
        }
        context.write()

    case .start(let messageId, let messageMetadata):
        if let messageId {
            context.state.message.id = messageId
        }

        if let metadata = messageMetadata {
            if let merged = try await mergeMetadata(
                existing: context.state.message.metadata,
                incoming: metadata,
                schema: messageMetadataSchema
            ) {
                context.state.message.metadata = merged
            }
        }

        if messageId != nil || messageMetadata != nil {
            context.write()
        }

    case .finish(let finishReason, let messageMetadata):
        if let finishReason {
            context.state.finishReason = finishReason
        }
        if let metadata = messageMetadata {
            if let merged = try await mergeMetadata(
                existing: context.state.message.metadata,
                incoming: metadata,
                schema: messageMetadataSchema
            ) {
                context.state.message.metadata = merged
                context.write()
            }
        }

    case .messageMetadata(let metadata):
        if let merged = try await mergeMetadata(
            existing: context.state.message.metadata,
            incoming: metadata,
            schema: messageMetadataSchema
        ) {
            context.state.message.metadata = merged
            context.write()
        }

    case .error(let errorText):
        onError?(UIMessageStreamError(message: errorText))

    case .data(let dataChunk):
        if let schema = dataPartSchemas?[dataChunk.typeIdentifier] {
            _ = try await validateTypes(
                ValidateTypesOptions(
                    value: jsonValueToAny(dataChunk.data),
                    schema: schema
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

private func mergeMetadata(
    existing: JSONValue?,
    incoming: JSONValue,
    schema: FlexibleSchema<JSONValue>?
) async throws -> JSONValue? {
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
                schema: schema
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

private struct UIMessageStreamError: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

private extension StreamingUIMessageState {
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

    func toolPartIndex(for toolCallId: String) -> Int? {
        message.parts.firstIndex {
            if case .tool(let part) = $0 {
                return part.toolCallId == toolCallId
            } else {
                return false
            }
        }
    }

    func dynamicToolPartIndex(for toolCallId: String) -> Int? {
        message.parts.firstIndex {
            if case .dynamicTool(let part) = $0 {
                return part.toolCallId == toolCallId
            } else {
                return false
            }
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
        title: String?
    ) {
        if let index = toolPartIndex(for: toolCallId),
           case .tool(var part) = message.parts[index] {
            part.state = state
            part.input = input
            part.output = output
            part.rawInput = rawInput
            part.errorText = errorText
            if let providerExecuted { part.providerExecuted = providerExecuted }
            if let providerMetadata {
                part.callProviderMetadata = providerMetadata
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
                rawInput: rawInput,
                errorText: errorText,
                providerExecuted: providerExecuted,
                callProviderMetadata: providerMetadata,
                preliminary: preliminary,
                approval: approval,
                title: title
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
        title: String?
    ) {
        if let index = dynamicToolPartIndex(for: toolCallId),
           case .dynamicTool(var part) = message.parts[index] {
            part.state = state
            part.input = input
            part.output = output
            part.errorText = errorText
            if let providerExecuted { part.providerExecuted = providerExecuted }
            if let providerMetadata { part.callProviderMetadata = providerMetadata }
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
                input: input,
                output: output,
                errorText: errorText,
                providerExecuted: providerExecuted,
                callProviderMetadata: providerMetadata,
                preliminary: preliminary,
                approval: approval,
                title: title
            )
            appendPart(.dynamicTool(part))
        }
    }

    func indexOfDataPart(typeIdentifier: String, id: String?) -> Int? {
        message.parts.firstIndex {
            switch $0 {
            case .data(let part):
                if part.typeIdentifier != typeIdentifier {
                    return false
                }
                if let id {
                    return part.id == id
                } else {
                    return part.id == nil
                }
            default:
                return false
            }
        }
    }
}
