import Foundation
import AISDKProvider
import AISDKProviderUtils

private struct OpenAIChatLanguageModelCore: Sendable {
    private let modelIdentifier: OpenAIChatModelId
    private let config: OpenAIConfig

    init(modelId: OpenAIChatModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }

    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            let regex = try NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
            return ["image/*": [regex]]
        }
    }

    func doGenerate(options: OpenAIChatCallSettings) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }

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

        var content: [LanguageModelV4Content] = []

        if let text = choice.message.content, !text.isEmpty {
            content.append(.text(LanguageModelV4Text(text: text)))
        }

        let responseIdGenerator = config.generateId ?? generateID

        for toolCall in choice.message.toolCalls ?? [] {
            guard let name = toolCall.function?.name else { continue }
            let arguments = toolCall.function?.arguments ?? "{}"
            let toolCallId = toolCall.id ?? responseIdGenerator()
            content.append(.toolCall(LanguageModelV4ToolCall(
                toolCallId: toolCallId,
                toolName: name,
                input: arguments,
                providerExecuted: nil,
                providerMetadata: nil
            )))
        }

        if let annotations = choice.message.annotations {
            for annotation in annotations where annotation.type == "url_citation" {
                content.append(.source(.url(
                    id: responseIdGenerator(),
                    url: annotation.url,
                    title: annotation.title,
                    providerMetadata: nil
                )))
            }
        }

        let metadata = responseMetadata(from: response.value)

        return LanguageModelV4GenerateResult(
            content: content,
            finishReason: LanguageModelV4FinishReason(
                unified: OpenAIChatFinishReasonMapper.mapV4(choice.finishReason),
                raw: choice.finishReason
            ),
            usage: convertOpenAIChatUsageToV4(response.value.usage),
            providerMetadata: openAIChatProviderMetadata(
                usage: response.value.usage,
                logprobs: choice.logprobs,
                shape: options.logprobsMetadataShape
            ),
            request: LanguageModelV4RequestInfo(body: prepared.body),
            response: LanguageModelV4ResponseInfo(
                id: metadata.id,
                timestamp: metadata.timestamp,
                modelId: metadata.modelId,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    func doStream(options: OpenAIChatCallSettings) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        body["stream_options"] = .object(["include_usage": .bool(true)])

        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }
        let url = config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions"))

        let eventStream = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAIChatChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let checkedStream: AsyncThrowingStream<ParseJSONResult<OpenAIChatChunk>, Error>
        if options.throwsPreOutputStreamErrors {
            checkedStream = try await throwIfOpenAIChatStreamErrorBeforeOutput(
                stream: eventStream.value,
                url: url,
                requestBodyValues: body,
                responseHeaders: eventStream.responseHeaders
            )
        } else {
            checkedStream = eventStream.value
        }

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            let task = Task {
                var finishReason = LanguageModelV4FinishReason(unified: .other, raw: nil)
                var usage = LanguageModelV4Usage()
                var metadataExtracted = false
                var isActiveText = false
                var providerMetadata: SharedV4ProviderMetadata = ["openai": [:]]

                let toolCallTracker = StreamingToolCallTracker(
                    enqueue: { part in continuation.yield(part) },
                    options: StreamingToolCallTrackerOptions(
                        generateId: config.generateId ?? generateID,
                        typeValidation: .ifPresent,
                        emitsEmptyInitialArgumentDelta: options.emitsEmptyInitialToolArgumentDelta
                    )
                )

                do {
                    for try await parseResult in checkedStream {
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
                            finishReason = LanguageModelV4FinishReason(unified: .error, raw: nil)
                            continuation.yield(.error(error: .string(String(describing: error))))

                        case .success(let chunk, _):
                            switch chunk {
                            case .error(let errorData):
                                finishReason = LanguageModelV4FinishReason(unified: .error, raw: nil)
                                if let errorValue = try? JSONEncoder().encodeToJSONValue(errorData.error) {
                                    continuation.yield(.error(error: errorValue))
                                } else {
                                    continuation.yield(.error(error: .string(errorData.error.message)))
                                }

                            case .data(let data):
                                if !metadataExtracted {
                                    let metadata = responseMetadata(from: data)
                                    if metadata.id != nil || metadata.modelId != nil || metadata.timestamp != nil {
                                        metadataExtracted = true
                                        continuation.yield(.responseMetadata(
                                            id: metadata.id,
                                            modelId: metadata.modelId,
                                            timestamp: metadata.timestamp
                                        ))
                                    }
                                }

                                if let usageValue = data.usage {
                                    usage = convertOpenAIChatUsageToV4(usageValue)
                                    addOpenAIChatUsageMetadata(usageValue, to: &providerMetadata)
                                }

                                guard let choice = data.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = LanguageModelV4FinishReason(
                                        unified: OpenAIChatFinishReasonMapper.mapV4(finish),
                                        raw: finish
                                    )
                                }

                                addOpenAIChatLogprobsMetadata(
                                    choice.logprobs,
                                    shape: options.logprobsMetadataShape,
                                    to: &providerMetadata
                                )

                                guard let delta = choice.delta else { continue }

                                if let text = delta.content {
                                    if !isActiveText {
                                        isActiveText = true
                                        continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                    }
                                    continuation.yield(.textDelta(id: "0", delta: text, providerMetadata: nil))
                                }

                                if let toolCallDeltas = delta.toolCalls {
                                    for delta in toolCallDeltas {
                                        try toolCallTracker.processDelta(StreamingToolCallDelta(
                                            index: delta.index,
                                            id: delta.id,
                                            type: delta.type,
                                            function: StreamingToolCallFunctionDelta(
                                                name: delta.function?.name,
                                                arguments: delta.function?.arguments
                                            )
                                        ))
                                    }
                                }

                                if let annotations = delta.annotations {
                                    for annotation in annotations where annotation.type == "url_citation" {
                                        continuation.yield(.source(.url(
                                            id: (config.generateId ?? generateID)(),
                                            url: annotation.url,
                                            title: annotation.title,
                                            providerMetadata: nil
                                        )))
                                    }
                                }
                            }
                        }
                    }

                    if isActiveText {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                    }

                    toolCallTracker.flush()

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: usage,
                        providerMetadata: providerMetadata
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return LanguageModelV4StreamResult(
            stream: stream,
            request: LanguageModelV4RequestInfo(body: body),
            response: LanguageModelV4StreamResponseInfo(headers: eventStream.responseHeaders)
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
    }

    private func prepareRequest(options: OpenAIChatCallSettings) async throws -> PreparedRequest {
        var warnings: [SharedV4Warning] = []

        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }

        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAIChatProviderOptionsSchema
        )
        let strictJsonSchema = openAIOptions?.strictJsonSchema ?? true

        let modelId = modelIdentifier.rawValue
        let modelCapabilities = getOpenAILanguageModelCapabilities(for: modelId)
        let supportsNonReasoningParameters = modelCapabilities.supportsNonReasoningParameters
        let resolvedReasoningEffort = resolvedReasoningEffort(
            topLevelReasoning: options.reasoning,
            openAIOptions: openAIOptions
        )
        let isReasoningModel = openAIOptions?.forceReasoning ?? modelCapabilities.isReasoningModel
        let systemMode = openAIOptions?.systemMessageMode
            ?? (isReasoningModel ? .developer : chatSystemMessageMode(from: modelCapabilities.systemMessageMode))

        let conversion: (messages: OpenAIChatPrompt, warnings: [SharedV4Warning])
        switch options.prompt {
        case .v3(let prompt):
            let v3Conversion = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: systemMode)
            conversion = (
                messages: v3Conversion.messages,
                warnings: v3Conversion.warnings.map(convertSharedV3WarningToV4)
            )
        case .v4(let prompt):
            conversion = try OpenAIChatMessagesConverter.convertV4(prompt: prompt, systemMessageMode: systemMode)
        }
        warnings.append(contentsOf: conversion.warnings)

        let preparedTools: (tools: JSONValue?, toolChoice: JSONValue?, warnings: [SharedV4Warning])
        switch options.tools {
        case .v3(let tools, let toolChoice):
            let prepared = OpenAIChatToolPreparer.prepare(tools: tools, toolChoice: toolChoice)
            preparedTools = (
                tools: prepared.tools,
                toolChoice: prepared.toolChoice,
                warnings: prepared.warnings.map(convertSharedV3WarningToV4)
            )
        case .v4(let tools, let toolChoice):
            let prepared = OpenAIChatToolPreparer.prepareV4(tools: tools, toolChoice: toolChoice)
            preparedTools = (
                tools: prepared.tools,
                toolChoice: prepared.toolChoice,
                warnings: prepared.warnings
            )
        }
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

        if let verbosity = openAIOptions?.textVerbosity {
            body["verbosity"] = .string(verbosity.rawValue)
        }

        if let logitBias = openAIOptions?.logitBias {
            body["logit_bias"] = .object(logitBias.mapValues(JSONValue.number))
        }

        if let logprobs = openAIOptions?.logprobs {
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

        if let parallelToolCalls = openAIOptions?.parallelToolCalls {
            body["parallel_tool_calls"] = .bool(parallelToolCalls)
        }
        if let user = openAIOptions?.user {
            body["user"] = .string(user)
        }
        if let store = openAIOptions?.store {
            body["store"] = .bool(store)
        }
        if let reasoningEffort = resolvedReasoningEffort {
            body["reasoning_effort"] = .string(reasoningEffort.rawValue)
        }
        if let serviceTier = openAIOptions?.serviceTier {
            body["service_tier"] = .string(serviceTier.rawValue)
        }
        if let promptCacheKey = openAIOptions?.promptCacheKey {
            body["prompt_cache_key"] = .string(promptCacheKey)
        }
        if let promptCacheOptions = openAIOptions?.promptCacheOptions {
            body["prompt_cache_options"] = promptCacheOptions.jsonValue
        }
        if let promptCacheRetention = openAIOptions?.promptCacheRetention {
            body["prompt_cache_retention"] = .string(promptCacheRetention.rawValue)
        }
        if let safetyIdentifier = openAIOptions?.safetyIdentifier {
            body["safety_identifier"] = .string(safetyIdentifier)
        }
        if let metadata = openAIOptions?.metadata {
            body["metadata"] = .object(metadata.mapValues(JSONValue.string))
        }
        if let prediction = openAIOptions?.prediction {
            body["prediction"] = .object(prediction)
        }
        if let maxCompletionTokens = openAIOptions?.maxCompletionTokens {
            body["max_completion_tokens"] = .number(maxCompletionTokens)
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

        let allowsNonReasoningParameters = resolvedReasoningEffort == OpenAIChatReasoningEffort.none && supportsNonReasoningParameters
        adjustForModelConstraints(
            body: &body,
            warnings: &warnings,
            isReasoningModel: isReasoningModel,
            allowsNonReasoningParameters: allowsNonReasoningParameters,
            modelId: modelId
        )

        if openAIOptions?.serviceTier == .flex, !modelCapabilities.supportsFlexProcessing {
            warnings.append(.unsupported(
                feature: "serviceTier",
                details: "flex processing is only available for o3, o4-mini, and gpt-5 models"
            ))
            body.removeValue(forKey: "service_tier")
        }

        if openAIOptions?.serviceTier == .priority, !modelCapabilities.supportsPriorityProcessing {
            warnings.append(.unsupported(
                feature: "serviceTier",
                details: "priority processing is only available for supported models (gpt-4, gpt-5, gpt-5-mini, o3, o4-mini) and requires Enterprise access. gpt-5-nano is not supported"
            ))
            body.removeValue(forKey: "service_tier")
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func resolvedReasoningEffort(
        topLevelReasoning: LanguageModelV4ReasoningEffort?,
        openAIOptions: OpenAIChatProviderOptions?
    ) -> OpenAIChatReasoningEffort? {
        if let providerEffort = openAIOptions?.reasoningEffort {
            return providerEffort
        }
        guard let topLevelReasoning, isCustomReasoning(topLevelReasoning) else {
            return nil
        }
        return OpenAIChatReasoningEffort(rawValue: topLevelReasoning.rawValue)
    }

    private func chatSystemMessageMode(from mode: OpenAIResponsesSystemMessageMode) -> OpenAIChatSystemMessageMode {
        switch mode {
        case .system:
            return .system
        case .developer:
            return .developer
        case .remove:
            return .remove
        }
    }

    private func adjustForModelConstraints(
        body: inout [String: JSONValue],
        warnings: inout [SharedV4Warning],
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
}

private enum OpenAIChatPromptInput: Sendable {
    case v3(LanguageModelV3Prompt)
    case v4(LanguageModelV4Prompt)
}

private enum OpenAIChatToolsInput: Sendable {
    case v3([LanguageModelV3Tool]?, LanguageModelV3ToolChoice?)
    case v4([LanguageModelV4Tool]?, LanguageModelV4ToolChoice?)
}

private enum OpenAIChatLogprobsMetadataShape: Sendable {
    case v3Object
    case v4Content
}

private struct OpenAIChatCallSettings: Sendable {
    let prompt: OpenAIChatPromptInput
    let maxOutputTokens: Int?
    let temperature: Double?
    let stopSequences: [String]?
    let topP: Double?
    let topK: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let responseFormat: LanguageModelV4ResponseFormat?
    let seed: Int?
    let tools: OpenAIChatToolsInput
    let includeRawChunks: Bool?
    let throwsPreOutputStreamErrors: Bool
    let abortSignal: (@Sendable () -> Bool)?
    let headers: SharedV4Headers?
    let reasoning: LanguageModelV4ReasoningEffort?
    let providerOptions: SharedV4ProviderOptions?
    let logprobsMetadataShape: OpenAIChatLogprobsMetadataShape
    let emitsEmptyInitialToolArgumentDelta: Bool

    init(v3 options: LanguageModelV3CallOptions) {
        self.prompt = .v3(options.prompt)
        self.maxOutputTokens = options.maxOutputTokens
        self.temperature = options.temperature
        self.stopSequences = options.stopSequences
        self.topP = options.topP
        self.topK = options.topK
        self.presencePenalty = options.presencePenalty
        self.frequencyPenalty = options.frequencyPenalty
        self.responseFormat = options.responseFormat.map(convertLanguageModelV3ResponseFormatToV4)
        self.seed = options.seed
        self.tools = .v3(options.tools, options.toolChoice)
        self.includeRawChunks = options.includeRawChunks
        self.throwsPreOutputStreamErrors = false
        self.abortSignal = options.abortSignal
        self.headers = options.headers
        self.reasoning = nil
        self.providerOptions = options.providerOptions
        self.logprobsMetadataShape = .v3Object
        self.emitsEmptyInitialToolArgumentDelta = true
    }

    init(v4 options: LanguageModelV4CallOptions) {
        self.prompt = .v4(options.prompt)
        self.maxOutputTokens = options.maxOutputTokens
        self.temperature = options.temperature
        self.stopSequences = options.stopSequences
        self.topP = options.topP
        self.topK = options.topK
        self.presencePenalty = options.presencePenalty
        self.frequencyPenalty = options.frequencyPenalty
        self.responseFormat = options.responseFormat
        self.seed = options.seed
        self.tools = .v4(options.tools, options.toolChoice)
        self.includeRawChunks = options.includeRawChunks
        self.throwsPreOutputStreamErrors = true
        self.abortSignal = options.abortSignal
        self.headers = options.headers
        self.reasoning = options.reasoning
        self.providerOptions = options.providerOptions
        self.logprobsMetadataShape = .v4Content
        self.emitsEmptyInitialToolArgumentDelta = false
    }
}

public final class OpenAIChatLanguageModel: LanguageModelV3 {
    private let core: OpenAIChatLanguageModelCore

    public init(modelId: OpenAIChatModelId, config: OpenAIConfig) {
        self.core = OpenAIChatLanguageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await core.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let result = try await core.doGenerate(options: OpenAIChatCallSettings(v3: options))
        return try convertOpenAIChatGenerateResultToV3(result)
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let result = try await core.doStream(options: OpenAIChatCallSettings(v3: options))
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await part in result.stream {
                        continuation.yield(try convertOpenAIChatStreamPartToV3(part))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: result.request.map(convertLanguageModelV4RequestInfoToV3),
            response: result.response.map(convertLanguageModelV4StreamResponseInfoToV3)
        )
    }

    func asV4() -> OpenAIChatLanguageModelV4 {
        OpenAIChatLanguageModelV4(core: core)
    }
}

public final class OpenAIChatLanguageModelV4: LanguageModelV4 {
    private let core: OpenAIChatLanguageModelCore

    public init(modelId: OpenAIChatModelId, config: OpenAIConfig) {
        self.core = OpenAIChatLanguageModelCore(modelId: modelId, config: config)
    }

    fileprivate init(core: OpenAIChatLanguageModelCore) {
        self.core = core
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await core.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        try await core.doGenerate(options: OpenAIChatCallSettings(v4: options))
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        try await core.doStream(options: OpenAIChatCallSettings(v4: options))
    }
}

private func convertLanguageModelV3ResponseFormatToV4(_ value: LanguageModelV3ResponseFormat) -> LanguageModelV4ResponseFormat {
    switch value {
    case .text:
        return .text
    case let .json(schema, name, description):
        return .json(schema: schema, name: name, description: description)
    }
}

private func openAIChatProviderMetadata(
    usage: OpenAIChatUsage?,
    logprobs: OpenAIChatChoiceLogprobs?,
    shape: OpenAIChatLogprobsMetadataShape
) -> SharedV4ProviderMetadata {
    var metadata: SharedV4ProviderMetadata = ["openai": [:]]
    if let usage {
        addOpenAIChatUsageMetadata(usage, to: &metadata)
    }
    addOpenAIChatLogprobsMetadata(logprobs, shape: shape, to: &metadata)
    return metadata
}

private func addOpenAIChatUsageMetadata(_ usage: OpenAIChatUsage, to metadata: inout SharedV4ProviderMetadata) {
    if metadata["openai"] == nil {
        metadata["openai"] = [:]
    }
    if let accepted = usage.completionTokensDetails?.acceptedPredictionTokens {
        metadata["openai"]?["acceptedPredictionTokens"] = .number(Double(accepted))
    }
    if let rejected = usage.completionTokensDetails?.rejectedPredictionTokens {
        metadata["openai"]?["rejectedPredictionTokens"] = .number(Double(rejected))
    }
}

private func addOpenAIChatLogprobsMetadata(
    _ logprobs: OpenAIChatChoiceLogprobs?,
    shape: OpenAIChatLogprobsMetadataShape,
    to metadata: inout SharedV4ProviderMetadata
) {
    guard let logprobs else { return }
    if metadata["openai"] == nil {
        metadata["openai"] = [:]
    }

    switch shape {
    case .v3Object:
        if let encoded = try? JSONEncoder().encodeToJSONValue(logprobs) {
            metadata["openai"]?["logprobs"] = encoded
        }
    case .v4Content:
        if let content = logprobs.content,
           let encoded = try? JSONEncoder().encodeToJSONValue(content) {
            metadata["openai"]?["logprobs"] = encoded
        }
    }
}

private func convertOpenAIChatUsageToV4(_ usage: OpenAIChatUsage?) -> LanguageModelV4Usage {
    guard let usage else { return LanguageModelV4Usage() }

    let promptTokens = usage.promptTokens ?? 0
    let completionTokens = usage.completionTokens ?? 0
    let cachedTokens = usage.promptTokensDetails?.cachedTokens ?? 0
    let cacheWriteTokens = usage.promptTokensDetails?.cacheWriteTokens
    let reasoningTokens = usage.completionTokensDetails?.reasoningTokens ?? 0

    return LanguageModelV4Usage(
        inputTokens: .init(
            total: promptTokens,
            noCache: promptTokens - cachedTokens - (cacheWriteTokens ?? 0),
            cacheRead: cachedTokens,
            cacheWrite: cacheWriteTokens
        ),
        outputTokens: .init(
            total: completionTokens,
            text: completionTokens - reasoningTokens,
            reasoning: reasoningTokens
        ),
        raw: try? JSONEncoder().encodeToJSONValue(usage)
    )
}

private func responseMetadata(from response: OpenAIChatResponse) -> (id: String?, modelId: String?, timestamp: Date?) {
    let timestamp = openAIChatTimestamp(from: response.created)
    return (response.id, response.model, timestamp)
}

private func responseMetadata(from chunk: OpenAIChatChunkData) -> (id: String?, modelId: String?, timestamp: Date?) {
    let timestamp = openAIChatTimestamp(from: chunk.created)
    return (chunk.id, chunk.model, timestamp)
}

private func openAIChatTimestamp(from created: Double?) -> Date? {
    guard let created, created != 0 else { return nil }
    return Date(timeIntervalSince1970: created)
}

private func convertOpenAIChatGenerateResultToV3(
    _ result: LanguageModelV4GenerateResult
) throws -> LanguageModelV3GenerateResult {
    LanguageModelV3GenerateResult(
        content: try result.content.map(convertOpenAIChatContentToV3),
        finishReason: convertLanguageModelV4FinishReasonToV3(result.finishReason),
        usage: convertLanguageModelV4UsageToV3(result.usage),
        providerMetadata: nilIfEmptyOpenAIMetadata(result.providerMetadata),
        request: result.request.map(convertLanguageModelV4RequestInfoToV3),
        response: result.response.map(convertLanguageModelV4ResponseInfoToV3),
        warnings: result.warnings.map(convertSharedV4WarningToV3)
    )
}

private func convertOpenAIChatContentToV3(_ value: LanguageModelV4Content) throws -> LanguageModelV3Content {
    switch value {
    case .text(let content):
        return .text(LanguageModelV3Text(text: content.text, providerMetadata: content.providerMetadata))
    case .source(let source):
        return .source(convertLanguageModelV4SourceToV3(source))
    case .toolCall(let toolCall):
        return .toolCall(convertLanguageModelV4ToolCallToV3(toolCall))
    default:
        throw UnsupportedFunctionalityError(functionality: "OpenAI chat V4 content \(value) on V3 facade")
    }
}

private func convertOpenAIChatStreamPartToV3(
    _ value: LanguageModelV4StreamPart
) throws -> LanguageModelV3StreamPart {
    switch value {
    case let .textStart(id, providerMetadata):
        return .textStart(id: id, providerMetadata: providerMetadata)
    case let .textDelta(id, delta, providerMetadata):
        return .textDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .textEnd(id, providerMetadata):
        return .textEnd(id: id, providerMetadata: providerMetadata)
    case let .toolInputStart(id, toolName, providerMetadata, providerExecuted, dynamic, title):
        return .toolInputStart(
            id: id,
            toolName: toolName,
            providerMetadata: providerMetadata,
            providerExecuted: providerExecuted,
            dynamic: dynamic,
            title: title
        )
    case let .toolInputDelta(id, delta, providerMetadata):
        return .toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .toolInputEnd(id, providerMetadata):
        return .toolInputEnd(id: id, providerMetadata: providerMetadata)
    case .toolCall(let toolCall):
        return .toolCall(convertLanguageModelV4ToolCallToV3(toolCall))
    case .source(let source):
        return .source(convertLanguageModelV4SourceToV3(source))
    case let .streamStart(warnings):
        return .streamStart(warnings: warnings.map(convertSharedV4WarningToV3))
    case let .responseMetadata(id, modelId, timestamp):
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)
    case let .finish(finishReason, usage, providerMetadata):
        return .finish(
            finishReason: convertLanguageModelV4FinishReasonToV3(finishReason),
            usage: convertLanguageModelV4UsageToV3(usage),
            providerMetadata: nilIfEmptyOpenAIMetadata(providerMetadata)
        )
    case let .raw(rawValue):
        return .raw(rawValue: rawValue)
    case let .error(error):
        return .error(error: error)
    default:
        throw UnsupportedFunctionalityError(functionality: "OpenAI chat V4 stream part \(value) on V3 facade")
    }
}

private func convertLanguageModelV4ToolCallToV3(_ value: LanguageModelV4ToolCall) -> LanguageModelV3ToolCall {
    LanguageModelV3ToolCall(
        toolCallId: value.toolCallId,
        toolName: value.toolName,
        input: value.input,
        providerExecuted: value.providerExecuted,
        dynamic: value.dynamic,
        providerMetadata: value.providerMetadata
    )
}

private func convertLanguageModelV4SourceToV3(_ value: LanguageModelV4Source) -> LanguageModelV3Source {
    switch value {
    case let .url(id, url, title, providerMetadata):
        return .url(id: id, url: url, title: title, providerMetadata: providerMetadata)
    case let .document(id, mediaType, title, filename, providerMetadata):
        return .document(
            id: id,
            mediaType: mediaType,
            title: title,
            filename: filename,
            providerMetadata: providerMetadata
        )
    }
}

private func convertLanguageModelV4FinishReasonToV3(_ value: LanguageModelV4FinishReason) -> LanguageModelV3FinishReason {
    LanguageModelV3FinishReason(
        unified: LanguageModelV3FinishReason.Unified(rawValue: value.unified.rawValue) ?? .other,
        raw: value.raw
    )
}

private func convertLanguageModelV4UsageToV3(_ value: LanguageModelV4Usage) -> LanguageModelV3Usage {
    LanguageModelV3Usage(
        inputTokens: .init(
            total: value.inputTokens.total,
            noCache: value.inputTokens.noCache,
            cacheRead: value.inputTokens.cacheRead,
            cacheWrite: value.inputTokens.cacheWrite
        ),
        outputTokens: .init(
            total: value.outputTokens.total,
            text: value.outputTokens.text,
            reasoning: value.outputTokens.reasoning
        ),
        raw: value.raw
    )
}

private func convertLanguageModelV4RequestInfoToV3(_ value: LanguageModelV4RequestInfo) -> LanguageModelV3RequestInfo {
    LanguageModelV3RequestInfo(body: value.body)
}

private func convertLanguageModelV4ResponseInfoToV3(_ value: LanguageModelV4ResponseInfo) -> LanguageModelV3ResponseInfo {
    LanguageModelV3ResponseInfo(
        id: value.id,
        timestamp: value.timestamp,
        modelId: value.modelId,
        headers: value.headers,
        body: value.body
    )
}

private func convertLanguageModelV4StreamResponseInfoToV3(
    _ value: LanguageModelV4StreamResponseInfo
) -> LanguageModelV3StreamResponseInfo {
    LanguageModelV3StreamResponseInfo(headers: value.headers)
}

private func convertSharedV3WarningToV4(_ value: SharedV3Warning) -> SharedV4Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .other(message):
        return .other(message: message)
    }
}

