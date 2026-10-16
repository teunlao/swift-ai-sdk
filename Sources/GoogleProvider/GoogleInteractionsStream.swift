import Foundation
import AISDKProvider

struct GoogleInteractionsStreamState {
    private enum Kind { case pending, text, reasoning, image, function, builtinCall, builtinResult, custom, unknown }
    private struct Slot {
        var kind: Kind
        let id: String
        var fields: JSONObject = [:]
        var arguments = ""
    }
    let generateId: @Sendable () -> String
    var serviceTier: String?
    private var interactionId: String?
    private var usage: JSONObject?
    private var status: String?
    private var functionCall = false
    private var slots: [Double: Slot] = [:]
    private var emittedSources: Set<String> = []

    init(generateId: @escaping @Sendable () -> String, serviceTier: String? = nil) { self.generateId = generateId; self.serviceTier = serviceTier }

    mutating func failed(_ error: Error) -> [LanguageModelV4StreamPart] { status = "failed"; return [.error(error: .error(error))] }
    mutating func process(_ event: GoogleInteractionEvent) throws -> [LanguageModelV4StreamPart] {
        var output: [LanguageModelV4StreamPart] = []
        switch event.event_type {
        case "interaction.created":
            interactionId = interactionString(event.interaction?["id"]).flatMap { $0.isEmpty ? nil : $0 }
            output.append(.responseMetadata(id: interactionId, modelId: interactionString(event.interaction?["model"]), timestamp: interactionDate(interactionString(event.interaction?["created"]))))
        case "step.start":
            guard let index = event.index else { return [] }
            let step = event.step ?? [:]
            let type = interactionString(step["type"]) ?? ""
            let id = "\(interactionId ?? "interaction"):\(try googleJSONString(.number(index)))"
            var slot = Slot(kind: .unknown, id: id, fields: step)
            switch type {
            case "model_output":
                let initial = interactionObject(interactionArray(step["content"]).first)
                if initial?["type"] == .string("text") {
                    slot.kind = .text
                    output.append(.textStart(id: id, providerMetadata: nil))
                    output += emitSources(interactionAnnotationSources(interactionArray(initial?["annotations"]), generateId: generateId))
                } else if initial?["type"] == .string("image") { slot.kind = .image; slot.fields = initial ?? [:] }
                else { slot.kind = .pending }
            case "thought":
                slot.kind = .reasoning
                output.append(.reasoningStart(id: id, providerMetadata: nil))
                for item in interactionArray(step["summary"]).compactMap(interactionObject) {
                    if item["type"] == .string("text"), let text = interactionString(item["text"]) { output.append(.reasoningDelta(id: id, delta: text, providerMetadata: nil)) }
                }
            case "function_call":
                slot.kind = .function; functionCall = true
                slot.fields["id"] = .string(interactionString(step["id"]).flatMap { $0.isEmpty ? nil : $0 } ?? id)
                slot.fields["name"] = step["name"] ?? .string("unknown")
                output.append(.toolInputStart(id: interactionString(slot.fields["id"])!, toolName: interactionString(slot.fields["name"])!, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil))
            case "processing_call", "processing_result":
                slot.kind = .custom
                slot.fields[type == "processing_call" ? "id" : "call_id"] = .string(interactionString(step[type == "processing_call" ? "id" : "call_id"]).flatMap { $0.isEmpty ? nil : $0 } ?? id)
            default:
                if interactionBuiltinCalls.contains(type) {
                    slot.kind = .builtinCall
                    slot.fields["id"] = .string(interactionString(step["id"]).flatMap { $0.isEmpty ? nil : $0 } ?? id)
                } else if interactionBuiltinResults.contains(type) {
                    slot.kind = .builtinResult
                    slot.fields["call_id"] = .string(interactionString(step["call_id"]).flatMap { $0.isEmpty ? nil : $0 } ?? id)
                }
            }
            slots[index] = slot
        case "step.delta":
            guard let index = event.index, var slot = slots[index] else { return [] }
            let delta = event.delta ?? [:]
            let type = interactionString(delta["type"]) ?? ""
            if slot.kind == .pending && ["text", "text_annotation", "text_annotation_delta"].contains(type) {
                slot.kind = .text
                output.append(.textStart(id: slot.id, providerMetadata: nil))
            }
            if type == "image" && [.pending, .text, .image].contains(slot.kind) || type == "video" && [.pending, .text].contains(slot.kind) {
                if let file = try interactionFile(delta, id: interactionId) { output.append(.file(file)) }
                if slot.kind == .image { slot.fields.removeValue(forKey: "data"); slot.fields.removeValue(forKey: "uri") }
            } else {
                switch slot.kind {
                case .text:
                    if type == "text", let text = interactionString(delta["text"]), !text.isEmpty { output.append(.textDelta(id: slot.id, delta: text, providerMetadata: nil)) }
                    else if type == "text_annotation" || type == "text_annotation_delta" { output += emitSources(interactionAnnotationSources(interactionArray(delta["annotations"]), generateId: generateId)) }
                case .reasoning:
                    if type == "thought_summary", let content = interactionObject(delta["content"]), content["type"] == .string("text"), let text = interactionString(content["text"]) { output.append(.reasoningDelta(id: slot.id, delta: text, providerMetadata: nil)) }
                    else if type == "thought_signature", let signature = delta["signature"], signature != .null { slot.fields["signature"] = signature }
                case .function:
                    if type == "arguments_delta" {
                        if let arguments = interactionString(delta["arguments"]), !arguments.isEmpty {
                            slot.arguments += arguments
                            output.append(.toolInputDelta(id: interactionString(slot.fields["id"])!, delta: arguments, providerMetadata: nil))
                        }
                        if let id = interactionString(delta["id"]), !id.isEmpty { slot.fields["id"] = .string(id) }
                        if let signature = delta["signature"], signature != .null { slot.fields["signature"] = signature }
                        functionCall = true
                    }
                case .builtinCall, .builtinResult:
                    if delta["type"] == slot.fields["type"] {
                        for key in ["id", "call_id", "name", "arguments", "result", "is_error"] {
                            if let value = delta[key], key == "result" || value != .null { slot.fields[key] = value }
                        }
                    }
                case .custom:
                    if type == "processing_call" || type == "processing_result" {
                        for key in ["id", "call_id", "signature"] { if let value = delta[key], value != .null { slot.fields[key] = value } }
                    }
                default: break
                }
            }
            slots[index] = slot
        case "step.stop":
            guard let index = event.index, let slot = slots.removeValue(forKey: index) else { return [] }
            switch slot.kind {
            case .text: output.append(.textEnd(id: slot.id, providerMetadata: interactionPartMetadata(id: interactionId)))
            case .reasoning: output.append(.reasoningEnd(id: slot.id, providerMetadata: interactionPartMetadata(id: interactionId, signature: slot.fields["signature"])))
            case .image: if let file = try interactionFile(slot.fields, id: interactionId) { output.append(.file(file)) }
            case .function:
                let id = interactionString(slot.fields["id"])!
                output.append(.toolInputEnd(id: id, providerMetadata: nil))
                output.append(.toolCall(.init(toolCallId: id, toolName: interactionString(slot.fields["name"]) ?? "unknown", input: slot.arguments.isEmpty ? "{}" : slot.arguments, providerMetadata: interactionPartMetadata(id: interactionId, signature: slot.fields["signature"]))))
            case .builtinCall:
                let type = interactionString(slot.fields["type"]) ?? ""
                let name = type == "mcp_server_tool_call" ? interactionString(slot.fields["name"]) ?? "mcp_server_tool" : String(type.dropLast(5))
                output.append(.toolCall(.init(toolCallId: interactionString(slot.fields["id"])!, toolName: name, input: try googleJSONString(slot.fields["arguments"].flatMap { $0 == .null ? nil : $0 } ?? .object([:])), providerExecuted: true)))
            case .builtinResult:
                let type = interactionString(slot.fields["type"]) ?? ""
                let name = type == "mcp_server_tool_result" ? interactionString(slot.fields["name"]) ?? "mcp_server_tool" : String(type.dropLast(7))
                output.append(.toolResult(.init(toolCallId: interactionString(slot.fields["call_id"])!, toolName: name, result: slot.fields["result"] ?? .null)))
                output += emitSources(interactionBuiltinSources(slot.fields, generateId: generateId))
            case .custom:
                let call = slot.fields["type"] == .string("processing_call")
                output.append(.custom(.init(kind: call ? "google.processing_call" : "google.processing_result", providerMetadata: interactionPartMetadata(id: interactionId, signature: slot.fields["signature"], additional: [call ? "processingId" : "processingCallId": slot.fields[call ? "id" : "call_id"]!]))))
            default: break
            }
        case "interaction.status_update", "interaction.in_progress", "interaction.requires_action": status = event.status ?? (event.event_type == "interaction.requires_action" ? "requires_action" : "in_progress")
        case "interaction.completed":
            if let id = interactionString(event.interaction?["id"]), !id.isEmpty { interactionId = id }
            if let status = interactionString(event.interaction?["status"]) { self.status = status }
            if let usage = interactionObject(event.interaction?["usage"]) { try validateInteractionUsage(usage); self.usage = usage }
            if let tier = interactionString(event.interaction?["service_tier"]) { serviceTier = tier }
        case "error":
            status = "failed"
            let code: ProviderStreamError.Code?
            switch event.error?["code"] { case .string(let value): code = .string(value); case .number(let value): code = .number(value); default: code = nil }
            let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(event))
            output.append(.error(error: .providerStreamError(.init(message: interactionString(event.error?["message"]) ?? "Unknown interaction error", type: event.event_type, code: code, data: raw))))
        default: break
        }
        return output
    }
    private mutating func emitSources(_ sources: [LanguageModelV4Source]) -> [LanguageModelV4StreamPart] { sources.filter { emittedSources.insert(interactionSourceKey($0)).inserted }.map(LanguageModelV4StreamPart.source) }
    func finish() throws -> LanguageModelV4StreamPart { .finish(finishReason: interactionFinish(status, functionCall: functionCall), usage: try interactionUsage(usage), providerMetadata: interactionMetadata(id: interactionId, tier: serviceTier, usage: usage)) }
}

