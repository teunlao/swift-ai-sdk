import Foundation
import AISDKProvider

struct OpenResponsesStream {
    private final class ToolState {
        var name: String?
        var callId: String?
        var input: String
        init(name: String? = nil, callId: String? = nil, input: String = "") { self.name = name; self.callId = callId; self.input = input }
    }
    private let config: OpenResponsesConfig
    private let extensionState = Experimental_OpenResponsesExtensionStreamState()
    private var usage = LanguageModelV4Usage()
    private var activeReasoning: String?
    private var hasToolCalls = false
    private var finishReason = LanguageModelV4FinishReason(unified: .other)
    private var functions: [String: ToolState] = [:]
    private var customs: [String: ToolState] = [:]

    init(config: OpenResponsesConfig) { self.config = config }

    mutating func process(_ raw: JSONValue) async throws -> [LanguageModelV4StreamPart] {
        guard raw != .null else { throw InvalidResponseDataError(data: raw, message: "Expected an Open Responses stream event") }
        guard case .object(let fields) = raw, let type = openResponsesString(fields["type"]) else { return [] }
        if let event = Experimental_OpenResponsesExtensionEvent(wire: fields), let capability = config.extensions.byEventType[event.type] {
            do {
                let decoded = try await capability.decode(event, extensionState) ?? []
                hasToolCalls = hasToolCalls || decoded.contains(where: \.signalsToolCall)
                return decoded.map(\.value)
            } catch { return [.error(error: .error(error))] }
        }
        var parts: [LanguageModelV4StreamPart] = []
        switch type {
        case "response.output_item.added", "response.output_item.done":
            guard case .object(let item) = fields["item"] else { throw InvalidResponseDataError(data: raw, message: "Expected stream output item") }
            let output = try OpenResponsesOutputItem(item)
            let added = type == "response.output_item.added"
            switch output {
            case .function(let value):
                let itemId = try required(value.id, data: raw, name: "item id")
                if added { functions[itemId] = ToolState(name: value.name, callId: value.callId, input: value.arguments ?? "") }
                else {
                    let state = functions[itemId]
                    let arguments = try required(value.arguments, data: raw, name: "function arguments")
                    let name = try required(state?.name ?? value.name, data: raw, name: "function name")
                    let callId = try required(state?.callId ?? value.callId, data: raw, name: "function call id")
                    parts.append(.toolCall(.init(toolCallId: callId, toolName: name, input: arguments.isEmpty ? state?.input ?? "" : arguments, providerMetadata: openResponsesItemMetadata(id: itemId, namespace: config.providerOptionsName))))
                    hasToolCalls = true
                    functions.removeValue(forKey: itemId)
                }
            case .custom(let value):
                let itemId = try required(value.id, data: raw, name: "item id")
                if added {
                    let name = try required(value.name, data: raw, name: "custom tool name")
                    let callId = try required(value.callId, data: raw, name: "custom tool call id")
                    customs[itemId] = ToolState(name: name, callId: callId, input: value.input ?? "")
                    parts.append(.toolInputStart(id: callId, toolName: name, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil))
                } else {
                    let state = customs[itemId]
                    let input = try required(value.input, data: raw, name: "custom tool input")
                    let name = try required(state?.name ?? value.name, data: raw, name: "custom tool name")
                    let callId = try required(state?.callId ?? value.callId, data: raw, name: "custom tool call id")
                    parts += [.toolInputEnd(id: callId, providerMetadata: nil), .toolCall(.init(toolCallId: callId, toolName: name, input: try openResponsesJSONString(input.isEmpty ? state?.input ?? "" : input), providerMetadata: openResponsesItemMetadata(id: itemId, namespace: config.providerOptionsName)))]
                    hasToolCalls = true
                    customs.removeValue(forKey: itemId)
                }
            case .reasoning(let value):
                let id = try required(value.id, data: raw, name: "reasoning item id")
                if added { activeReasoning = id; parts.append(.reasoningStart(id: id, providerMetadata: nil)) }
                else {
                    parts.append(.reasoningEnd(id: id, providerMetadata: try openResponsesReasoningMetadata(value, namespace: config.providerOptionsName)))
                    if activeReasoning == id { activeReasoning = nil }
                }
            case .message(let value):
                let id = try required(value.id, data: raw, name: "message item id")
                if added { parts.append(.textStart(id: id, providerMetadata: nil)) }
                else {
                    guard let content = value.content else { throw InvalidResponseDataError(data: raw, message: "Expected completed message content") }
                    parts.append(.textEnd(id: id, providerMetadata: openResponsesItemMetadata(id: id, annotations: content.flatMap { $0.annotations ?? [] }, namespace: config.providerOptionsName)))
                }
            case .other(let fields):
                if !added, let item = Experimental_OpenResponsesExtensionItem(wire: fields), config.extensions.byItemType[item.type] != nil {
                    do {
                        let decoded = try await config.extensions.decode(item, mode: .stream, namespace: config.providerOptionsName) ?? []
                        hasToolCalls = hasToolCalls || decoded.contains(where: \.isToolCall)
                        parts += decoded.map(\.streamPart)
                    } catch { parts.append(.error(error: .error(error))) }
                }
            }
        case "response.function_call_arguments.delta", "response.function_call_arguments.done":
            let id = try required(openResponsesString(fields["item_id"]), data: raw, name: "item id")
            let input = try required(openResponsesString(fields[type.hasSuffix(".delta") ? "delta" : "arguments"]), data: raw, name: "function input")
            let state = functions[id] ?? ToolState()
            if type.hasSuffix(".delta") { state.input += input } else { state.input = input }
            functions[id] = state
        case "response.custom_tool_call_input.delta", "response.custom_tool_call_input.done":
            let id = try required(openResponsesString(fields["item_id"]), data: raw, name: "item id")
            let input = try required(openResponsesString(fields[type.hasSuffix(".delta") ? "delta" : "input"]), data: raw, name: "custom input")
            let state = customs[id] ?? ToolState()
            if type.hasSuffix(".delta") {
                state.input += input
                parts.append(.toolInputDelta(id: state.callId ?? id, delta: input, providerMetadata: nil))
            } else { state.input = input }
            customs[id] = state
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            let id = try required(openResponsesString(fields["item_id"]), data: raw, name: "reasoning item id")
            let delta = try required(openResponsesString(fields["delta"]), data: raw, name: "reasoning delta")
            parts.append(.reasoningDelta(id: id, delta: delta, providerMetadata: nil))
        case "response.output_text.delta":
            let id = try required(openResponsesString(fields["item_id"]), data: raw, name: "message item id")
            let delta = try required(openResponsesString(fields["delta"]), data: raw, name: "text delta")
            parts.append(.textDelta(id: id, delta: delta, providerMetadata: nil))
        case "response.completed", "response.incomplete":
            guard case .object(let response) = fields["response"] else { throw InvalidResponseDataError(data: raw, message: "Expected terminal response") }
            let reason = openResponsesString(openResponsesObject(response["incomplete_details"])?["reason"])
            finishReason = .init(unified: mapOpenResponsesFinishReason(finishReason: reason, hasToolCalls: hasToolCalls), raw: reason)
            try updateUsage(response["usage"])
        case "response.failed":
            guard case .object(let response) = fields["response"] else { throw InvalidResponseDataError(data: raw, message: "Expected failed response") }
            let error = try openResponsesTruthy(response["error"]) ? response["error"].map(OpenResponsesResponseError.init(wire:)) : nil
            finishReason = .init(unified: .error, raw: error?.code ?? openResponsesString(response["status"]))
            try updateUsage(response["usage"])
            if let error { parts.append(.error(error: .providerStreamError(try streamError(error, type: type, raw: raw)))) }
        case "error":
            guard let payload = fields["error"] else { throw InvalidResponseDataError(data: raw, message: "Expected stream error") }
            let error = try OpenResponsesResponseError(wire: payload)
            finishReason = .init(unified: .error, raw: error.code)
            parts.append(.error(error: .providerStreamError(try streamError(error, type: type, raw: raw))))
        default: break
        }
        return parts
    }
    func flush() -> [LanguageModelV4StreamPart] {
        var parts: [LanguageModelV4StreamPart] = []
        if let activeReasoning { parts.append(.reasoningEnd(id: activeReasoning, providerMetadata: nil)) }
        parts.append(.finish(finishReason: finishReason, usage: usage, providerMetadata: nil))
        return parts
    }
    private mutating func updateUsage(_ value: JSONValue?) throws {
        if let value, openResponsesTruthy(value) { usage = try OpenResponsesUsage(value).value }
    }
    private func streamError(_ error: OpenResponsesResponseError, type: String, raw: JSONValue) throws -> ProviderStreamError {
        let metadata = try config.getResponseErrorMetadata?(error)
        return .init(message: error.message, type: type, code: error.code.map(ProviderStreamError.Code.string), statusCode: metadata?.statusCode, isRetryable: metadata?.isRetryable, data: raw)
    }
    private func required(_ value: String?, data: JSONValue, name: String) throws -> String {
        guard let value else { throw InvalidResponseDataError(data: data, message: "Expected \(name)") }
        return value
    }
}
