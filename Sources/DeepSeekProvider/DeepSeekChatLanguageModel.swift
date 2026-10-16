import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct DeepSeekChatConfig: Sendable {
    public let provider: String
    public let headers: (@Sendable () throws -> [String: String])?
    public let url: @Sendable (DeepSeekURLOptions) throws -> String
    public let fetch: FetchFunction?
    public let supportsAssistantPrefixCompletion: Bool
    public let supportsStrictToolCalls: Bool?
    public let supportsPenaltySampling: Bool
    public let supportsThinking: Bool
    public let supportsStructuredOutputs: Bool

    public init(
        provider: String,
        headers: (@Sendable () throws -> [String: String])? = nil,
        url: @escaping @Sendable (DeepSeekURLOptions) throws -> String,
        fetch: FetchFunction? = nil,
        supportsAssistantPrefixCompletion: Bool = false,
        supportsStrictToolCalls: Bool? = nil,
        supportsPenaltySampling: Bool = false,
        supportsThinking: Bool = true,
        supportsStructuredOutputs: Bool = false
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.supportsAssistantPrefixCompletion = supportsAssistantPrefixCompletion
        self.supportsStrictToolCalls = supportsStrictToolCalls
        self.supportsPenaltySampling = supportsPenaltySampling
        self.supportsThinking = supportsThinking
        self.supportsStructuredOutputs = supportsStructuredOutputs
    }
}

public struct DeepSeekURLOptions: Sendable {
    public let modelId: String
    public let path: String
}