func synthesizeInteractionStream(_ response: GoogleInteractionResponse, warnings: [SharedV4Warning], generateId: @Sendable () -> String, raw: Bool, headerTier: String?) throws -> [LanguageModelV4StreamPart] {
    let id = response.id.flatMap { $0.isEmpty ? nil : $0 }
    var parts: [LanguageModelV4StreamPart] = [.streamStart(warnings: warnings), .responseMetadata(id: id, modelId: response.model, timestamp: interactionDate(response.created))]
    if raw { parts.append(.raw(rawValue: try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(response)))) }
    let parsed = try parseInteractionOutputs(response.steps, id: id, generateId: generateId)
    var counter = 0
    for content in parsed.content {
        switch content {
        case .text(let text):
            let block = "\(id ?? "agent"):\(counter)"; counter += 1
            parts.append(.textStart(id: block, providerMetadata: nil))
            if !text.text.isEmpty { parts.append(.textDelta(id: block, delta: text.text, providerMetadata: nil)) }
            parts.append(.textEnd(id: block, providerMetadata: text.providerMetadata))
        case .reasoning(let text):
            let block = "\(id ?? "agent"):\(counter)"; counter += 1
            parts.append(.reasoningStart(id: block, providerMetadata: nil))
            if !text.text.isEmpty { parts.append(.reasoningDelta(id: block, delta: text.text, providerMetadata: nil)) }
            parts.append(.reasoningEnd(id: block, providerMetadata: text.providerMetadata))
        case .toolCall(let call):
            parts.append(.toolInputStart(id: call.toolCallId, toolName: call.toolName, providerMetadata: nil, providerExecuted: call.providerExecuted, dynamic: nil, title: nil))
            parts.append(.toolInputDelta(id: call.toolCallId, delta: call.input, providerMetadata: nil))
            parts.append(.toolInputEnd(id: call.toolCallId, providerMetadata: nil))
            parts.append(.toolCall(call))
        case .toolResult(let result): parts.append(.toolResult(.init(toolCallId: result.toolCallId, toolName: result.toolName, result: result.result)))
        case .source(let source): parts.append(.source(source))
        case .file(let file): parts.append(.file(file))
        default: break
        }
    }
    parts.append(.finish(finishReason: interactionFinish(response.status, functionCall: parsed.functionCall), usage: try interactionUsage(response.usage), providerMetadata: interactionMetadata(id: id, tier: response.service_tier ?? headerTier, usage: nil, includeModalities: false)))
    return parts
}
