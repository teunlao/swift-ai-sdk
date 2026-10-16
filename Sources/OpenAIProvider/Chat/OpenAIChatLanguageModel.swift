import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAIChatLanguageModel: LanguageModelV4 {
    private let modelIdentifier: OpenAIChatModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAIChatModelId, config: OpenAIConfig) {
        modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { ["image/*": [try NSRegularExpression(pattern: "^https?://.*$")]] }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options)
        let response = try await postJsonToAPI(
            url: try config.url(.init(modelId: modelId, path: "/chat/completions")),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIChatResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        guard let choice = response.value.choices.first else {
            throw InvalidResponseDataError(data: response.rawValue, message: "Response did not contain any choices.")
        }
        var content: [LanguageModelV4Content] = []
        let text = choice.message.content.flatMap { $0.isEmpty ? nil : $0 } ?? choice.message.audio?.transcript
        if let text, !text.isEmpty { content.append(.text(.init(text: text))) }
        let generateId = config.generateId ?? generateID
        for call in choice.message.toolCalls ?? [] {
            content.append(.toolCall(.init(
                toolCallId: call.id.flatMap { $0.isEmpty ? nil : $0 } ?? generateId(),
                toolName: call.function.name, input: call.function.arguments
            )))
        }
        for annotation in choice.message.annotations ?? [] {
            content.append(.source(.url(id: generateId(), url: annotation.urlCitation.url, title: annotation.urlCitation.title, providerMetadata: nil)))
        }
        let metadata = responseMetadata(id: response.value.id, created: response.value.created, model: response.value.model)
        var providerMetadata: SharedV4ProviderMetadata = ["openai": [:]]
        addUsageMetadata(response.value.usage, to: &providerMetadata)
        if let logprobs = choice.logprobs?.content {
            providerMetadata["openai"]?["logprobs"] = try encodeJSON(logprobs)
        }
        return LanguageModelV4GenerateResult(
            content: content,
            finishReason: .init(unified: OpenAIChatFinishReasonMapper.map(choice.finishReason), raw: choice.finishReason),
            usage: convertUsage(response.value.usage),
            providerMetadata: providerMetadata,
            request: .init(body: prepared.body),
            response: .init(id: metadata.id, timestamp: metadata.timestamp, modelId: metadata.modelId, headers: response.responseHeaders, body: response.rawValue),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options)
        var body = prepared.body
        body["stream"] = .bool(true)
        body["stream_options"] = .object(["include_usage": .bool(true)])
        let url = try config.url(.init(modelId: modelId, path: "/chat/completions"))
        let response = try await postJsonToAPI(
            url: url,
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAIChatChunkSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let checked = try await prepareOpenAIStream(
            stream: response.value,
            getError: { if case .error(let frame) = $0 { return frame }; return nil },
            isOutput: { chunk in
                guard case .data(let data) = chunk else { return false }
                return data.choices.contains { choice in
                    choice.delta?.content?.isEmpty == false || choice.delta?.toolCalls?.isEmpty == false
                        || choice.delta?.annotations?.isEmpty == false
                }
            },
            url: url, requestBodyValues: body, responseHeaders: response.responseHeaders
        )
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))
            let task = Task {
                var finishReason = LanguageModelV4FinishReason(unified: .other)
                var usage: OpenAIChatUsage?
                var metadataExtracted = false
                var textActive = false
                var providerMetadata: SharedV4ProviderMetadata = ["openai": [:]]
                let tracker = StreamingToolCallTracker(
                    enqueue: { continuation.yield($0) },
                    options: .init(generateId: config.generateId ?? generateID, typeValidation: .ifPresent, emitsEmptyInitialArgumentDelta: false)
                )
                do {
                    for try await parsed in checked {
                        try Task.checkCancellation()
                        if options.includeRawChunks == true {
                            let raw: Any?
                            switch parsed {
                            case .success(_, let value): raw = value
                            case .failure(_, let value): raw = value
                            }
                            if let raw { continuation.yield(.raw(rawValue: try jsonValue(from: raw))) }
                        }
                        switch parsed {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error)
                            continuation.yield(.error(error: .error(error)))
                        case .success(let chunk, _):
                            switch chunk {
                            case .error(let frame):
                                finishReason = .init(unified: .error)
                                if let error = createOpenAIProviderStreamError(frame) {
                                    continuation.yield(.error(error: .providerStreamError(error)))
                                } else {
                                    continuation.yield(.error(error: .value(frame)))
                                }
                            case .data(let data):
                                if !metadataExtracted {
                                    let metadata = responseMetadata(id: data.id, created: data.created, model: data.model)
                                    if metadata.id != nil || metadata.timestamp != nil || metadata.modelId != nil {
                                        metadataExtracted = true
                                        continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                                    }
                                }
                                if let value = data.usage {
                                    usage = value
                                    addUsageMetadata(value, to: &providerMetadata)
                                }
                                guard let choice = data.choices.first else { continue }
                                if let reason = choice.finishReason {
                                    finishReason = .init(unified: OpenAIChatFinishReasonMapper.map(reason), raw: reason)
                                }
                                if let logprobs = choice.logprobs?.content {
                                    providerMetadata["openai"]?["logprobs"] = try encodeJSON(logprobs)
                                }
                                guard let delta = choice.delta else { continue }
                                if let text = delta.content {
                                    if !textActive {
                                        textActive = true
                                        continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                    }
                                    continuation.yield(.textDelta(id: "0", delta: text, providerMetadata: nil))
                                }
                                for call in delta.toolCalls ?? [] {
                                    try tracker.processDelta(.init(
                                        index: call.index, id: call.id, type: call.type?.rawValue,
                                        function: .init(name: call.function.name, arguments: call.function.arguments)
                                    ))
                                }
                                for annotation in delta.annotations ?? [] {
                                    continuation.yield(.source(.url(id: (config.generateId ?? generateID)(), url: annotation.urlCitation.url, title: annotation.urlCitation.title, providerMetadata: nil)))
                                }
                            }
                        }
                    }
                    try Task.checkCancellation()
                    if textActive { continuation.yield(.textEnd(id: "0", providerMetadata: nil)) }
                    tracker.flush()
                    continuation.yield(.finish(finishReason: finishReason, usage: convertUsage(usage), providerMetadata: providerMetadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return LanguageModelV4StreamResult(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }

    private func prepareRequest(_ options: LanguageModelV4CallOptions) async throws -> (body: [String: JSONValue], warnings: [SharedV4Warning]) {
        var warnings: [SharedV4Warning] = []
        let openAI = try await parseProviderOptions(provider: "openai", providerOptions: options.providerOptions, schema: openAIChatProviderOptionsSchema)
        let capabilities = getOpenAILanguageModelCapabilities(for: modelId)
        let reasoning = openAI?.forceReasoning ?? capabilities.isReasoningModel
        let portable = options.reasoning.flatMap { isCustomReasoning($0) ? OpenAIChatReasoningEffort(rawValue: $0.rawValue) : nil }
        var effort = openAI?.reasoningEffort ?? portable
        if let selected = effort, let supported = capabilities.supportedReasoningEfforts, !supported.contains(selected.rawValue) {
            warnings.append(.unsupported(feature: "reasoningEffort", details: "\(modelId) only supports the following reasoning efforts: \(supported.joined(separator: ", "))"))
            effort = nil
        }
        if options.topK != nil { warnings.append(.unsupported(feature: "topK", details: nil)) }
        if let summary = options.providerOptions?["openai"]?["reasoningSummary"], summary != .null {
            warnings.append(.unsupported(feature: "reasoningSummary", details: "reasoningSummary is only supported by the Responses API, not the Chat Completions API"))
        }
        let systemMode = openAI?.systemMessageMode ?? (reasoning ? .developer : .system)
        let converted = try OpenAIChatMessagesConverter.convert(prompt: options.prompt, systemMessageMode: systemMode)
        warnings += converted.warnings
        var body: [String: JSONValue] = ["model": .string(modelId), "messages": .array(converted.messages)]
        if let value = options.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if let value = options.temperature { body["temperature"] = .number(value) }
        if let value = options.topP { body["top_p"] = .number(value) }
        if let value = options.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if let value = options.presencePenalty { body["presence_penalty"] = .number(value) }
        if let value = options.seed { body["seed"] = .number(Double(value)) }
        if let value = options.stopSequences { body["stop"] = .array(value.map(JSONValue.string)) }
        if let value = openAI?.textVerbosity { body["verbosity"] = .string(value.rawValue) }
        if let value = openAI?.logitBias { body["logit_bias"] = .object(value.mapValues(JSONValue.number)) }
        if let value = openAI?.logprobs {
            switch value {
            case .bool(true): body["logprobs"] = .bool(true); body["top_logprobs"] = .number(0)
            case .bool(false): break
            case .number(let count): body["logprobs"] = .bool(true); body["top_logprobs"] = .number(count)
            }
        }
        if let value = openAI?.parallelToolCalls { body["parallel_tool_calls"] = .bool(value) }
        if let value = openAI?.user { body["user"] = .string(value) }
        if let value = openAI?.store { body["store"] = .bool(value) }
        if let value = effort { body["reasoning_effort"] = .string(value.rawValue) }
        if let value = openAI?.serviceTier { body["service_tier"] = .string(value.rawValue) }
        if let value = openAI?.promptCacheKey { body["prompt_cache_key"] = .string(value) }
        if let value = openAI?.promptCacheOptions { body["prompt_cache_options"] = value.jsonValue }
        if let value = openAI?.safetyIdentifier { body["safety_identifier"] = .string(value) }
        if let value = openAI?.metadata { body["metadata"] = .object(value.mapValues(JSONValue.string)) }
        if let value = openAI?.prediction { body["prediction"] = .object(value) }
        if let value = openAI?.maxCompletionTokens { body["max_completion_tokens"] = .number(value) }
        if case .json(let schema, let name, let description) = options.responseFormat {
            if let schema {
                let normalized = try normalizeOpenAIJsonSchema(schema)
                warnings += normalized.warnings
                var value: [String: JSONValue] = ["schema": normalized.schema, "strict": .bool(openAI?.strictJsonSchema ?? true), "name": .string(name ?? "response")]
                if let description { value["description"] = .string(description) }
                body["response_format"] = .object(["type": .string("json_schema"), "json_schema": .object(value)])
            } else {
                body["response_format"] = .object(["type": .string("json_object")])
            }
        }
        if let retention = openAI?.promptCacheRetention {
            if capabilities.supportedReasoningEfforts != nil {
                warnings.append(.unsupported(feature: "promptCacheRetention", details: "promptCacheRetention is not supported by GPT-6 and later models; use promptCacheOptions instead"))
            } else { body["prompt_cache_retention"] = .string(retention.rawValue) }
        }
        if reasoning {
            let allowSampling = effort == OpenAIChatReasoningEffort.none && capabilities.supportsNonReasoningParameters
            if !allowSampling {
                if body.removeValue(forKey: "temperature") != nil { warnings.append(.unsupported(feature: "temperature", details: "temperature is not supported for reasoning models")) }
                if body.removeValue(forKey: "top_p") != nil { warnings.append(.unsupported(feature: "topP", details: "topP is not supported for reasoning models")) }
                if body.removeValue(forKey: "logprobs") != nil { warnings.append(.other(message: "logprobs is not supported for reasoning models")) }
            }
            if body.removeValue(forKey: "frequency_penalty") != nil { warnings.append(.unsupported(feature: "frequencyPenalty", details: "frequencyPenalty is not supported for reasoning models")) }
            if body.removeValue(forKey: "presence_penalty") != nil { warnings.append(.unsupported(feature: "presencePenalty", details: "presencePenalty is not supported for reasoning models")) }
            if body.removeValue(forKey: "logit_bias") != nil { warnings.append(.other(message: "logitBias is not supported for reasoning models")) }
            if body.removeValue(forKey: "top_logprobs") != nil { warnings.append(.other(message: "topLogprobs is not supported for reasoning models")) }
            if let maximum = body["max_tokens"] {
                if body["max_completion_tokens"] == nil { body["max_completion_tokens"] = maximum }
                body.removeValue(forKey: "max_tokens")
            }
        } else if modelId.hasPrefix("gpt-4o-search-preview") || modelId.hasPrefix("gpt-4o-mini-search-preview") {
            if body.removeValue(forKey: "temperature") != nil { warnings.append(.unsupported(feature: "temperature", details: "temperature is not supported for the search preview models and has been removed.")) }
        }
        if openAI?.serviceTier == .flex, !capabilities.supportsFlexProcessing {
            warnings.append(.unsupported(feature: "serviceTier", details: "flex processing is only available for o3, o4-mini, and gpt-5 models"))
            body.removeValue(forKey: "service_tier")
        }
        if (openAI?.serviceTier == .priority || openAI?.serviceTier == .fast), !capabilities.supportsPriorityProcessing {
            warnings.append(.unsupported(feature: "serviceTier", details: "priority processing is only available for supported models (gpt-4, gpt-5, gpt-5-mini, o3, o4-mini) and requires Enterprise access. gpt-5-nano is not supported"))
            body.removeValue(forKey: "service_tier")
        }
        let tools = try OpenAIChatToolPreparer.prepare(tools: options.tools, toolChoice: options.toolChoice)
        if let value = tools.tools { body["tools"] = value }
        if let value = tools.toolChoice { body["tool_choice"] = value }
        warnings += tools.warnings
        return (body, warnings)
    }
}

private func encodeJSON(_ value: some Encodable) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
}

private func responseMetadata(id: String?, created: Double?, model: String?) -> (id: String?, timestamp: Date?, modelId: String?) {
    (id, created.flatMap { $0 == 0 ? nil : Date(timeIntervalSince1970: $0) }, model)
}

private func convertUsage(_ usage: OpenAIChatUsage?) -> LanguageModelV4Usage {
    guard let usage else { return LanguageModelV4Usage() }
    let prompt = usage.promptTokens ?? 0
    let completion = usage.completionTokens ?? 0
    let cacheRead = usage.promptTokensDetails?.cachedTokens ?? 0
    let cacheWrite = usage.promptTokensDetails?.cacheWriteTokens
    let reasoning = usage.completionTokensDetails?.reasoningTokens ?? 0
    return LanguageModelV4Usage(
        inputTokens: .init(total: prompt, noCache: prompt - cacheRead - (cacheWrite ?? 0), cacheRead: cacheRead, cacheWrite: cacheWrite),
        outputTokens: .init(total: completion, text: max(0, completion - reasoning), reasoning: reasoning),
        raw: usage.raw
    )
}

private func addUsageMetadata(_ usage: OpenAIChatUsage?, to metadata: inout SharedV4ProviderMetadata) {
    if let value = usage?.completionTokensDetails?.acceptedPredictionTokens { metadata["openai"]?["acceptedPredictionTokens"] = .number(Double(value)) }
    if let value = usage?.completionTokensDetails?.rejectedPredictionTokens { metadata["openai"]?["rejectedPredictionTokens"] = .number(Double(value)) }
}