public final class DeepSeekChatLanguageModel: LanguageModelV4 {
    public let specificationVersion = "v4"
    public let modelId: String
    public var provider: String { config.provider }
    public var supportedUrls: [String: [NSRegularExpression]] {
        ["image/*": [try! NSRegularExpression(pattern: "^https?://.*$")]]
    }
    private let config: DeepSeekChatConfig
    private var providerOptionsName: String {
        config.provider.split(separator: ".").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    public init(modelId: DeepSeekChatModelId, config: DeepSeekChatConfig) {
        self.modelId = modelId.rawValue
        self.config = config
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let (body, warnings) = try await prepare(options)
        let response = try await postJsonToAPI(
            url: try config.url(.init(modelId: modelId, path: "/chat/completions")),
            headers: try headers(options.headers), body: JSONValue.object(body),
            failedResponseHandler: deepSeekFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: deepSeekResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let value = response.value
        guard let choice = value.choices.first else {
            throw InvalidResponseDataError(data: response.rawValue, message: "Response did not contain any choices.")
        }
        var content: [LanguageModelV4Content] = []
        if let reasoning = choice.message.reasoningContent, !reasoning.isEmpty {
            content.append(.reasoning(.init(text: reasoning)))
        }
        for tool in choice.message.toolCalls ?? [] {
            content.append(.toolCall(.init(toolCallId: tool.id.flatMap { $0.isEmpty ? nil : $0 } ?? generateID(),
                                           toolName: tool.function.name, input: tool.function.arguments)))
        }
        if let text = choice.message.content, !text.isEmpty {
            content.append(.text(.init(text: text)))
        }
        var metadata = deepSeekMetadata(value.usage?.raw)
        if let object = value.object { metadata["responseObject"] = .string(object) }
        if let index = choice.index { metadata["choiceIndex"] = .number(index) }
        if let role = choice.message.role { metadata["messageRole"] = .string(role) }
        if let tools = choice.message.toolCalls { metadata["toolCallTypes"] = .array(tools.compactMap { $0.type.map(JSONValue.string) }) }
        if let logprobs = choice.logprobs { metadata["logprobs"] = logprobs.raw }
        if let fingerprint = value.systemFingerprint { metadata["systemFingerprint"] = .string(fingerprint) }
        return .init(content: content, finishReason: deepSeekFinishReason(choice.finishReason),
                     usage: convertDeepSeekUsage(value.usage?.raw), providerMetadata: [providerOptionsName: metadata],
                     request: .init(body: body),
                     response: .init(id: value.id, timestamp: value.created.map(Date.init(timeIntervalSince1970:)),
                                     modelId: value.model, headers: response.responseHeaders, body: response.rawValue),
                     warnings: warnings)
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        var (body, warnings) = try await prepare(options)
        body["stream"] = true
        body["stream_options"] = ["include_usage": true]
        let response = try await postJsonToAPI(
            url: try config.url(.init(modelId: modelId, path: "/chat/completions")),
            headers: try headers(options.headers), body: JSONValue.object(body),
            failedResponseHandler: deepSeekFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: deepSeekChunkSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let namespace = providerOptionsName
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: warnings))
            let task = Task {
                var finishReason = LanguageModelV4FinishReason(unified: .other)
                var usage: JSONValue?
                var metadata: [String: JSONValue] = [:]
                var toolTypes: [Int: String] = [:]
                var contentLogprobs: [JSONValue] = []
                var reasoningLogprobs: [JSONValue] = []
                var first = true
                var activeReasoning = false
                var activeText = false
                let tracker = StreamingToolCallTracker(enqueue: { continuation.yield($0) })
                do {
                    for try await chunk in response.value {
                        let raw: JSONValue?
                        switch chunk {
                        case .success(_, let value): raw = try? jsonValue(from: value)
                        case .failure(_, let value): raw = value.flatMap { try? jsonValue(from: $0) }
                        }
                        if options.includeRawChunks == true, let raw { continuation.yield(.raw(rawValue: raw)) }
                        switch chunk {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error)
                            continuation.yield(.error(error: .error(error)))
                        case .success(let event, _):
                            switch event {
                            case .error(let error):
                                finishReason = .init(unified: .error)
                                continuation.yield(.error(error: .providerStreamError(deepSeekStreamError(error, raw: raw ?? .null))))
                            case .data(let value):
                                if first {
                                    first = false
                                    continuation.yield(.responseMetadata(id: value.id, modelId: value.model,
                                                                        timestamp: value.created.map(Date.init(timeIntervalSince1970:))))
                                }
                                if let current = value.usage?.raw, current != .null { usage = current }
                                if let object = value.object { metadata["responseObject"] = .string(object) }
                                if let fingerprint = value.systemFingerprint { metadata["systemFingerprint"] = .string(fingerprint) }
                                guard let choice = value.choices.first else { continue }
                                if let index = choice.index { metadata["choiceIndex"] = .number(index) }
                                if let finish = choice.finishReason { finishReason = deepSeekFinishReason(finish) }
                                if case .object(let logprobs) = choice.logprobs?.raw {
                                    if case .array(let values) = logprobs["content"] { contentLogprobs += values }
                                    if case .array(let values) = logprobs["reasoning_content"] { reasoningLogprobs += values }
                                }
                                guard let delta = choice.delta else { continue }
                                if let role = delta.role { metadata["messageRole"] = .string(role) }
                                if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                                    if !activeReasoning {
                                        continuation.yield(.reasoningStart(id: "reasoning-0", providerMetadata: nil))
                                        activeReasoning = true
                                    }
                                    continuation.yield(.reasoningDelta(id: "reasoning-0", delta: reasoning, providerMetadata: nil))
                                }
                                if let text = delta.content, !text.isEmpty {
                                    if !activeText {
                                        continuation.yield(.textStart(id: "txt-0", providerMetadata: nil))
                                        activeText = true
                                    }
                                    if activeReasoning {
                                        continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                                        activeReasoning = false
                                    }
                                    continuation.yield(.textDelta(id: "txt-0", delta: text, providerMetadata: nil))
                                }
                                if let tools = delta.toolCalls, !tools.isEmpty {
                                    if activeReasoning {
                                        continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                                        activeReasoning = false
                                    }
                                    for tool in tools {
                                        if let type = tool.type { toolTypes[tool.index] = type }
                                        try tracker.processDelta(.init(index: tool.index, id: tool.id, type: tool.type,
                                                                       function: .init(name: tool.function.name, arguments: tool.function.arguments)))
                                    }
                                }
                            }
                        }
                    }
                    if activeReasoning { continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil)) }
                    if activeText { continuation.yield(.textEnd(id: "txt-0", providerMetadata: nil)) }
                    tracker.flush()
                    metadata.merge(deepSeekMetadata(usage)) { _, new in new }
                    if !toolTypes.isEmpty { metadata["toolCallTypes"] = .array(toolTypes.sorted { $0.key < $1.key }.map { .string($0.value) }) }
                    var logprobs: [String: JSONValue] = [:]
                    if !contentLogprobs.isEmpty { logprobs["content"] = .array(contentLogprobs) }
                    if !reasoningLogprobs.isEmpty { logprobs["reasoning_content"] = .array(reasoningLogprobs) }
                    if !logprobs.isEmpty { metadata["logprobs"] = .object(logprobs) }
                    continuation.yield(.finish(finishReason: finishReason, usage: convertDeepSeekUsage(usage), providerMetadata: [namespace: metadata]))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return .init(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }

