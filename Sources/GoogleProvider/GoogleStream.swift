import Foundation
import AISDKProvider

struct GoogleContentMapper {
    let names: [String]
    let generateId: @Sendable () -> String
    let codeToolName: String
    var jsonToolName: String? = nil
    var codeId: String?
    var serverId: String?

    mutating func convert(_ parts: [GoogleResponse.Part]) throws -> [LanguageModelV4Content] {
        var content: [LanguageModelV4Content] = []
        for part in parts {
            let metadata = googleThoughtMetadata(part.thoughtSignature, names: names)
            if let code = part.executableCode, let text = code.code, !text.isEmpty {
                let id = generateId()
                codeId = id
                var input: [String: JSONValue] = ["code": .string(text)]
                if let language = code.language { input["language"] = .string(language) }
                content.append(.toolCall(.init(toolCallId: id, toolName: codeToolName, input: try googleJSONString(.object(input)), providerExecuted: true)))
            } else if let result = part.codeExecutionResult, let id = codeId {
                var output: [String: JSONValue] = ["output": .string(result.output ?? "")]
                if let outcome = result.outcome { output["outcome"] = .string(outcome) }
                content.append(.toolResult(.init(toolCallId: id, toolName: codeToolName, result: .object(output))))
            } else if let text = part.text {
                if jsonToolName != nil && part.thought != true { continue }
                if text.isEmpty {
                    if let metadata, let last = content.popLast() { content.append(withMetadata(last, metadata)) }
                } else if part.thought == true { content.append(.reasoning(.init(text: text, providerMetadata: metadata))) }
                else { content.append(.text(.init(text: text, providerMetadata: metadata))) }
            } else if let call = part.functionCall, let name = call.name {
                let input = call.args ?? .object([:])
                if name == jsonToolName {
                    let text: String
                    if case .string(let string) = input { text = string } else { text = try googleJSONString(input) }
                    content.append(.text(.init(text: text, providerMetadata: metadata)))
                } else {
                    content.append(.toolCall(.init(toolCallId: call.id.flatMap { $0.isEmpty ? nil : $0 } ?? generateId(), toolName: name, input: try googleJSONString(input), providerMetadata: metadata)))
                }
            } else if let file = part.inlineData {
                if part.thought == true { content.append(.reasoningFile(.init(mediaType: file.mimeType, data: .base64(file.data), providerMetadata: metadata))) }
                else { content.append(.file(.init(mediaType: file.mimeType, data: .base64(file.data), providerMetadata: metadata))) }
            } else if let call = part.toolCall {
                let id = call.id.isEmpty ? generateId() : call.id
                serverId = id
                content.append(.toolCall(.init(toolCallId: id, toolName: "server:\(call.toolType)", input: try googleJSONString(call.args ?? .object([:])), providerExecuted: true, dynamic: true, providerMetadata: googleServerMetadata(id: id, type: call.toolType, signature: part.thoughtSignature, names: names))))
            } else if let response = part.toolResponse {
                let id = serverId ?? (response.id.isEmpty ? generateId() : response.id)
                content.append(.toolResult(.init(toolCallId: id, toolName: "server:\(response.toolType)", result: response.response ?? .object([:]), providerMetadata: googleServerMetadata(id: id, type: response.toolType, signature: part.thoughtSignature, names: names))))
                serverId = nil
            }
        }
        return content
    }

    private func withMetadata(_ content: LanguageModelV4Content, _ metadata: SharedV4ProviderMetadata) -> LanguageModelV4Content {
        switch content {
        case .text(let text): return .text(.init(text: text.text, citations: text.citations, providerMetadata: metadata))
        case .reasoning(let text): return .reasoning(.init(text: text.text, providerMetadata: metadata))
        case .file(let file): return .file(.init(mediaType: file.mediaType, data: file.data, providerMetadata: metadata))
        case .reasoningFile(let file): return .reasoningFile(.init(mediaType: file.mediaType, data: file.data, providerMetadata: metadata))
        case .toolCall(let call): return .toolCall(.init(toolCallId: call.toolCallId, toolName: call.toolName, input: call.input, providerExecuted: call.providerExecuted, dynamic: call.dynamic, providerMetadata: metadata))
        case .toolResult(let result): return .toolResult(.init(toolCallId: result.toolCallId, toolName: result.toolName, result: result.result, isError: result.isError, preliminary: result.preliminary, dynamic: result.dynamic, providerMetadata: metadata))
        default: return content
        }
    }
}

