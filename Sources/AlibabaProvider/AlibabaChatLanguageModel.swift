import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class AlibabaChatLanguageModel: LanguageModelV4 {
    private let identifier: AlibabaChatModelId
    private let config: AlibabaConfig
    private static let imageRegex = try! NSRegularExpression(pattern: "^https?://.*$")
    init(modelId: AlibabaChatModelId, config: AlibabaConfig) { identifier = modelId; self.config = config }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] { ["image/*": [Self.imageRegex]] }

    private struct Request { let body: JSONObject; let warnings: [SharedV4Warning] }
    private func prepare(_ call: LanguageModelV4CallOptions) async throws -> Request {
        var warnings: [SharedV4Warning] = []
        let cache = CacheControlValidator()
        let options = try await parseProviderOptions(provider: "alibaba", providerOptions: call.providerOptions, schema: alibabaLanguageModelChatOptions)
        if call.frequencyPenalty != nil { warnings.append(.unsupported(feature: "frequencyPenalty", details: nil)) }
        let preserve: Bool? = options?.preserveThinking ?? (supportsAlibabaPreservedThinking(modelId) ? true : nil)
        var prompt = call.prompt
        var format: JSONValue?
        if case .json(let schema, let name, let description) = call.responseFormat {
            if let schema, supportsAlibabaJSONSchema(modelId) {
                var value: JSONObject = ["schema": schema, "name": .string(name ?? "response")]
                if let description { value["description"] = .string(description) }
                format = ["type": "json_schema", "json_schema": .object(value)]
            } else {
                if schema != nil {
                    warnings.append(.compatibility(feature: "responseFormat JSON schema", details: "Alibaba does not support JSON Schema output for model \(modelId). JSON Object mode is used instead. The schema was injected into the system message and will only be validated locally."))
                }
                prompt = injectJSONInstructionIntoMessages(messages: prompt, schema: schema)
                format = ["type": "json_object"]
            }
        }
        var body: JSONObject = ["model": .string(modelId)]
        if let value = call.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if let value = call.temperature { body["temperature"] = .number(value) }
        if let value = call.topP { body["top_p"] = .number(value) }
        if let value = call.topK { body["top_k"] = .number(Double(value)) }
        if let value = call.presencePenalty { body["presence_penalty"] = .number(value) }
        if let value = call.stopSequences { body["stop"] = .array(value.map(JSONValue.string)) }
        if let value = call.seed { body["seed"] = .number(Double(value)) }
        if let format { body["response_format"] = format }
        if options?.enableThinking != nil || options?.thinkingBudget != nil {
            if let value = options?.enableThinking { body["enable_thinking"] = .bool(value) }
            if let value = options?.thinkingBudget { body["thinking_budget"] = .number(value) }
        } else if let reasoning = call.reasoning, isCustomReasoning(reasoning) {
            if reasoning == .none { body["enable_thinking"] = false }
            else {
                body["enable_thinking"] = true
                if let budget = mapReasoningToProviderBudget(reasoning: reasoning, maxOutputTokens: 16384, maxReasoningBudget: 16384, warnings: &warnings) { body["thinking_budget"] = .number(Double(budget)) }
            }
        }
        if let preserve { body["preserve_thinking"] = .bool(preserve) }
        body["messages"] = .array(try convertToAlibabaChatMessages(prompt: prompt, cacheControlValidator: cache, preserveThinking: preserve ?? false))
        let tools = prepareAlibabaTools(call.tools, choice: call.toolChoice)
        if let values = tools.tools {
            body["tools"] = .array(values)
            if let parallel = options?.parallelToolCalls { body["parallel_tool_calls"] = .bool(parallel) }
        }
        if let choice = tools.choice { body["tool_choice"] = choice }
        return .init(body: body, warnings: warnings + cache.getWarnings() + tools.warnings)
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let request = try await prepare(options)
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(request.body), failedResponseHandler: alibabaFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: alibabaChatResponseSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        guard let choice = response.value.choices.first else { throw InvalidResponseDataError(data: response.rawValue, message: "Alibaba response did not include choices") }
        var content: [LanguageModelV4Content] = []
        if let text = choice.message.content, !text.isEmpty { content.append(.text(.init(text: text))) }
        if let text = choice.message.reasoning, !text.isEmpty { content.append(.reasoning(.init(text: text))) }
        for call in choice.message.tools ?? [] {
            content.append(.toolCall(.init(toolCallId: call.id.isEmpty ? generateID() : call.id, toolName: call.function.name, input: call.function.arguments)))
        }
        let value = response.value
        return .init(content: content, finishReason: .init(unified: mapAlibabaFinishReason(choice.finish), raw: choice.finish), usage: convertAlibabaUsage(value.usage?.value),
                     request: .init(body: try alibabaJSONString(request.body)), response: .init(id: value.id, timestamp: value.created.map { Date(timeIntervalSince1970: $0) }, modelId: value.model, headers: response.responseHeaders, body: response.rawValue), warnings: request.warnings)
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let request = try await prepare(options)
        var body = request.body
        body["stream"] = true
        if config.includeUsage { body["stream_options"] = ["include_usage": true] }
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: alibabaFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: alibabaChatChunkSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: request.warnings))
            let task = Task {
                let tracker = StreamingToolCallTracker(enqueue: { continuation.yield($0) })
                var finish = LanguageModelV4FinishReason(unified: .other)
                var usage: AlibabaUsage?
                var first = true
                var activeText = false
                var reasoning: String?
                do {
                    for try await result in response.value {
                        if options.includeRawChunks == true {
                            switch result {
                            case .success(_, let raw): continuation.yield(.raw(rawValue: try jsonValue(from: raw)))
                            case .failure(_, let raw): if let raw { continuation.yield(.raw(rawValue: try jsonValue(from: raw))) }
                            }
                        }
                        switch result {
                        case .failure(let error, _): continuation.yield(.error(error: .error(error)))
                        case .success(let value, _):
                            if first {
                                first = false
                                continuation.yield(.responseMetadata(id: value.id, modelId: value.model, timestamp: value.created.map { Date(timeIntervalSince1970: $0) }))
                            }
                            if let value = value.usage { usage = value.value }
                            guard let choice = value.choices.first else { continue }
                            let delta = choice.delta
                            if let text = delta.reasoning, !text.isEmpty {
                                if reasoning == nil {
                                    if activeText { continuation.yield(.textEnd(id: "0", providerMetadata: nil)); activeText = false }
                                    let id = generateID(); reasoning = id
                                    continuation.yield(.reasoningStart(id: id, providerMetadata: nil))
                                }
                                if let id = reasoning { continuation.yield(.reasoningDelta(id: id, delta: text, providerMetadata: nil)) }
                            }
                            if let text = delta.content, !text.isEmpty {
                                if let id = reasoning { continuation.yield(.reasoningEnd(id: id, providerMetadata: nil)); reasoning = nil }
                                if !activeText { continuation.yield(.textStart(id: "0", providerMetadata: nil)); activeText = true }
                                continuation.yield(.textDelta(id: "0", delta: text, providerMetadata: nil))
                            }
                            if let tools = delta.tools, !tools.isEmpty {
                                if let id = reasoning { continuation.yield(.reasoningEnd(id: id, providerMetadata: nil)); reasoning = nil }
                                if activeText { continuation.yield(.textEnd(id: "0", providerMetadata: nil)); activeText = false }
                                for tool in tools {
                                    try tracker.processDelta(.init(index: tool.index, id: tool.id, type: tool.type?.rawValue, function: tool.function.map { .init(name: $0.name, arguments: $0.arguments) }))
                                }
                            }
                            if let raw = choice.finish { finish = .init(unified: mapAlibabaFinishReason(raw), raw: raw) }
                        }
                    }
                    if let id = reasoning { continuation.yield(.reasoningEnd(id: id, providerMetadata: nil)) }
                    if activeText { continuation.yield(.textEnd(id: "0", providerMetadata: nil)) }
                    tracker.flush()
                    continuation.yield(.finish(finishReason: finish, usage: convertAlibabaUsage(usage), providerMetadata: nil))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .init(stream: stream, request: .init(body: try alibabaJSONString(body)), response: .init(headers: response.responseHeaders))
    }
}