private func convertSharedV4WarningToV3(_ value: SharedV4Warning) -> SharedV3Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .deprecated(setting, message):
        return .other(message: "\(setting): \(message)")
    case let .other(message):
        return .other(message: message)
    }
}

private func nilIfEmptyOpenAIMetadata(_ value: SharedV4ProviderMetadata?) -> SharedV3ProviderMetadata? {
    guard let value else { return nil }
    let withoutEmptyObjects = value.filter { !$0.value.isEmpty }
    return withoutEmptyObjects.isEmpty ? nil : withoutEmptyObjects
}

private func throwIfOpenAIChatStreamErrorBeforeOutput(
    stream: AsyncThrowingStream<ParseJSONResult<OpenAIChatChunk>, Error>,
    url: String,
    requestBodyValues: [String: JSONValue],
    responseHeaders: SharedV4Headers?
) async throws -> AsyncThrowingStream<ParseJSONResult<OpenAIChatChunk>, Error> {
    let iteratorBox = OpenAIChatStreamIteratorBox(iterator: stream.makeAsyncIterator())
    var buffered: [ParseJSONResult<OpenAIChatChunk>] = []

    while let chunk = try await iteratorBox.next() {
        switch chunk {
        case .failure:
            buffered.append(chunk)
            return makeOpenAIChatCheckedStream(buffered: buffered, iteratorBox: iteratorBox)

        case .success(let value, _):
            if case .error(let errorData) = value {
                throw openAIChatStreamError(
                    errorData: errorData,
                    url: url,
                    requestBodyValues: requestBodyValues,
                    responseHeaders: responseHeaders
                )
            }

            buffered.append(chunk)
            if isOpenAIChatOutputChunk(value) {
                return makeOpenAIChatCheckedStream(buffered: buffered, iteratorBox: iteratorBox)
            }
        }
    }

    return makeOpenAIChatCheckedStream(buffered: buffered, iteratorBox: iteratorBox)
}