    private func headers(_ request: SharedV4Headers?) throws -> [String: String] {
        combineHeaders(try config.headers?().mapValues(Optional.some), request?.mapValues(Optional.some)).compactMapValues { $0 }
    }

    private func prepare(_ options: LanguageModelV4CallOptions) async throws -> ([String: JSONValue], [SharedV4Warning]) {
        let settings = try await parseProviderOptions(provider: providerOptionsName, providerOptions: options.providerOptions,
                                                     schema: deepSeekLanguageModelChatOptionsSchema) ?? .init()
        let converted = try await convertToDeepSeekChatMessages(prompt: options.prompt, responseFormat: options.responseFormat,
                                                                modelId: modelId, providerOptionsName: providerOptionsName,
                                                                supportsAssistantPrefixCompletion: config.supportsAssistantPrefixCompletion,
                                                                supportsStructuredOutputs: config.supportsStructuredOutputs)
        var warnings = converted.warnings
        if options.topK != nil { warnings.append(.unsupported(feature: "topK", details: nil)) }
        if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: nil)) }
        for (name, value) in [("frequencyPenalty", options.frequencyPenalty), ("presencePenalty", options.presencePenalty)] {
            if !config.supportsPenaltySampling, value != nil {
                warnings.append(.deprecated(setting: name, message: "\(name) is deprecated by DeepSeek and has been omitted. Remove \(name) from the request."))
            }
        }
        var thinking = settings.thinking?.type
        if thinking == "adaptive" {
            thinking = "enabled"
            warnings.append(.compatibility(feature: "thinking.type", details: "thinking.type \"adaptive\" is not a canonical DeepSeek value. mapped to \"enabled\"."))
        }
        if !config.supportsThinking { thinking = nil }
        else if thinking == nil, let reasoning = options.reasoning, reasoning != .providerDefault {
            thinking = reasoning == .none ? "disabled" : "enabled"
        }
        let enabled = config.supportsThinking && thinking != "disabled" && (thinking != nil || modelId == "deepseek-reasoner" || isDeepSeekV4Model(modelId))
        for (name, value) in [("temperature", options.temperature), ("topP", options.topP)] where enabled && value != nil {
            warnings.append(.unsupported(feature: name, details: "\(name) has no effect when DeepSeek thinking is enabled. Set providerOptions.deepseek.thinking.type to 'disabled' to use \(name)."))
        }
        var effort = settings.reasoningEffort
        if let current = effort {
            effort = current == "medium" ? "high" : current == "xhigh" ? "max" : current
            if current != effort { warnings.append(.compatibility(feature: "reasoningEffort", details: "reasoningEffort \"\(current)\" is not a canonical DeepSeek value. mapped to \"\(effort!)\".")) }
        } else if let reasoning = options.reasoning, reasoning != .providerDefault, reasoning != .none {
            effort = mapReasoningToProviderEffort(reasoning: reasoning,
                                                  effortMap: [.minimal: "low", .low: "low", .medium: "high", .high: "high", .xhigh: "max", .max: "max"],
                                                  warnings: &warnings)
        }
        let preparedTools = try prepareDeepSeekTools(options.tools, choice: options.toolChoice, supportsStrict: config.supportsStrictToolCalls)
        warnings += preparedTools.warnings
        var body: [String: JSONValue] = ["model": .string(modelId), "messages": .array(converted.messages)]
        if settings.logprobs == true || settings.topLogprobs != nil { body["logprobs"] = true }
        if let value = settings.topLogprobs { body["top_logprobs"] = .number(Double(value)) }
        if let value = options.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if !enabled {
            if let value = options.temperature { body["temperature"] = .number(value) }
            if let value = options.topP { body["top_p"] = .number(value) }
        }
        if config.supportsPenaltySampling {
            if let value = options.frequencyPenalty { body["frequency_penalty"] = .number(value) }
            if let value = options.presencePenalty { body["presence_penalty"] = .number(value) }
        }
        if let value = options.stopSequences { body["stop"] = .array(value.map(JSONValue.string)) }
        if let thinking { body["thinking"] = ["type": .string(thinking)] }
        if let user = settings.userId { body["user_id"] = .string(user) }
        if thinking != "disabled", let effort { body["reasoning_effort"] = .string(effort) }
        if case let .json(schema, name, description) = options.responseFormat {
            if config.supportsStructuredOutputs, let schema {
                var jsonSchema: [String: JSONValue] = ["schema": schema, "strict": .bool(settings.strictJsonSchema ?? true), "name": .string(name ?? "response")]
                if let description { jsonSchema["description"] = .string(description) }
                body["response_format"] = ["type": "json_schema", "json_schema": .object(jsonSchema)]
            } else { body["response_format"] = ["type": "json_object"] }
        }
        if let tools = preparedTools.tools { body["tools"] = .array(tools) }
        if let choice = preparedTools.choice { body["tool_choice"] = choice }
        return (body, warnings)
    }
}

