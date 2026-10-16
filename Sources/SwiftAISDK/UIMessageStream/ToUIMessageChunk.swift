import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ToUIMessageChunkOptions: Sendable {
    public var tools: ToolSet?
    public var sendReasoning: Bool
    public var sendSources: Bool
    public var sendStart: Bool
    public var sendFinish: Bool
    public var onError: @Sendable (Error) -> String
    public var messageMetadata: JSONValue?
    public var responseMessageId: String?

    public init(
        tools: ToolSet? = nil, sendReasoning: Bool = true, sendSources: Bool = false,
        sendStart: Bool = true, sendFinish: Bool = true,
        onError: @escaping @Sendable (Error) -> String = { _ in "An error occurred." },
        messageMetadata: JSONValue? = nil, responseMessageId: String? = nil
    ) {
        self.tools = tools
        self.sendReasoning = sendReasoning
        self.sendSources = sendSources
        self.sendStart = sendStart
        self.sendFinish = sendFinish
        self.onError = onError
        self.messageMetadata = messageMetadata
        self.responseMessageId = responseMessageId
    }
}

public func toUIMessageChunk(
    _ part: TextStreamPart, options: ToUIMessageChunkOptions = ToUIMessageChunkOptions()
) -> AnyUIMessageChunk? {
    func dynamic(_ name: String, _ fallback: Bool?) -> Bool? {
        guard let tool = options.tools?[name] else { return fallback }
        return tool.type == .dynamic ? true : nil
    }
    switch part {
    case .textStart(let id, let metadata): return .textStart(id: id, providerMetadata: metadata)
    case .textDelta(let id, let text, let metadata): return .textDelta(id: id, delta: text, providerMetadata: metadata)
    case .textEnd(let id, let metadata): return .textEnd(id: id, providerMetadata: metadata)
    case .reasoningStart(let id, let metadata):
        return options.sendReasoning ? .reasoningStart(id: id, providerMetadata: metadata) : nil
    case .reasoningDelta(let id, let text, let metadata):
        return options.sendReasoning ? .reasoningDelta(id: id, delta: text, providerMetadata: metadata) : nil
    case .reasoningEnd(let id, let metadata):
        return options.sendReasoning ? .reasoningEnd(id: id, providerMetadata: metadata) : nil
    case .custom(let kind, let metadata): return .custom(kind: kind, providerMetadata: metadata)
    case .file(let file):
        return .file(url: "data:\(file.mediaType);base64,\(file.base64)", mediaType: file.mediaType, providerMetadata: nil)
    case .reasoningFile(let file, let metadata):
        return options.sendReasoning
            ? .reasoningFile(url: "data:\(file.mediaType);base64,\(file.base64)", mediaType: file.mediaType, providerMetadata: metadata)
            : nil
    case .source(let source):
        guard options.sendSources else { return nil }
        switch source {
        case .url(let id, let url, let title, let metadata):
            return .sourceUrl(sourceId: id, url: url, title: title, providerMetadata: metadata)
        case .document(let id, let mediaType, let title, let filename, let metadata):
            return .sourceDocument(sourceId: id, mediaType: mediaType, title: title, filename: filename, providerMetadata: metadata)
        }
    case .toolInputStart(let id, let name, let metadata, let executed, let isDynamic, let title):
        return .toolInputStart(toolCallId: id, toolName: name, providerExecuted: executed,
                               providerMetadata: metadata, dynamic: dynamic(name, isDynamic), title: title)
    case .toolInputDelta(let id, let text, _): return .toolInputDelta(toolCallId: id, inputTextDelta: text)
    case .toolCall(let call):
        if call.invalid == true {
            return .toolInputError(toolCallId: call.toolCallId, toolName: call.toolName, input: call.input,
                providerExecuted: call.providerExecuted, providerMetadata: call.providerMetadata,
                dynamic: dynamic(call.toolName, call.isDynamic),
                errorText: options.onError(call.error ?? StreamToolInputError()), title: call.title)
        }
        return .toolInputAvailable(toolCallId: call.toolCallId, toolName: call.toolName, input: call.input,
            providerExecuted: call.providerExecuted, providerMetadata: call.providerMetadata,
            dynamic: dynamic(call.toolName, call.isDynamic), title: call.title)
    case .toolResult(let result):
        return .toolOutputAvailable(toolCallId: result.toolCallId, output: result.output,
            providerExecuted: result.providerExecuted, providerMetadata: result.providerMetadata,
            dynamic: dynamic(result.toolName, result.isDynamic), preliminary: result.preliminary)
    case .toolError(let error):
        return .toolOutputError(toolCallId: error.toolCallId,
            errorText: error.providerExecuted == true ? AISDKProvider.getErrorMessage(error.error) : options.onError(error.error),
            providerExecuted: error.providerExecuted, providerMetadata: error.providerMetadata,
            dynamic: dynamic(error.toolName, error.isDynamic))
    case .toolOutputDenied(let denied): return .toolOutputDenied(toolCallId: denied.toolCallId)
    case .toolApprovalRequest(let request):
        return .toolApprovalRequest(approvalId: request.approvalId, toolCallId: request.toolCall.toolCallId)
    case .error(let error): return .error(errorText: options.onError(error))
    case .startStep: return .startStep
    case .finishStep: return .finishStep
    case .start:
        return options.sendStart ? .start(messageId: options.responseMessageId, messageMetadata: options.messageMetadata) : nil
    case .finish(let reason, _, _):
        return options.sendFinish ? .finish(finishReason: reason, messageMetadata: options.messageMetadata) : nil
    case .abort(let reason): return .abort(reason: reason)
    case .toolInputEnd, .raw: return nil
    }
}

private struct StreamToolInputError: LocalizedError {
    var errorDescription: String? { "Invalid tool input" }
}