private final class OpenAIChatStreamIteratorBox: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<ParseJSONResult<OpenAIChatChunk>, Error>.Iterator

    init(iterator: AsyncThrowingStream<ParseJSONResult<OpenAIChatChunk>, Error>.Iterator) {
        self.iterator = iterator
    }

    func next() async throws -> ParseJSONResult<OpenAIChatChunk>? {
        try await iterator.next()
    }
}

private func makeOpenAIChatCheckedStream(
    buffered: [ParseJSONResult<OpenAIChatChunk>],
    iteratorBox: OpenAIChatStreamIteratorBox
) -> AsyncThrowingStream<ParseJSONResult<OpenAIChatChunk>, Error> {
    AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
        let task = Task {
            do {
                for chunk in buffered {
                    continuation.yield(chunk)
                }
                while let chunk = try await iteratorBox.next() {
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}

private func isOpenAIChatOutputChunk(_ chunk: OpenAIChatChunk) -> Bool {
    guard case .data(let data) = chunk else { return false }
    return data.choices.contains { choice in
        guard let delta = choice.delta else { return false }
        return (delta.content?.isEmpty == false)
            || (delta.toolCalls?.isEmpty == false)
            || (delta.annotations?.isEmpty == false)
    }
}

private func openAIChatStreamError(
    errorData: OpenAIErrorData,
    url: String,
    requestBodyValues: [String: JSONValue],
    responseHeaders: SharedV4Headers?
) -> APICallError {
    let frameJSON = (try? JSONEncoder().encodeToJSONValue(errorData.error)) ?? .string(errorData.error.message)
    return APICallError(
        message: errorData.error.message,
        url: url,
        requestBodyValues: requestBodyValues,
        statusCode: openAIChatStreamErrorStatusCode(errorData.error),
        responseHeaders: responseHeaders,
        responseBody: jsonString(from: frameJSON),
        data: frameJSON
    )
}

private func openAIChatStreamErrorStatusCode(_ error: OpenAIErrorData.ErrorPayload) -> Int {
    if let code = error.code {
        switch code {
        case .number(let value):
            let intValue = Int(value)
            if Double(intValue) == value, (400...599).contains(intValue) {
                return intValue
            }
        case .string(let value):
            if value.range(of: #"^\d{3}$"#, options: .regularExpression) != nil,
               let intValue = Int(value),
               (400...599).contains(intValue) {
                return intValue
            }
        }
    }

    let discriminator = [openAIErrorCodeDescription(error.code), error.type]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

    if discriminator.contains("insufficient_quota") || discriminator.contains("rate_limit") {
        return 429
    }
    if discriminator.contains("authentication") { return 401 }
    if discriminator.contains("permission") { return 403 }
    if discriminator.contains("not_found") { return 404 }
    if discriminator.contains("invalid")
        || discriminator.contains("bad_request")
        || discriminator.contains("context_length") {
        return 400
    }
    if discriminator.contains("overload") { return 503 }
    if discriminator.contains("timeout") { return 504 }

    return 500
}

private func openAIErrorCodeDescription(_ code: OpenAIErrorCode?) -> String? {
    switch code {
    case .none:
        return nil
    case .number(let value):
        return String(value)
    case .string(let value):
        return value
    }
}

private func jsonString(from value: JSONValue) -> String? {
    do {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}
