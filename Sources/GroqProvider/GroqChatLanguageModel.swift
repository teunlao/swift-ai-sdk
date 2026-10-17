import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GroqChatLanguageModel: LanguageModelV4 {
    struct Config: Sendable {
        struct RequestOptions { let modelId: GroqChatModelId; let path: String }
        let provider: String
        let url: @Sendable (RequestOptions) -> String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
    }
    private struct Request {
        let body: JSONObject
        let warnings: [SharedV4Warning]
        let jsonToolName: String?
    }
    private let modelIdentifier: GroqChatModelId
    private let config: Config
    private static let imageRegex = try! NSRegularExpression(pattern: "^https?://.*$")

    init(modelId: GroqChatModelId, config: Config) { modelIdentifier = modelId; self.config = config }
    public var modelId: String { modelIdentifier.rawValue }
    public var provider: String { config.provider }
    public var supportedUrls: [String: [NSRegularExpression]] { ["image/*": [Self.imageRegex]] }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let request = try await prepare(options)
        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/chat/completions")),
            headers: try headers(options.headers), body: JSONValue.object(request.body),
            failedResponseHandler: groqFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: groqChatResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        guard let choice = response.value.choices.first else {
            throw InvalidResponseDataError(data: response.rawValue, message: "Response did not contain any choices.")
        }
        var content: [LanguageModelV4Content] = []
        if request.jsonToolName == nil, let text = choice.message.content, !text.isEmpty { content.append(.text(.init(text: text))) }
        if let text = choice.message.reasoning, !text.isEmpty { content.append(.reasoning(.init(text: text))) }
        for call in choice.message.toolCalls ?? [] {
            if call.function.name == request.jsonToolName { content.append(.text(.init(text: call.function.arguments))) }
            else { content.append(.toolCall(.init(toolCallId: call.id.flatMap { $0.isEmpty ? nil : $0 } ?? generateID(), toolName: call.function.name, input: call.function.arguments))) }
        }
        let jsonOnly = request.jsonToolName != nil && content.contains { if case .text = $0 { true } else { false } }
            && !content.contains { if case .toolCall = $0 { true } else { false } } && choice.finishReason == "tool_calls"
        let metadata = groqResponseMetadata(id: response.value.id, model: response.value.model, created: response.value.created)
        return .init(content: content,
                     finishReason: .init(unified: jsonOnly ? .stop : mapGroqFinishReason(choice.finishReason), raw: choice.finishReason),
                     usage: convertGroqUsage(response.value.usage), request: .init(body: try groqJSONString(request.body)),
                     response: .init(id: metadata.id, timestamp: metadata.timestamp, modelId: metadata.modelId, headers: response.responseHeaders, body: response.rawValue),
                     warnings: request.warnings)
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let request = try await prepare(options)
        var body = request.body
        body["stream"] = true
        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/chat/completions")),
            headers: try headers(options.headers), body: JSONValue.object(body),
            failedResponseHandler: groqFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: groqChatStreamSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: request.warnings))
            let task = Task {
                let tracker = StreamingToolCallTracker(enqueue: { continuation.yield($0) }, options: .init(typeValidation: .required))
                var finish = LanguageModelV4FinishReason(unified: .other)
                var usage: GroqUsage?
                var first = true
                var activeText = false
                var activeReasoning = false
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
                            finish = .init(unified: .error)
                            continuation.yield(.error(error: .error(error)))
                        case .success(.error(let error), _):
                            finish = .init(unified: .error)
                            continuation.yield(.error(error: .providerStreamError(groqStreamError(error))))
                        case .success(.chunk(let chunk), _):
                            if first {
                                first = false
                                let metadata = groqResponseMetadata(id: chunk.id, model: chunk.model, created: chunk.created)
                                continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                            }
                            if let value = chunk.xGroq?.usage { usage = value }
                            guard let choice = chunk.choices.first else { continue }
                            if let reason = choice.finishReason { finish = .init(unified: mapGroqFinishReason(reason), raw: reason) }
                            guard let delta = choice.delta else { continue }
                            if let text = delta.reasoning, !text.isEmpty {
                                if !activeReasoning { continuation.yield(.reasoningStart(id: "reasoning-0", providerMetadata: nil)); activeReasoning = true }
                                continuation.yield(.reasoningDelta(id: "reasoning-0", delta: text, providerMetadata: nil))
                            }
                            if let text = delta.content, !text.isEmpty {
                                if activeReasoning { continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil)); activeReasoning = false }
                                if !activeText { continuation.yield(.textStart(id: "txt-0", providerMetadata: nil)); activeText = true }
                                continuation.yield(.textDelta(id: "txt-0", delta: text, providerMetadata: nil))
                            }
                            if let tools = delta.toolCalls, !tools.isEmpty {
                                if activeReasoning { continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil)); activeReasoning = false }
                                for tool in tools {
                                    try tracker.processDelta(.init(index: tool.index, id: tool.id, type: tool.type?.rawValue, function: .init(name: tool.function.name, arguments: tool.function.arguments)))
                                }
                            }
                        }
                    }
                    if activeReasoning { continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil)) }
                    if activeText { continuation.yield(.textEnd(id: "txt-0", providerMetadata: nil)) }
                    tracker.flush()
                    continuation.yield(.finish(finishReason: finish, usage: convertGroqUsage(usage), providerMetadata: nil))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .init(stream: request.jsonToolName.map { convertJsonResponseToolStream(stream, toolName: $0) } ?? stream,
                     request: .init(body: try groqJSONString(body)), response: .init(headers: response.responseHeaders))
    }

    private func headers(_ request: SharedV4Headers?) throws -> [String: String] {
        combineHeaders(try config.headers(), request?.mapValues(Optional.some)).compactMapValues { $0 }
    }

    private func prepare(_ call: LanguageModelV4CallOptions) async throws -> Request {
        let options = try await parseProviderOptions(provider: "groq", providerOptions: call.providerOptions, schema: groqLanguageModelChatOptions)
        var tools = call.tools
        var choice = call.toolChoice
        var jsonTool: String?
        if case .json(let schema?, _, let description) = call.responseFormat,
           tools?.contains(where: { if case .function = $0 { true } else { false } }) == true {
            let names = Set((tools ?? []).map { tool in switch tool { case .function(let tool): tool.name; case .provider(let tool): tool.name } })
            var name = "json"
            var suffix = 1
            while names.contains(name) { name = "json_\(suffix)"; suffix += 1 }
            jsonTool = name
            tools?.append(.function(.init(name: name, inputSchema: schema, description: description ?? "Respond with a JSON object.")))
            switch choice {
            case .tool: break
            case .none?: choice = .tool(toolName: name)
            default: choice = .required
            }
        }
        var warnings: [SharedV4Warning] = []
        let structured = options?.structuredOutputs ?? true
        if call.topK != nil { warnings.append(.unsupported(feature: "topK", details: nil)) }
        if case .json(let schema?, _, _) = call.responseFormat, !structured, jsonTool == nil {
            _ = schema
            warnings.append(.unsupported(feature: "responseFormat", details: "JSON response format schema is only supported with structuredOutputs"))
        }
        let prepared = prepareGroqTools(tools: tools, toolChoice: choice, modelId: modelIdentifier)
        var effort = options?.reasoningEffort?.rawValue
        if effort == nil, let reasoning = call.reasoning, isCustomReasoning(reasoning) {
            if reasoning == .none {
                if modelId == "qwen/qwen3.6-27b" { effort = "none" }
                else { warnings.append(.unsupported(feature: "reasoning", details: #"reasoning "none" is not supported by this model."#)) }
            } else {
                effort = mapReasoningToProviderEffort(reasoning: reasoning, effortMap: [.minimal: "low", .low: "low", .medium: "medium", .high: "high", .xhigh: "high", .max: "high"], warnings: &warnings)
            }
        }
        warnings += prepared.toolWarnings
        var body: JSONObject = ["model": .string(modelId), "messages": .array(try convertToGroqChatMessages(call.prompt))]
        if let value = call.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if let value = call.temperature { body["temperature"] = .number(value) }
        if let value = call.topP { body["top_p"] = .number(value) }
        if let value = call.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if let value = call.presencePenalty { body["presence_penalty"] = .number(value) }
        if let value = call.stopSequences { body["stop"] = .array(value.map(JSONValue.string)) }
        if let value = call.seed { body["seed"] = .number(Double(value)) }
        if let value = options?.user { body["user"] = .string(value) }
        if jsonTool != nil { body["parallel_tool_calls"] = false }
        else if let value = options?.parallelToolCalls { body["parallel_tool_calls"] = .bool(value) }
        if let value = options?.reasoningFormat { body["reasoning_format"] = .string(value.rawValue) }
        if let effort { body["reasoning_effort"] = .string(effort) }
        if let value = options?.serviceTier { body["service_tier"] = .string(value.rawValue) }
        if jsonTool == nil, case .json(let schema, let name, let description) = call.responseFormat {
            if structured, let schema {
                var jsonSchema: JSONObject = ["schema": schema, "strict": .bool(options?.strictJsonSchema ?? true), "name": .string(name ?? "response")]
                if let description { jsonSchema["description"] = .string(description) }
                body["response_format"] = ["type": "json_schema", "json_schema": .object(jsonSchema)]
            } else { body["response_format"] = ["type": "json_object"] }
        }
        if let tools = prepared.tools { body["tools"] = .array(tools) }
        if let choice = prepared.toolChoice { body["tool_choice"] = choice }
        return .init(body: body, warnings: warnings, jsonToolName: jsonTool)
    }
}

private enum GroqFunctionType: String, Decodable { case function }
private struct GroqChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            struct ToolCall: Decodable {
                struct Function: Decodable { let name: String; let arguments: String }
                let id: String?
                let type: GroqFunctionType
                let function: Function
            }
            let content: String?
            let reasoning: String?
            let toolCalls: [ToolCall]?
            enum CodingKeys: String, CodingKey { case content, reasoning; case toolCalls = "tool_calls" }
        }
        let message: Message
        let index: Int
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case message, index; case finishReason = "finish_reason" }
    }
    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: GroqUsage?
}
private struct GroqChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct ToolCall: Decodable {
                struct Function: Decodable { let name: String?; let arguments: String? }
                let index: Int
                let id: String?
                let type: GroqFunctionType?
                let function: Function
                enum CodingKeys: String, CodingKey { case index, id, type, function }
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    index = try container.decode(Int.self, forKey: .index)
                    id = try container.decodeIfPresent(String.self, forKey: .id)
                    type = container.contains(.type) ? try container.decode(GroqFunctionType.self, forKey: .type) : nil
                    function = try container.decode(Function.self, forKey: .function)
                }
            }
            let content: String?
            let reasoning: String?
            let toolCalls: [ToolCall]?
            enum CodingKeys: String, CodingKey { case content, reasoning; case toolCalls = "tool_calls" }
        }
        let index: Int
        let delta: Delta?
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case index, delta; case finishReason = "finish_reason" }
    }
    struct XGroq: Decodable { let usage: GroqUsage? }
    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let xGroq: XGroq?
    enum CodingKeys: String, CodingKey { case id, created, model, choices; case xGroq = "x_groq" }
}
private enum GroqChatEvent: Decodable {
    case chunk(GroqChatChunk)
    case error(GroqErrorData)
    init(from decoder: Decoder) throws {
        if let chunk = try? GroqChatChunk(from: decoder) { self = .chunk(chunk) }
        else { self = .error(try GroqErrorData(from: decoder)) }
    }
}
private let groqChatResponseSchema = FlexibleSchema(Schema<GroqChatResponse>.codable(GroqChatResponse.self, jsonSchema: ["type": "object"]))
private let groqChatStreamSchema = FlexibleSchema(Schema<GroqChatEvent>.codable(GroqChatEvent.self, jsonSchema: ["type": "object"]))

