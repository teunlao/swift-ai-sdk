import Foundation
import AISDKProvider
import AISDKProviderUtils

struct PerplexityAgentStream {
    private final class TextState {
        var text = ""
        var ended = false
    }
    private let generateId: IDGenerator
    private var finishReason = LanguageModelV4FinishReason(unified: .other)
    private var usage: PerplexityUsage?
    private var hasFunctionCall = false
    private var hasMetadata = false
    private var activeReasoning: String?
    private var textStates: [String: TextState] = [:]
    private var textOrder: [String] = []
    private var emittedUrls: Set<String> = []
    private var pendingSources: [String: PerplexitySource] = [:]
    private var pendingSourceOrder: [String] = []
    private var functionCalls: Set<String> = []

    init(generateId: @escaping IDGenerator) { self.generateId = generateId }

    mutating func parsingFailed() { finishReason = .init(unified: .error) }

    mutating func process(_ event: PerplexityAgentChunk) throws -> [LanguageModelV4StreamPart] {
        var parts: [LanguageModelV4StreamPart] = []
        switch event.type {
        case "response.created", "response.in_progress":
            if let response = event.response { metadata(response, into: &parts) }
        case "response.output_text.delta":
            if let delta = event.delta {
                emitText(id: try textId(event.itemId, event.outputIndex, event.contentIndex), delta: delta, into: &parts)
            }
        case "response.output_text.done":
            finishText(id: try textId(event.itemId, event.outputIndex, event.contentIndex), text: event.text, into: &parts)
        case "response.reasoning.started":
            if let activeReasoning { parts.append(.reasoningEnd(id: activeReasoning, providerMetadata: nil)) }
            let number = try event.sequenceNumber.map(perplexityNumberString) ?? generateId()
            let id = "reasoning-\(number)"
            activeReasoning = id
            parts.append(.reasoningStart(id: id, providerMetadata: nil))
            thought(event.thought, into: &parts)
        case "response.reasoning.search_queries", "response.reasoning.fetch_url_queries": thought(event.thought, into: &parts)
        case "response.reasoning.search_results":
            thought(event.thought, into: &parts)
            for result in event.results ?? [] { emitSource(try .init(result: result, generateId: generateId), into: &parts) }
        case "response.reasoning.fetch_url_results":
            thought(event.thought, into: &parts)
            for result in event.contents ?? [] { emitSource(.init(fetched: result, generateId: generateId), into: &parts) }
        case "response.reasoning.stopped":
            thought(event.thought, into: &parts)
            if let activeReasoning { parts.append(.reasoningEnd(id: activeReasoning, providerMetadata: nil)) }
            activeReasoning = nil
        case "response.output_item.done":
            if let item = event.item {
                try finishOutput(item, index: event.outputIndex, into: &parts)
                try outputSources(item, into: &parts)
                functionCall(item, into: &parts)
            }
        case "response.completed", "response.incomplete":
            if let response = event.response {
                metadata(response, into: &parts)
                for (index, item) in response.output.enumerated() {
                    try finishOutput(item, index: Double(index), into: &parts)
                    try outputSources(item, into: &parts)
                    functionCall(item, into: &parts)
                }
                usage = response.usage
                finishReason = .init(unified: mapPerplexityFinishReason(status: response.status, incompleteReason: response.incomplete?.reason, hasFunctionCall: hasFunctionCall), raw: response.incomplete?.reason ?? response.status)
            }
        case "response.failed":
            finishReason = .init(unified: .error, raw: "failed")
            if let error = event.error { parts.append(.error(error: .value(.object(error.raw)))) }
            else { parts.append(.error(error: .error(NSError(domain: "Perplexity", code: 0, userInfo: [NSLocalizedDescriptionKey: "Perplexity response failed"])))) }
        default: break
        }
        return parts
    }

