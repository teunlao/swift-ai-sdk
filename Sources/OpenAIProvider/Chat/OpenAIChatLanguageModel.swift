import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAIChatLanguageModel: LanguageModelV3 {
    private let modelIdentifier: OpenAIChatModelId
    private let config: OpenAIConfig
    private let providerOptionsName: String

    public init(modelId: OpenAIChatModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
        if let prefix = config.provider.split(separator: ".").first {
            self.providerOptionsName = String(prefix)
        } else {
            self.providerOptionsName = "openai"
        }
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            let regex = try NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
            return ["image/*": [regex]]
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let choice = response.value.choices.first else {
            throw UnsupportedFunctionalityError(functionality: "No chat choices returned")
        }

        var content: [LanguageModelV3Content] = []

        if let text = choice.message.content, !text.isEmpty {
            content.append(.text(LanguageModelV3Text(text: text)))
        }

        let responseIdGenerator = config.generateId ?? generateID

        for toolCall in choice.message.toolCalls ?? [] {
            guard let name = toolCall.function?.name else { continue }
            let arguments = toolCall.function?.arguments ?? "{}"
            let toolCallId = toolCall.id ?? responseIdGenerator()
            content.append(.toolCall(LanguageModelV3ToolCall(
                toolCallId: toolCallId,
                toolName: name,
                input: arguments,
                providerExecuted: nil,
                providerMetadata: nil
            )))
        }

        if let annotations = choice.message.annotations {
            for annotation in annotations {
                guard annotation.type == "url_citation" else { continue }
                let id = responseIdGenerator()
                content.append(.source(.url(
                    id: id,
                    url: annotation.url,
                    title: annotation.title,
                    providerMetadata: nil
                )))
            }
        }

        var openaiMetadata: [String: JSONValue] = [:]

        if let completionDetails = response.value.usage?.completionTokensDetails {
            if let accepted = completionDetails.acceptedPredictionTokens {
                openaiMetadata["acceptedPredictionTokens"] = .number(Double(accepted))
            }
            if let rejected = completionDetails.rejectedPredictionTokens {
                openaiMetadata["rejectedPredictionTokens"] = .number(Double(rejected))
            }
        }

        if let logprobs = choice.logprobs, let encoded = try? JSONEncoder().encodeToJSONValue(logprobs) {
            openaiMetadata["logprobs"] = encoded
        }

        let providerMetadata: SharedV3ProviderMetadata? = openaiMetadata.isEmpty ? nil : ["openai": openaiMetadata]

        let usage = mapUsage(response.value.usage)
        let rawFinishReason = choice.finishReason
        let finishReason = LanguageModelV3FinishReason(
            unified: OpenAIChatFinishReasonMapper.map(rawFinishReason),
            raw: rawFinishReason
        )
        let metadata = responseMetadata(from: response.value)

        let generateResult = LanguageModelV3GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3ResponseInfo(
                id: metadata.id,
                timestamp: metadata.timestamp,
                modelId: metadata.modelId,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )

        return generateResult
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        body["stream_options"] = .object(["include_usage": .bool(true)])

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let eventStream = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAIChatChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .init(unified: .other, raw: nil)
                var usage = LanguageModelV3Usage()
                var isFirstChunk = true
                var isActiveText = false
                var toolCalls: [Int: ToolCallState] = [:]
                var openaiMetadata: [String: JSONValue] = [:]

                do {
                    for try await parseResult in eventStream.value {
                        if options.includeRawChunks == true {
                            let rawJSON: JSONValue?
                            switch parseResult {
                            case .success(_, let raw):
                                rawJSON = try? jsonValue(from: raw)
                            case .failure(_, let raw):
                                rawJSON = raw.flatMap { try? jsonValue(from: $0) }
                            }
                            if let rawJSON {
                                continuation.yield(.raw(rawValue: rawJSON))
                            }
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .string(String(describing: error))))
                        case .success(let chunk, _):
                            switch chunk {
                            case .error(let errorData):
                                finishReason = .init(unified: .error, raw: nil)
                                if let errorValue = try? JSONEncoder().encodeToJSONValue(errorData) {
                                    continuation.yield(.error(error: errorValue))
                                } else {
                                    continuation.yield(.error(error: .string(errorData.error.message)))
                                }
                            case .data(let data):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let metadata = responseMetadata(from: data)
                                    continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                                }

                                if let usageValue = data.usage {
                                    usage = mapUsage(usageValue)
                                    if let accepted = usageValue.completionTokensDetails?.acceptedPredictionTokens {
                                        openaiMetadata["acceptedPredictionTokens"] = .number(Double(accepted))
                                    }
                                    if let rejected = usageValue.completionTokensDetails?.rejectedPredictionTokens {
                                        openaiMetadata["rejectedPredictionTokens"] = .number(Double(rejected))
                                    }
                                }

                                guard let choice = data.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = LanguageModelV3FinishReason(
                                        unified: OpenAIChatFinishReasonMapper.map(finish),
                                        raw: finish
                                    )
                                }

                                if let logprobs = choice.logprobs, let encoded = try? JSONEncoder().encodeToJSONValue(logprobs) {
                                    openaiMetadata["logprobs"] = encoded
                                }

                                if let delta = choice.delta {
                                    if let text = delta.content {
                                        if !isActiveText {
                                            isActiveText = true
                                            continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                        }
                                        continuation.yield(.textDelta(id: "0", delta: text, providerMetadata: nil))
                                    }

                                    if let toolCallDeltas = delta.toolCalls {
                                        try handleToolCallDeltas(
                                            toolCallDeltas,
                                            toolCalls: &toolCalls,
                                            continuation: continuation
                                        )
                                    }

                                    if let annotations = delta.annotations {
                                        for annotation in annotations where annotation.type == "url_citation" {
                                            continuation.yield(.source(.url(
                                                id: config.generateId?() ?? generateID(),
                                                url: annotation.url,
                                                title: annotation.title,
                                                providerMetadata: nil
                                            )))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if isActiveText {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                    }

                    let providerMetadata: SharedV3ProviderMetadata? = openaiMetadata.isEmpty ? nil : ["openai": openaiMetadata]
                    continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: body),
            response: LanguageModelV3StreamResponseInfo(headers: eventStream.responseHeaders)
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
    }

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }

        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAIChatProviderOptionsSchema
        )

        let providerSpecificOptions: OpenAIChatProviderOptions?
        if providerOptionsName != "openai" {
            providerSpecificOptions = try await parseProviderOptions(
                provider: providerOptionsName,
                providerOptions: options.providerOptions,
                schema: openAIChatProviderOptionsSchema
            )
        } else {
            providerSpecificOptions = nil
        }

        let mergedOptions = mergeOptions(primary: openAIOptions, override: providerSpecificOptions)
        let strictJsonSchema = mergedOptions?.strictJsonSchema ?? true

        let modelId = modelIdentifier.rawValue
        let modelCapabilities = getOpenAILanguageModelCapabilities(for: modelId)
        let modelIsReasoningModel = modelCapabilities.isReasoningModel
        let supportsNonReasoningParameters = modelCapabilities.supportsNonReasoningParameters
        let isReasoningModel = mergedOptions?.forceReasoning ?? modelCapabilities.isReasoningModel

        let modelDefaultSystemMode: OpenAIChatSystemMessageMode = modelIsReasoningModel ? .developer : .system
        let systemMode = mergedOptions?.systemMessageMode
            ?? (isReasoningModel ? .developer : modelDefaultSystemMode)

        let conversion = try OpenAIChatMessagesConverter.convert(prompt: options.prompt, systemMessageMode: systemMode)
        warnings.append(contentsOf: conversion.warnings)

        let preparedTools = OpenAIChatToolPreparer.prepare(
            tools: options.tools,
            toolChoice: options.toolChoice
        )
        warnings.append(contentsOf: preparedTools.warnings)

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(conversion.messages)
        ]

        if let maxTokens = options.maxOutputTokens {
            body["max_tokens"] = .number(Double(maxTokens))
        }
        if let temperature = options.temperature {
            body["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            body["top_p"] = .number(topP)
        }
        if let frequencyPenalty = options.frequencyPenalty {
            body["frequency_penalty"] = .number(frequencyPenalty)
        }
        if let presencePenalty = options.presencePenalty {
            body["presence_penalty"] = .number(presencePenalty)
        }
        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }
        if let stopSequences = options.stopSequences, !stopSequences.isEmpty {
            body["stop"] = .array(stopSequences.map(JSONValue.string))
        }

        if let verbosity = mergedOptions?.textVerbosity {
            body["verbosity"] = .string(verbosity.rawValue)
        }

        if let logitBias = mergedOptions?.logitBias {
            body["logit_bias"] = .object(logitBias.mapValues(JSONValue.number))
        }

        if let logprobs = mergedOptions?.logprobs {
            switch logprobs {
            case .bool(true):
                body["logprobs"] = .bool(true)
                body["top_logprobs"] = .number(0)
            case .bool(false):
                break
            case .number(let value):
                body["logprobs"] = .bool(true)
                body["top_logprobs"] = .number(Double(value))
            }
        }

        if let parallelToolCalls = mergedOptions?.parallelToolCalls {
            body["parallel_tool_calls"] = .bool(parallelToolCalls)
        }
        if let user = mergedOptions?.user {
            body["user"] = .string(user)
        }
        if let store = mergedOptions?.store {
            body["store"] = .bool(store)
        }
        if let reasoningEffort = mergedOptions?.reasoningEffort {
            body["reasoning_effort"] = .string(reasoningEffort.rawValue)
        }
        if let serviceTier = mergedOptions?.serviceTier {
            body["service_tier"] = .string(serviceTier.rawValue)
        }
        if let promptCacheKey = mergedOptions?.promptCacheKey {
            body["prompt_cache_key"] = .string(promptCacheKey)
        }
        if let promptCacheRetention = mergedOptions?.promptCacheRetention {
            body["prompt_cache_retention"] = .string(promptCacheRetention.rawValue)
        }
        if let safetyIdentifier = mergedOptions?.safetyIdentifier {
            body["safety_identifier"] = .string(safetyIdentifier)
        }
        if let metadata = mergedOptions?.metadata {
            body["metadata"] = .object(metadata.mapValues(JSONValue.string))
        }
        if let prediction = mergedOptions?.prediction {
            body["prediction"] = .object(prediction)
        }
        if let maxCompletionTokens = mergedOptions?.maxCompletionTokens {
            body["max_completion_tokens"] = .number(Double(maxCompletionTokens))
        }

        if let responseFormat = options.responseFormat {
            switch responseFormat {
            case .text:
                break
            case .json(let schema, let name, let description):
                if let schema {
                    var jsonSchema: [String: JSONValue] = [
                        "schema": schema,
                        "strict": .bool(strictJsonSchema),
                        "name": .string(name ?? "response")
                    ]
                    if let description {
                        jsonSchema["description"] = .string(description)
                    }
                    body["response_format"] = .object([
                        "type": .string("json_schema"),
                        "json_schema": .object(jsonSchema)
                    ])
                } else {
                    body["response_format"] = .object(["type": .string("json_object")])
                }
            }
        }

        if let tools = preparedTools.tools {
            body["tools"] = tools
        }
        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = toolChoice
        }

        let allowsNonReasoningParameters = mergedOptions?.reasoningEffort == OpenAIChatReasoningEffort.none && supportsNonReasoningParameters
        adjustForModelConstraints(
            body: &body,
            warnings: &warnings,
            isReasoningModel: isReasoningModel,
            allowsNonReasoningParameters: allowsNonReasoningParameters,
            modelId: modelId
        )

        if mergedOptions?.serviceTier == .flex, !modelCapabilities.supportsFlexProcessing {
            warnings.append(.unsupported(
                feature: "serviceTier",
                details: "flex processing is only available for o3, o4-mini, and gpt-5 models"
            ))
            body.removeValue(forKey: "service_tier")
        }

        if mergedOptions?.serviceTier == .priority, !modelCapabilities.supportsPriorityProcessing {
            warnings.append(.unsupported(
                feature: "serviceTier",
                details: "priority processing is only available for supported models (gpt-4, gpt-5, gpt-5-mini, o3, o4-mini) and requires Enterprise access. gpt-5-nano is not supported"
            ))
            body.removeValue(forKey: "service_tier")
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func mergeOptions(
        primary: OpenAIChatProviderOptions?,
        override: OpenAIChatProviderOptions?
    ) -> OpenAIChatProviderOptions? {
        if primary == nil { return override }
        if override == nil { return primary }
        guard var result = primary, let override = override else { return nil }

        if let logitBias = override.logitBias { result.logitBias = logitBias }
        if let logprobs = override.logprobs { result.logprobs = logprobs }
        if let parallel = override.parallelToolCalls { result.parallelToolCalls = parallel }
        if let user = override.user { result.user = user }
        if let reasoning = override.reasoningEffort { result.reasoningEffort = reasoning }
        if let maxCompletionTokens = override.maxCompletionTokens { result.maxCompletionTokens = maxCompletionTokens }
        if let store = override.store { result.store = store }
        if let metadata = override.metadata { result.metadata = metadata }
        if let prediction = override.prediction { result.prediction = prediction }
        if let serviceTier = override.serviceTier { result.serviceTier = serviceTier }
        if let strict = override.strictJsonSchema { result.strictJsonSchema = strict }
        if let verbosity = override.textVerbosity { result.textVerbosity = verbosity }
        if let promptCacheKey = override.promptCacheKey { result.promptCacheKey = promptCacheKey }
        if let promptCacheRetention = override.promptCacheRetention { result.promptCacheRetention = promptCacheRetention }
        if let safetyIdentifier = override.safetyIdentifier { result.safetyIdentifier = safetyIdentifier }
        if let systemMessageMode = override.systemMessageMode { result.systemMessageMode = systemMessageMode }
        if let forceReasoning = override.forceReasoning { result.forceReasoning = forceReasoning }

        return result
    }

    private func adjustForModelConstraints(
        body: inout [String: JSONValue],
        warnings: inout [SharedV3Warning],
        isReasoningModel: Bool,
        allowsNonReasoningParameters: Bool,
        modelId: String
    ) {
        if isReasoningModel {
            if !allowsNonReasoningParameters {
                if body.removeValue(forKey: "temperature") != nil {
                    warnings.append(.unsupported(feature: "temperature", details: "temperature is not supported for reasoning models"))
                }
                if body.removeValue(forKey: "top_p") != nil {
                    warnings.append(.unsupported(feature: "topP", details: "topP is not supported for reasoning models"))
                }
                if body.removeValue(forKey: "logprobs") != nil {
                    warnings.append(.other(message: "logprobs is not supported for reasoning models"))
                }
            }

            if body.removeValue(forKey: "frequency_penalty") != nil {
                warnings.append(.unsupported(feature: "frequencyPenalty", details: "frequencyPenalty is not supported for reasoning models"))
            }
            if body.removeValue(forKey: "presence_penalty") != nil {
                warnings.append(.unsupported(feature: "presencePenalty", details: "presencePenalty is not supported for reasoning models"))
            }
            if body.removeValue(forKey: "logit_bias") != nil {
                warnings.append(.other(message: "logitBias is not supported for reasoning models"))
            }
            if body.removeValue(forKey: "top_logprobs") != nil {
                warnings.append(.other(message: "topLogprobs is not supported for reasoning models"))
            }
            if let maxTokens = body.removeValue(forKey: "max_tokens"), body["max_completion_tokens"] == nil {
                body["max_completion_tokens"] = maxTokens
            }
        } else if modelId.hasPrefix("gpt-4o-search-preview") || modelId.hasPrefix("gpt-4o-mini-search-preview") {
            if body.removeValue(forKey: "temperature") != nil {
                warnings.append(.unsupported(
                    feature: "temperature",
                    details: "temperature is not supported for the search preview models and has been removed."
                ))
            }
        }
    }

    private func mapUsage(_ usage: OpenAIChatUsage?) -> LanguageModelV3Usage {
        guard let usage else { return LanguageModelV3Usage() }

        let promptTokens = usage.promptTokens ?? 0
        let completionTokens = usage.completionTokens ?? 0
        let cachedTokens = usage.promptTokensDetails?.cachedTokens ?? 0
        let reasoningTokens = usage.completionTokensDetails?.reasoningTokens ?? 0

        return LanguageModelV3Usage(
            inputTokens: .init(
                total: promptTokens,
                noCache: promptTokens - cachedTokens,
                cacheRead: cachedTokens,
                cacheWrite: nil
            ),
            outputTokens: .init(
                total: completionTokens,
                text: completionTokens - reasoningTokens,
                reasoning: reasoningTokens
            ),
            raw: try? jsonValue(from: usage)
        )
    }

    private func responseMetadata(from response: OpenAIChatResponse) -> (id: String?, modelId: String?, timestamp: Date?) {
        let timestamp = response.created.map { Date(timeIntervalSince1970: $0) }
        return (response.id, response.model, timestamp)
    }

    private func responseMetadata(from chunk: OpenAIChatChunkData) -> (id: String?, modelId: String?, timestamp: Date?) {
        let timestamp = chunk.created.map { Date(timeIntervalSince1970: $0) }
        return (chunk.id, chunk.model, timestamp)
    }

    private func handleToolCallDeltas(
        _ deltas: [OpenAIChatChunkToolCallDelta],
        toolCalls: inout [Int: ToolCallState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) throws {
        for delta in deltas {
            let index = delta.index

            if toolCalls[index] == nil {
                guard delta.type == nil || delta.type == "function" else {
                    throw InvalidResponseDataError(data: delta, message: "Expected 'function' type.")
                }
                guard let id = delta.id else {
                    throw InvalidResponseDataError(data: delta, message: "Expected 'id' to be a string.")
                }
                guard let name = delta.function?.name else {
                    throw InvalidResponseDataError(data: delta, message: "Expected function name.")
                }

                var state = ToolCallState(
                    toolCallId: id,
                    toolName: name,
                    arguments: delta.function?.arguments ?? "",
                    hasFinished: false
                )

                continuation.yield(.toolInputStart(
                    id: id,
                    toolName: name,
                    providerMetadata: nil,
                    providerExecuted: nil,
                    dynamic: nil,
                    title: nil
                ))

                if let args = delta.function?.arguments {
                    continuation.yield(.toolInputDelta(id: id, delta: args, providerMetadata: nil))
                    if isParsableJson(state.arguments) {
                        continuation.yield(.toolInputEnd(id: id, providerMetadata: nil))
                        continuation.yield(.toolCall(LanguageModelV3ToolCall(
                            toolCallId: id,
                            toolName: name,
                            input: state.arguments,
                            providerExecuted: nil,
                            providerMetadata: nil
                        )))
                        state.hasFinished = true
                    }
                }

                toolCalls[index] = state
                continue
            }

            var state = toolCalls[index]!
            if state.hasFinished {
                continue
            }

            if let name = delta.function?.name, !name.isEmpty {
                state.toolName = name
            }

            if let argumentDelta = delta.function?.arguments {
                state.arguments += argumentDelta
                continuation.yield(.toolInputDelta(id: state.toolCallId, delta: argumentDelta, providerMetadata: nil))

                if isParsableJson(state.arguments) {
                    continuation.yield(.toolInputEnd(id: state.toolCallId, providerMetadata: nil))
                    continuation.yield(.toolCall(LanguageModelV3ToolCall(
                        toolCallId: state.toolCallId,
                        toolName: state.toolName,
                        input: state.arguments,
                        providerExecuted: nil,
                        providerMetadata: nil
                    )))
                    state.hasFinished = true
                }
            }

            toolCalls[index] = state
        }
    }
    private struct ToolCallState {
        var toolCallId: String
        var toolName: String
        var arguments: String
        var hasFinished: Bool
    }

}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}