struct GoogleStreamState {
    private struct ActiveCall {
        let id: String
        let name: String
        let metadata: SharedV4ProviderMetadata?
        var accumulator = GoogleJSONAccumulator()
    }
    let names: [String]
    let generateId: @Sendable () -> String
    let codeToolName: String
    private var mapper: GoogleContentMapper
    private var finishReason = LanguageModelV4FinishReason(unified: .other)
    private var usage: [String: JSONValue]?
    private var continuedUsage: [String: JSONValue]?
    private var initialPromptTokens: JSONValue?
    private var metadata: [String: JSONValue] = ["promptFeedback": .null, "groundingMetadata": .null, "urlContextMetadata": .null, "safetyRatings": .null, "finishMessage": .null]
    private var blockReason: String?
    private var continuationToken: String?
    private var responseMetadataEmitted = false
    private var hasToolCalls = false
    private var textId: String?
    private var reasoningId: String?
    private var counter = 0
    private var sources: Set<String> = []
    private var activeCalls: [ActiveCall] = []

    init(names: [String], generateId: @escaping @Sendable () -> String, codeToolName: String) {
        self.names = names; self.generateId = generateId; self.codeToolName = codeToolName
        mapper = .init(names: names, generateId: generateId, codeToolName: codeToolName)
    }

    mutating func process(_ value: GoogleResponse) throws -> [LanguageModelV4StreamPart] {
        var output: [LanguageModelV4StreamPart] = []
        if !responseMetadataEmitted, let id = value.responseId {
            output.append(.responseMetadata(id: id, modelId: nil, timestamp: nil)); responseMetadataEmitted = true
        }
        if let usage = value.usageMetadata { self.usage = usage }
        if let feedback = value.promptFeedback, blockReason == nil {
            metadata["promptFeedback"] = feedback
            if let reason = googlePromptBlockReason(feedback) { blockReason = reason; finishReason = .init(unified: .contentFilter, raw: reason) }
        }
        let candidate = value.candidates?.first
        if let candidate {
            if let grounding = candidate.groundingMetadata { metadata["groundingMetadata"] = grounding }
            if let context = candidate.urlContextMetadata { metadata["urlContextMetadata"] = context }
            if let safety = candidate.safetyRatings { metadata["safetyRatings"] = safety }
            if let message = candidate.finishMessage { metadata["finishMessage"] = .string(message) }
            if let token = candidate.continuationToken { continuationToken = token }
        }
        guard blockReason == nil, let candidate else { return output }
        for source in googleSources(candidate.groundingMetadata, generateId: generateId) {
            if case .url(_, let url, _, _) = source, sources.insert(url).inserted { output.append(.source(source)) }
        }
        let parts = candidate.content?.parts ?? []
        for part in parts {
            let meta = googleThoughtMetadata(part.thoughtSignature, names: names)
            if part.executableCode != nil || part.codeExecutionResult != nil || part.toolCall != nil || part.toolResponse != nil {
                for content in try mapper.convert([part]) {
                    switch content { case .toolCall(let call): output.append(.toolCall(call)); case .toolResult(let result): output.append(.toolResult(result)); default: break }
                }
            } else if let text = part.text {
                if text.isEmpty {
                    if let meta, let id = textId { output.append(.textDelta(id: id, delta: "", providerMetadata: meta)) }
                } else if part.thought == true {
                    if let id = textId { output.append(.textEnd(id: id, providerMetadata: nil)); textId = nil }
                    if reasoningId == nil { reasoningId = String(counter); counter += 1; output.append(.reasoningStart(id: reasoningId!, providerMetadata: meta)) }
                    output.append(.reasoningDelta(id: reasoningId!, delta: text, providerMetadata: meta))
                } else {
                    if let id = reasoningId { output.append(.reasoningEnd(id: id, providerMetadata: nil)); reasoningId = nil }
                    if textId == nil { textId = String(counter); counter += 1; output.append(.textStart(id: textId!, providerMetadata: meta)) }
                    output.append(.textDelta(id: textId!, delta: text, providerMetadata: meta))
                }
            } else if let file = part.inlineData {
                if let id = textId { output.append(.textEnd(id: id, providerMetadata: nil)); textId = nil }
                if let id = reasoningId { output.append(.reasoningEnd(id: id, providerMetadata: nil)); reasoningId = nil }
                if part.thought == true { output.append(.reasoningFile(.init(mediaType: file.mimeType, data: .base64(file.data), providerMetadata: meta))) }
                else { output.append(.file(.init(mediaType: file.mimeType, data: .base64(file.data), providerMetadata: meta))) }
            }
        }
        for part in parts {
            guard let call = part.functionCall else { continue }
            let meta = googleThoughtMetadata(part.thoughtSignature, names: names)
            let streaming = call.partialArgs != nil || (call.name != nil && call.willContinue == true)
            let terminal = call.name == nil && call.args == nil && call.partialArgs == nil && call.willContinue == nil
            if streaming {
                if let name = call.name {
                    let id = call.id.flatMap { $0.isEmpty ? nil : $0 } ?? generateId()
                    activeCalls.append(.init(id: id, name: name, metadata: meta))
                    output.append(.toolInputStart(id: id, toolName: name, providerMetadata: meta, providerExecuted: nil, dynamic: nil, title: nil))
                }
                if let args = call.partialArgs, let index = activeCalls.indices.last {
                    let delta = try activeCalls[index].accumulator.process(args)
                    if !delta.isEmpty { output.append(.toolInputDelta(id: activeCalls[index].id, delta: delta, providerMetadata: meta)) }
                    if call.willContinue != true && args.allSatisfy({ $0.willContinue != true }) { output += try finishActiveCall() }
                }
            } else if terminal && !activeCalls.isEmpty { output += try finishActiveCall() }
            else if let name = call.name {
                let id = call.id.flatMap { $0.isEmpty ? nil : $0 } ?? generateId()
                output.append(.toolInputStart(id: id, toolName: name, providerMetadata: meta, providerExecuted: nil, dynamic: nil, title: nil))
                let input: String
                if let args = call.args {
                    if case .string(let value) = args { input = value } else { input = try googleJSONString(args) }
                    output.append(.toolInputDelta(id: id, delta: input, providerMetadata: meta))
                } else { input = "{}" }
                output.append(.toolInputEnd(id: id, providerMetadata: meta))
                output.append(.toolCall(.init(toolCallId: id, toolName: name, input: input, providerMetadata: meta)))
                hasToolCalls = true
            }
        }
        if candidate.finishReason == "CONTINUATION" {
            if continuedUsage == nil { initialPromptTokens = usage?["promptTokenCount"].flatMap { $0 == .null ? nil : $0 } }
            continuedUsage = addGoogleUsage(continuedUsage, usage); usage = nil
        }
        if let finish = candidate.finishReason { finishReason = .init(unified: mapGoogleFinishReason(finishReason: finish, hasToolCalls: hasToolCalls), raw: finish) }
        return output
    }