private struct GroqUsage: Decodable {
    let raw: JSONValue
    let prompt: Int?
    let completion: Int?
    let cache: Int?
    let reasoning: Int?
    let noCache: Int?
    let text: Int?
    private enum Keys: String, CodingKey, CaseIterable {
        case prompt = "prompt_tokens", completion = "completion_tokens", total = "total_tokens"
        case promptDetails = "prompt_tokens_details", completionDetails = "completion_tokens_details"
    }
    private struct PromptDetails: Decodable {
        let cached: Double?
        enum CodingKeys: String, CodingKey { case cached = "cached_tokens" }
    }
    private struct CompletionDetails: Decodable {
        let reasoning: Double?
        enum CodingKeys: String, CodingKey { case reasoning = "reasoning_tokens" }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let inputValue = try container.decodeIfPresent(Double.self, forKey: .prompt) ?? 0
        let outputValue = try container.decodeIfPresent(Double.self, forKey: .completion) ?? 0
        _ = try container.decodeIfPresent(Double.self, forKey: .total)
        let cacheValue = try container.decodeIfPresent(PromptDetails.self, forKey: .promptDetails)?.cached
        let reasoningValue = try container.decodeIfPresent(CompletionDetails.self, forKey: .completionDetails)?.reasoning
        prompt = Int(exactly: inputValue)
        completion = Int(exactly: outputValue)
        cache = cacheValue.flatMap(Int.init(exactly:))
        reasoning = reasoningValue.flatMap(Int.init(exactly:))
        func difference(_ lhs: Double, _ rhs: Double, clamp: Bool) -> Int? {
            if let left = Int(exactly: lhs), let right = Int(exactly: rhs) {
                let result = left.subtractingReportingOverflow(right)
                if result.overflow { return clamp && left < right ? 0 : nil }
                return clamp ? max(0, result.partialValue) : result.partialValue
            }
            return Int(exactly: clamp ? max(0, lhs - rhs) : lhs - rhs)
        }
        noCache = difference(inputValue, cacheValue ?? 0, clamp: false)
        text = reasoningValue.map { difference(outputValue, $0, clamp: true) } ?? completion
        var fields: JSONObject = [:]
        for key in Keys.allCases where container.contains(key) {
            var value = try container.decode(JSONValue.self, forKey: key)
            if case .object(let object) = value {
                let field = key == .promptDetails ? "cached_tokens" : "reasoning_tokens"
                value = .object(object.filter { $0.key == field })
            }
            fields[key.rawValue] = value
        }
        raw = .object(fields)
    }
}
private func convertGroqUsage(_ usage: GroqUsage?) -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    return .init(inputTokens: .init(total: usage.prompt, noCache: usage.noCache, cacheRead: usage.cache),
                 outputTokens: .init(total: usage.completion, text: usage.text, reasoning: usage.reasoning), raw: usage.raw)
}
private func groqStreamError(_ value: GroqErrorData) -> ProviderStreamError {
    let type = value.error.type
    let status: Int?
    let retry: Bool?
    switch type {
    case "rate_limit_error": status = 429; retry = true
    case "api_error", "internal_server_error", "server_error": status = 500; retry = true
    case "overloaded_error", "service_unavailable": status = 503; retry = true
    case "timeout", "timeout_error": status = 504; retry = true
    case "authentication_error", "invalid_api_key": status = 401; retry = false
    case "permission_error": status = 403; retry = false
    case "not_found_error", "model_not_found": status = 404; retry = false
    case "bad_request", "context_length_exceeded", "invalid_request_error": status = 400; retry = false
    default: status = nil; retry = nil
    }
    return .init(message: value.error.message, type: type, statusCode: status, isRetryable: retry,
                 data: ["error": ["message": .string(value.error.message), "type": .string(type)]])
}