func isDeepSeekV4Model(_ modelId: String) -> Bool {
    modelId.range(of: "(^|[/.])deepseek-(?:chat|reasoner|v[1-3](?:\\.\\d+)?)(?=[-/:.]|$)", options: .regularExpression) == nil
}

func convertDeepSeekUsage(_ usage: JSONValue?) -> LanguageModelV4Usage {
    guard case .object(let value) = usage else { return .init() }
    let prompt = deepSeekNumber(value["prompt_tokens"]) ?? 0
    let completion = deepSeekNumber(value["completion_tokens"]) ?? 0
    let cached = deepSeekNumber(value["prompt_cache_hit_tokens"]) ?? deepSeekNumber(deepSeekObject(value["prompt_tokens_details"])["cached_tokens"]) ?? 0
    let reasoning = deepSeekNumber(deepSeekObject(value["completion_tokens_details"])["reasoning_tokens"]) ?? 0
    return .init(inputTokens: .init(total: prompt, noCache: prompt - cached, cacheRead: cached),
                 outputTokens: .init(total: completion, text: max(0, completion - reasoning), reasoning: reasoning), raw: usage)
}

private func deepSeekMetadata(_ usage: JSONValue?) -> [String: JSONValue] {
    let value = deepSeekObject(usage)
    var result: [String: JSONValue] = [:]
    if let hit = value["prompt_cache_hit_tokens"], hit != .null { result["promptCacheHitTokens"] = hit }
    if let miss = value["prompt_cache_miss_tokens"], miss != .null { result["promptCacheMissTokens"] = miss }
    return result
}

func deepSeekObject(_ value: JSONValue?) -> [String: JSONValue] {
    guard case .object(let object) = value else { return [:] }
    return object
}

private func deepSeekNumber(_ value: JSONValue?) -> Int? {
    guard case .number(let number) = value else { return nil }
    return Int(exactly: number)
}

private func deepSeekFinishReason(_ value: String?) -> LanguageModelV4FinishReason {
    let unified: LanguageModelV4FinishReason.Unified
    switch value {
    case "stop": unified = .stop
    case "length": unified = .length
    case "content_filter": unified = .contentFilter
    case "tool_calls": unified = .toolCalls
    case "insufficient_system_resource": unified = .error
    default: unified = .other
    }
    return .init(unified: unified, raw: value)
}
