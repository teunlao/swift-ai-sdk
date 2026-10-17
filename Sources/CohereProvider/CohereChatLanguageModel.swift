import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class CohereChatLanguageModel: LanguageModelV4 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
        let generateId: IDGenerator
    }

    private struct Request {
        let body: JSONObject
        let warnings: [SharedV4Warning]
    }
    private let modelIdentifier: CohereChatModelId
    private let config: Config
    private static let imageRegex = try! NSRegularExpression(pattern: "^https?://.*$")
    // ECMAScript trim includes BOM and excludes U+0085.
    private static let argumentWhitespace = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")

    init(modelId: CohereChatModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] { ["image/*": [Self.imageRegex]] }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let request = try await prepare(options)
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(request.body),
            failedResponseHandler: cohereFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: cohereChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        var content: [LanguageModelV4Content] = []
        for item in response.value.message.content ?? [] {
            switch item {
            case .text(let text): if !text.isEmpty { content.append(.text(.init(text: text))) }
            case .thinking(let text): if !text.isEmpty { content.append(.reasoning(.init(text: text))) }
            }
        }
        for citation in response.value.message.citations ?? [] {
            var metadata: JSONObject = [
                "start": .number(citation.start), "end": .number(citation.end), "text": .string(citation.text),
                "sources": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(citation.sources))
            ]
            if let type = citation.type, !type.isEmpty { metadata["citationType"] = .string(type) }
            let title = citation.sources.first?.document.title ?? ""
            content.append(.source(.document(id: config.generateId(), mediaType: "text/plain", title: title.isEmpty ? "Document" : title, filename: nil, providerMetadata: ["cohere": metadata])))
        }
        for call in response.value.message.toolCalls ?? [] {
            content.append(.toolCall(.init(toolCallId: call.id, toolName: call.function.name, input: call.function.arguments == "null" ? "{}" : call.function.arguments)))
        }
        return .init(
            content: content,
            finishReason: .init(unified: mapCohereFinishReason(response.value.finishReason), raw: response.value.finishReason),
            usage: convertCohereUsage(response.value.usage),
            request: .init(body: request.body),
            response: .init(id: response.value.generationId, headers: response.responseHeaders, body: response.rawValue),
            warnings: request.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let request = try await prepare(options)
        var body = request.body
        body["stream"] = true
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: cohereFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: cohereChatEventSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: request.warnings))
            let task = Task {
                struct ToolCall {
                    let id: String
                    let name: String
                    var arguments: String
                }
                var pending: ToolCall?
                var activeReasoning = false
                var finishReason = LanguageModelV4FinishReason(unified: .other)
                var usage: CohereUsage?
                do {
                    for try await parsed in response.value {
                        if options.includeRawChunks == true {
                            switch parsed {
                            case .success(_, let raw): continuation.yield(.raw(rawValue: try jsonValue(from: raw)))
                            case .failure(_, let raw): if let raw { continuation.yield(.raw(rawValue: try jsonValue(from: raw))) }
                            }
                        }
                        switch parsed {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error)
                            continuation.yield(.error(error: .error(error)))
                        case .success(let event, _):
                            switch event {
                            case .contentStart(let index, let content):
                                let id = index == 0 ? "0" : try cohereJSONString(index)
                                if case .thinking = content {
                                    activeReasoning = true
                                    continuation.yield(.reasoningStart(id: id, providerMetadata: nil))
                                } else { continuation.yield(.textStart(id: id, providerMetadata: nil)) }
                            case .contentDelta(let index, let content):
                                let id = index == 0 ? "0" : try cohereJSONString(index)
                                switch content {
                                case .text(let text): continuation.yield(.textDelta(id: id, delta: text, providerMetadata: nil))
                                case .thinking(let text): continuation.yield(.reasoningDelta(id: id, delta: text, providerMetadata: nil))
                                }
                            case .contentEnd(let index):
                                let id = index == 0 ? "0" : try cohereJSONString(index)
                                if activeReasoning {
                                    continuation.yield(.reasoningEnd(id: id, providerMetadata: nil))
                                    activeReasoning = false
                                } else { continuation.yield(.textEnd(id: id, providerMetadata: nil)) }
                            case .toolStart(let call):
                                pending = .init(id: call.id, name: call.function.name, arguments: call.function.arguments)
                                continuation.yield(.toolInputStart(id: call.id, toolName: call.function.name, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil))
                                if !call.function.arguments.isEmpty {
                                    continuation.yield(.toolInputDelta(id: call.id, delta: call.function.arguments, providerMetadata: nil))
                                }
                            case .toolDelta(let arguments):
                                if var call = pending {
                                    call.arguments += arguments
                                    pending = call
                                    continuation.yield(.toolInputDelta(id: call.id, delta: arguments, providerMetadata: nil))
                                }
                            case .toolEnd:
                                if let call = pending {
                                    continuation.yield(.toolInputEnd(id: call.id, providerMetadata: nil))
                                    let trimmed = call.arguments.trimmingCharacters(in: Self.argumentWhitespace)
                                    let input = try await parseJSON(ParseJSONOptions(text: trimmed.isEmpty ? "{}" : trimmed))
                                    continuation.yield(.toolCall(.init(toolCallId: call.id, toolName: call.name, input: try cohereJSONString(input))))
                                    pending = nil
                                }
                            case .messageStart(let id): continuation.yield(.responseMetadata(id: id, modelId: nil, timestamp: nil))
                            case .messageEnd(let reason, let value):
                                finishReason = .init(unified: mapCohereFinishReason(reason), raw: reason)
                                usage = value
                            case .citationStart, .citationEnd, .toolPlan: break
                            }
                        }
                    }
                    continuation.yield(.finish(finishReason: finishReason, usage: convertCohereUsage(usage), providerMetadata: nil))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .init(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }

    private func prepare(_ call: LanguageModelV4CallOptions) async throws -> Request {
        let options = try await parseProviderOptions(provider: "cohere", providerOptions: call.providerOptions, schema: cohereLanguageModelChatOptions)
        let prompt = try await convertToCohereChatPrompt(call.prompt)
        let tools = prepareCohereTools(tools: call.tools, toolChoice: call.toolChoice)
        var warnings = tools.toolWarnings + prompt.warnings
        var body: JSONObject = ["model": .string(modelId), "messages": .array(prompt.messages)]
        if let value = call.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if let value = call.presencePenalty { body["presence_penalty"] = .number(value) }
        if let value = call.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if let value = call.temperature { body["temperature"] = .number(value) }
        if let value = call.topP { body["p"] = .number(value) }
        if let value = call.topK { body["k"] = .number(Double(value)) }
        if let value = call.seed { body["seed"] = .number(Double(value)) }
        if let value = call.stopSequences { body["stop_sequences"] = .array(value.map(JSONValue.string)) }
        if case .json(let schema, _, _) = call.responseFormat {
            var format: JSONObject = ["type": "json_object"]
            if let schema { format["json_schema"] = schema }
            body["response_format"] = .object(format)
        }
        if !prompt.documents.isEmpty { body["documents"] = .array(prompt.documents) }
        if let values = tools.tools { body["tools"] = .array(values) }
        if let choice = tools.toolChoice { body["tool_choice"] = .string(choice.rawValue) }
        if let thinking = options?.thinking {
            var value: JSONObject = ["type": .string(thinking.type?.rawValue ?? "enabled")]
            if let budget = thinking.tokenBudget { value["token_budget"] = .number(budget) }
            body["thinking"] = .object(value)
        } else if let reasoning = call.reasoning, isCustomReasoning(reasoning) {
            if reasoning == .none { body["thinking"] = ["type": "disabled"] }
            else if let budget = mapReasoningToProviderBudget(reasoning: reasoning, maxOutputTokens: 32768, maxReasoningBudget: 32768, warnings: &warnings) {
                body["thinking"] = ["type": "enabled", "token_budget": .number(Double(budget))]
            }
        }
        return .init(body: body, warnings: warnings)
    }
}