    func flush() -> [LanguageModelV4StreamPart] {
        var parts = pendingSourceOrder.compactMap { url -> LanguageModelV4StreamPart? in
            guard let source = pendingSources[url] else { return nil }
            return .source(source.value)
        }
        if let activeReasoning { parts.append(.reasoningEnd(id: activeReasoning, providerMetadata: nil)) }
        for id in textOrder where textStates[id]?.ended == false { parts.append(.textEnd(id: id, providerMetadata: nil)) }
        parts.append(.finish(finishReason: finishReason, usage: convertPerplexityUsage(usage), providerMetadata: perplexityProviderMetadata(usage)))
        return parts
    }

    private mutating func metadata(_ response: PerplexityAgentResponse, into parts: inout [LanguageModelV4StreamPart]) {
        guard !hasMetadata else { return }
        hasMetadata = true
        parts.append(.responseMetadata(id: response.id, modelId: response.model, timestamp: Date(timeIntervalSince1970: response.createdAt)))
    }
    private func textId(_ id: String?, _ outputIndex: Double?, _ contentIndex: Double?) throws -> String {
        let id = try id ?? outputIndex.map(perplexityNumberString) ?? "text"
        guard let contentIndex, contentIndex != 0 else { return id }
        return "\(id):\(try perplexityNumberString(contentIndex))"
    }
    private mutating func emitText(id: String, delta: String, into parts: inout [LanguageModelV4StreamPart]) {
        let state: TextState
        if let existing = textStates[id] {
            guard !existing.ended else { return }
            state = existing
        } else {
            state = TextState()
            textStates[id] = state
            textOrder.append(id)
            parts.append(.textStart(id: id, providerMetadata: nil))
        }
        state.text += delta
        parts.append(.textDelta(id: id, delta: delta, providerMetadata: nil))
    }
    private mutating func finishText(id: String, text: String?, into parts: inout [LanguageModelV4StreamPart]) {
        guard textStates[id]?.ended != true else { return }
        let emitted = textStates[id]?.text ?? ""
        if let text, text.utf8.starts(with: emitted.utf8), text.utf8.count > emitted.utf8.count {
            emitText(id: id, delta: String(decoding: text.utf8.dropFirst(emitted.utf8.count), as: UTF8.self), into: &parts)
        }
        if let state = textStates[id] {
            state.ended = true
            parts.append(.textEnd(id: id, providerMetadata: nil))
        }
    }
    private mutating func finishOutput(_ item: PerplexityOutputItem, index: Double?, into parts: inout [LanguageModelV4StreamPart]) throws {
        if case .message(let id, let content) = item {
            for (indexInContent, part) in (content ?? []).enumerated() where part.type == "output_text" {
                finishText(id: try textId(id, index, Double(indexInContent)), text: part.text, into: &parts)
            }
        }
    }
    private mutating func emitSource(_ source: PerplexitySource, into parts: inout [LanguageModelV4StreamPart]) {
        guard !emittedUrls.contains(source.url) else { return }
        if source.resultId != nil {
            pendingSources.removeValue(forKey: source.url)
            emittedUrls.insert(source.url)
            parts.append(.source(source.value))
        } else if pendingSources[source.url] == nil {
            pendingSources[source.url] = source
            pendingSourceOrder.append(source.url)
        }
    }
    private mutating func outputSources(_ item: PerplexityOutputItem, into parts: inout [LanguageModelV4StreamPart]) throws {
        for source in try perplexityOutputSources(item, generateId: generateId) { emitSource(source, into: &parts) }
    }
    private func thought(_ text: String?, into parts: inout [LanguageModelV4StreamPart]) {
        if let id = activeReasoning, let text { parts.append(.reasoningDelta(id: id, delta: text, providerMetadata: nil)) }
    }
    private mutating func functionCall(_ item: PerplexityOutputItem, into parts: inout [LanguageModelV4StreamPart]) {
        guard case .functionCall(let value) = item, let call = perplexityToolCall(value), !functionCalls.contains(call.toolCallId) else { return }
        functionCalls.insert(call.toolCallId)
        hasFunctionCall = true
        parts += [.toolInputStart(id: call.toolCallId, toolName: call.toolName, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
                  .toolInputDelta(id: call.toolCallId, delta: call.input, providerMetadata: nil), .toolInputEnd(id: call.toolCallId, providerMetadata: nil), .toolCall(call)]
    }
}