    private mutating func finishActiveCall() throws -> [LanguageModelV4StreamPart] {
        guard let active = activeCalls.popLast() else { return [] }
        let result = try active.accumulator.finalize()
        var output: [LanguageModelV4StreamPart] = []
        if !result.closing.isEmpty { output.append(.toolInputDelta(id: active.id, delta: result.closing, providerMetadata: active.metadata)) }
        output.append(.toolInputEnd(id: active.id, providerMetadata: active.metadata))
        output.append(.toolCall(.init(toolCallId: active.id, toolName: active.name, input: result.json, providerMetadata: active.metadata)))
        hasToolCalls = true
        return output
    }

    mutating func finish() throws -> [LanguageModelV4StreamPart] {
        usage = addGoogleUsage(continuedUsage, usage)
        var output: [LanguageModelV4StreamPart] = []
        if let id = textId { output.append(.textEnd(id: id, providerMetadata: nil)) }
        if let id = reasoningId { output.append(.reasoningEnd(id: id, providerMetadata: nil)) }
        metadata["usageMetadata"] = usage.map(JSONValue.object) ?? .null
        metadata["serviceTier"] = usage?["serviceTier"] ?? .null
        if let token = continuationToken, finishReason.raw == "MAX_TOKENS" || finishReason.raw == "CONTINUATION" { metadata["continuationToken"] = .string(token) }
        if let initialPromptTokens { metadata["initialPromptTokenCount"] = initialPromptTokens }
        output.append(.finish(finishReason: finishReason, usage: try convertGoogleUsage(usage), providerMetadata: googleProviderMetadata(metadata, names: names)))
        return output
    }
}