private struct AlibabaPreparedTools {
    let tools: [JSONValue]?
    let choice: JSONValue?
    let warnings: [SharedV4Warning]
}
private func prepareAlibabaTools(_ tools: [LanguageModelV4Tool]?, choice: LanguageModelV4ToolChoice?) -> AlibabaPreparedTools {
    guard let tools, !tools.isEmpty else { return .init(tools: nil, choice: nil, warnings: []) }
    var values: [JSONValue] = []
    var warnings: [SharedV4Warning] = []
    for tool in tools {
        switch tool {
        case .function(let tool):
            var function: JSONObject = ["name": .string(tool.name), "parameters": tool.inputSchema]
            if let description = tool.description { function["description"] = .string(description) }
            if let strict = tool.strict { function["strict"] = .bool(strict) }
            values.append(["type": "function", "function": .object(function)])
        case .provider(let tool): warnings.append(.unsupported(feature: "provider-defined tool \(tool.id)", details: nil))
        }
    }
    let selected: JSONValue?
    switch choice {
    case .auto?: selected = "auto"
    case .none?: selected = "none"
    case .required?: selected = "required"
    case .tool(let name)?: selected = ["type": "function", "function": ["name": .string(name)]]
    case nil: selected = nil
    }
    return .init(tools: values, choice: selected, warnings: warnings)
}

func mapAlibabaFinishReason(_ value: String?) -> LanguageModelV4FinishReason.Unified {
    switch value {
    case "stop": .stop
    case "length": .length
    case "content_filter": .contentFilter
    case "function_call", "tool_calls": .toolCalls
    default: .other
    }
}

private struct AlibabaReportedUsage: Decodable {
    let value: AlibabaUsage
    private enum Keys: String, CodingKey { case prompt_tokens, completion_tokens, total_tokens }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        for key in [Keys.prompt_tokens, .completion_tokens, .total_tokens] { _ = try values.decode(Double.self, forKey: key) }
        value = try AlibabaUsage(from: decoder)
    }
}
private enum AlibabaRole: String, Decodable { case assistant }
private enum AlibabaFunctionType: String, Decodable { case function }
private struct AlibabaChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            struct Tool: Decodable {
                struct Function: Decodable { let name: String; let arguments: String }
                let id: String
                let type: AlibabaFunctionType
                let function: Function
            }
            let role: AlibabaRole?
            let content: String?
            let reasoning: String?
            let tools: [Tool]?
            enum CodingKeys: String, CodingKey { case role, content; case reasoning = "reasoning_content", tools = "tool_calls" }
        }
        let message: Message
        let index: Double
        let finish: String?
        enum CodingKeys: String, CodingKey { case message, index; case finish = "finish_reason" }
    }
    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: AlibabaReportedUsage?
}
private struct AlibabaChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct Tool: Decodable {
                struct Function: Decodable { let name: String?; let arguments: String? }
                let index: Int?
                let id: String?
                let type: AlibabaFunctionType?
                let function: Function?
            }
            let role: AlibabaRole?
            let content: String?
            let reasoning: String?
            let tools: [Tool]?
            enum CodingKeys: String, CodingKey { case role, content; case reasoning = "reasoning_content", tools = "tool_calls" }
        }
        let delta: Delta
        let index: Double
        let finish: String?
        enum CodingKeys: String, CodingKey { case delta, index; case finish = "finish_reason" }
    }
    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: AlibabaReportedUsage?
}
private let alibabaChatResponseSchema = FlexibleSchema(Schema<AlibabaChatResponse>.codable(AlibabaChatResponse.self, jsonSchema: ["type": "object"]))
private let alibabaChatChunkSchema = FlexibleSchema(Schema<AlibabaChatChunk>.codable(AlibabaChatChunk.self, jsonSchema: ["type": "object"]))
