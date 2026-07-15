import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleChatConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let fetch: FetchFunction?
    public let includeUsage: Bool
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let metadataExtractor: OpenAICompatibleMetadataExtractor?
    public let supportsStructuredOutputs: Bool
    public let supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])?
    public let transformRequestBody: (@Sendable (_ body: [String: JSONValue]) -> [String: JSONValue])?
    public let convertUsage: (@Sendable (_ usage: OpenAICompatibleChatUsage?) -> LanguageModelV4Usage)?
    public let usagePostprocessor: (@Sendable (_ usage: LanguageModelV3Usage) -> LanguageModelV3Usage)?

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        metadataExtractor: OpenAICompatibleMetadataExtractor? = nil,
        supportsStructuredOutputs: Bool = false,
        supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])? = nil,
        transformRequestBody: (@Sendable (_ body: [String: JSONValue]) -> [String: JSONValue])? = nil,
        convertUsage: (@Sendable (_ usage: OpenAICompatibleChatUsage?) -> LanguageModelV4Usage)? = nil,
        usagePostprocessor: (@Sendable (_ usage: LanguageModelV3Usage) -> LanguageModelV3Usage)? = nil
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.includeUsage = includeUsage
        self.errorConfiguration = errorConfiguration
        self.metadataExtractor = metadataExtractor
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.supportedUrls = supportedUrls
        self.transformRequestBody = transformRequestBody
        self.convertUsage = convertUsage
        self.usagePostprocessor = usagePostprocessor
    }
}

private enum OpenAICompatibleChatPromptInput: Sendable {
    case v3(LanguageModelV3Prompt)
    case v4(LanguageModelV4Prompt)
}

private enum OpenAICompatibleChatToolsInput: Sendable {
    case v3([LanguageModelV3Tool]?, LanguageModelV3ToolChoice?)
    case v4([LanguageModelV4Tool]?, LanguageModelV4ToolChoice?)
}

private enum OpenAICompatibleChatContract: Sendable {
    case v3
    case v4

    private var isV4: Bool {
        switch self {
        case .v3: return false
        case .v4: return true
        }
    }

    var textBlockId: String { isV4 ? "txt-0" : "0" }
    var emitsEmptyInitialToolArgumentDelta: Bool { !isV4 }
    var usesReasoningFallbackInGenerate: Bool { isV4 }
    var usesCamelCaseProviderOptions: Bool { isV4 }
    var usesV4StreamBlockLifecycle: Bool { isV4 }
    var buffersToolCallsUntilName: Bool { isV4 }
    var includesToolCallProviderMetadata: Bool { isV4 }
    var includesEmptyStreamProviderMetadata: Bool { isV4 }
    var usesV4StreamErrorPayload: Bool { isV4 }
    var toolCallTypeValidation: StreamingToolCallTypeValidation { isV4 ? .none : .ifPresent }
}

private struct OpenAICompatibleChatCallSettings: Sendable {
    let contract: OpenAICompatibleChatContract
    let prompt: OpenAICompatibleChatPromptInput
    let maxOutputTokens: Int?
    let temperature: Double?
    let stopSequences: [String]?
    let topP: Double?
    let topK: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let responseFormat: LanguageModelV4ResponseFormat?
    let seed: Int?
    let tools: OpenAICompatibleChatToolsInput
    let includeRawChunks: Bool?
    let abortSignal: (@Sendable () -> Bool)?
    let headers: SharedV4Headers?
    let reasoning: LanguageModelV4ReasoningEffort?
    let providerOptions: SharedV4ProviderOptions?

    init(v3 options: LanguageModelV3CallOptions) {
        contract = .v3
        prompt = .v3(options.prompt)
        maxOutputTokens = options.maxOutputTokens
        temperature = options.temperature
        stopSequences = options.stopSequences
        topP = options.topP
        topK = options.topK
        presencePenalty = options.presencePenalty
        frequencyPenalty = options.frequencyPenalty
        responseFormat = options.responseFormat.map(convertOpenAICompatibleResponseFormatToV4)
        seed = options.seed
        tools = .v3(options.tools, options.toolChoice)
        includeRawChunks = options.includeRawChunks
        abortSignal = options.abortSignal
        headers = options.headers
        reasoning = nil
        providerOptions = options.providerOptions
    }

    init(v4 options: LanguageModelV4CallOptions) {
        contract = .v4
        prompt = .v4(options.prompt)
        maxOutputTokens = options.maxOutputTokens
        temperature = options.temperature
        stopSequences = options.stopSequences
        topP = options.topP
        topK = options.topK
        presencePenalty = options.presencePenalty
        frequencyPenalty = options.frequencyPenalty
        responseFormat = options.responseFormat
        seed = options.seed
        tools = .v4(options.tools, options.toolChoice)
        includeRawChunks = options.includeRawChunks
        abortSignal = options.abortSignal
        headers = options.headers
        reasoning = options.reasoning
        providerOptions = options.providerOptions
    }
}

private struct OpenAICompatibleChatLanguageModelCore: Sendable {
    private let modelIdentifier: OpenAICompatibleChatModelId
    private let config: OpenAICompatibleChatConfig
    private let providerOptionsName: String

    init(modelId: OpenAICompatibleChatModelId, config: OpenAICompatibleChatConfig) {
        self.modelIdentifier = modelId
        self.config = config
        self.providerOptionsName = config.provider.split(separator: ".").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }

    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            try await config.supportedUrls?() ?? [:]
        }
    }

    func doGenerate(options: OpenAICompatibleChatCallSettings) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let transformedBody = transformRequestBody(prepared.body)
        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
            headers: headers,
            body: JSONValue.object(transformedBody),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAICompatibleChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let choice = response.value.choices.first else {
            throw APICallError(
                message: "OpenAI-compatible response did not include choices.",
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
                requestBodyValues: transformedBody
            )
        }

        var content: [LanguageModelV4Content] = []

        if let text = choice.message.content, !text.isEmpty {
            content.append(.text(LanguageModelV4Text(text: text)))
        }

        let reasoning = choice.message.reasoningContent
            ?? (options.contract.usesReasoningFallbackInGenerate ? choice.message.reasoning : nil)
        if let reasoning, !reasoning.isEmpty {
            content.append(.reasoning(LanguageModelV4Reasoning(text: reasoning)))
        }

        if let toolCalls = choice.message.toolCalls {
            for toolCall in toolCalls {
                let function = toolCall.function
                let toolCallId = toolCall.id ?? generateID()
                let thoughtSignature = toolCall.extraContent?.google?.thoughtSignature
                let toolMetadata = options.contract.includesToolCallProviderMetadata
                    ? thoughtSignature.map {
                        [prepared.metadataKey: ["thoughtSignature": JSONValue.string($0)]]
                    }
                    : nil
                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: function.name,
                    input: function.arguments,
                    providerExecuted: nil,
                    providerMetadata: toolMetadata
                )))
            }
        }

        let rawJSON = try decodeJSONValue(from: response.rawValue)
        let usageRaw = extractUsage(from: rawJSON)
        let usage = convertUsage(response.value.usage, raw: usageRaw)
        let rawFinishReason = choice.finishReason
        let finishReason = LanguageModelV4FinishReason(
            unified: mapOpenAICompatibleFinishReasonV4(rawFinishReason),
            raw: rawFinishReason
        )
        let metadata = responseMetadata(id: response.value.id, model: response.value.model, created: response.value.created)

        let extractedMetadata = try await config.metadataExtractor?.extractMetadata(parsedBody: rawJSON)
        let providerMetadata = makeProviderMetadata(
            usage: response.value.usage,
            extractedMetadata: extractedMetadata,
            metadataKey: prepared.metadataKey
        )

        return LanguageModelV4GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV4RequestInfo(body: transformedBody),
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

    func doStream(options: OpenAICompatibleChatCallSettings) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        if config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }
        let transformedBody = transformRequestBody(body)

        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let eventStream = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
            headers: headers,
            body: JSONValue.object(transformedBody),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAICompatibleChatChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let metadataExtractor = config.metadataExtractor?.createStreamExtractor()
        let metadataKey = prepared.metadataKey

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            let task = Task {
                var finishReason = LanguageModelV4FinishReason(unified: .other, raw: nil)
                var usage: OpenAICompatibleChatUsage?
                var usageRaw: JSONValue?
                var isFirstChunk = true
                var isActiveText = false
                var isActiveReasoning = false
                var pendingToolCalls: [Int: PendingToolCall] = [:]
                var forwardedToolCallIndices: Set<Int> = []

                let toolCallTracker = StreamingToolCallTracker(
                    enqueue: { part in continuation.yield(part) },
                    options: StreamingToolCallTrackerOptions(
                        typeValidation: options.contract.toolCallTypeValidation,
                        emitsEmptyInitialArgumentDelta: options.contract.emitsEmptyInitialToolArgumentDelta,
                        extractMetadata: {
                            options.contract.includesToolCallProviderMetadata
                                ? $0.providerMetadata
                                : nil
                        },
                        buildToolCallProviderMetadata: { $0 }
                    )
                )

                do {
                    for try await parseResult in eventStream.value {
                        if options.includeRawChunks == true, let rawJSON = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: rawJSON))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .string(String(describing: error))))
                        case .success(let chunk, let raw):
                            if let metadataExtractor, let json = try? jsonValue(from: raw) {
                                metadataExtractor.processChunk(json)
                            }

                            switch chunk {
                            case .error(let errorData):
                                finishReason = .init(unified: .error, raw: nil)
                                if options.contract.usesV4StreamErrorPayload {
                                    continuation.yield(.error(error: .string(errorData.error.message)))
                                } else if let encoded = try? JSONEncoder().encodeToJSONValue(errorData) {
                                    continuation.yield(.error(error: encoded))
                                } else {
                                    continuation.yield(.error(error: .string(errorData.error.message)))
                                }
                            case .data(let data):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let meta = responseMetadata(id: data.id, model: data.model, created: data.created)
                                    continuation.yield(.responseMetadata(id: meta.id, modelId: meta.modelId, timestamp: meta.timestamp))
                                }

                                if let usageValue = data.usage {
                                    usage = usageValue
                                    usageRaw = extractUsage(from: parseResult.rawJSONValue)
                                }

                                guard let choice = data.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = LanguageModelV4FinishReason(
                                        unified: mapOpenAICompatibleFinishReasonV4(finish),
                                        raw: finish
                                    )
                                }

                                if let delta = choice.delta {
                                    if let reasoning = delta.reasoningContent ?? delta.reasoning, !reasoning.isEmpty {
                                        if !isActiveReasoning {
                                            isActiveReasoning = true
                                            continuation.yield(.reasoningStart(id: "reasoning-0", providerMetadata: nil))
                                        }
                                        continuation.yield(.reasoningDelta(id: "reasoning-0", delta: reasoning, providerMetadata: nil))
                                    }

                                    if let text = delta.content, !text.isEmpty {
                                        if options.contract.usesV4StreamBlockLifecycle, isActiveReasoning {
                                            isActiveReasoning = false
                                            continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                                        }
                                        if !isActiveText {
                                            isActiveText = true
                                            continuation.yield(.textStart(
                                                id: options.contract.textBlockId,
                                                providerMetadata: nil
                                            ))
                                        }
                                        continuation.yield(.textDelta(
                                            id: options.contract.textBlockId,
                                            delta: text,
                                            providerMetadata: nil
                                        ))
                                    }

                                    if let toolCallDeltas = delta.toolCalls {
                                        if options.contract.usesV4StreamBlockLifecycle, isActiveReasoning {
                                            isActiveReasoning = false
                                            continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                                        }
                                        for toolCallDelta in toolCallDeltas {
                                            try processToolCallDelta(
                                                toolCallDelta,
                                                metadataKey: metadataKey,
                                                pending: &pendingToolCalls,
                                                forwardedIndices: &forwardedToolCallIndices,
                                                tracker: toolCallTracker,
                                                contract: options.contract
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if options.contract.usesV4StreamBlockLifecycle {
                        if isActiveReasoning {
                            continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                        }
                        if isActiveText {
                            continuation.yield(.textEnd(
                                id: options.contract.textBlockId,
                                providerMetadata: nil
                            ))
                        }
                    } else {
                        if isActiveText {
                            continuation.yield(.textEnd(
                                id: options.contract.textBlockId,
                                providerMetadata: nil
                            ))
                        }
                        if isActiveReasoning {
                            continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                        }
                    }

                    for (index, pending) in pendingToolCalls.sorted(by: { $0.key < $1.key }) {
                        try toolCallTracker.processDelta(StreamingToolCallDelta(
                            index: index,
                            id: pending.id,
                            function: StreamingToolCallFunctionDelta(arguments: pending.arguments),
                            providerMetadata: pending.providerMetadata
                        ))
                    }
                    toolCallTracker.flush()

                    var providerMetadata: SharedV4ProviderMetadata = options.contract.includesEmptyStreamProviderMetadata
                        ? [metadataKey: [:]]
                        : [:]
                    if let extracted = metadataExtractor?.buildMetadata() {
                        providerMetadata.merge(extracted) { _, new in new }
                    }
                    var providerEntry = providerMetadata[metadataKey] ?? [:]
                    if let accepted = usage?.completionTokensDetails?.acceptedPredictionTokens {
                        providerEntry["acceptedPredictionTokens"] = .number(Double(accepted))
                    }
                    if let rejected = usage?.completionTokensDetails?.rejectedPredictionTokens {
                        providerEntry["rejectedPredictionTokens"] = .number(Double(rejected))
                    }
                    if options.contract.includesEmptyStreamProviderMetadata
                        || providerMetadata[metadataKey] != nil
                        || !providerEntry.isEmpty {
                        providerMetadata[metadataKey] = providerEntry
                    }

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: convertUsage(usage, raw: usageRaw),
                        providerMetadata: providerMetadata.isEmpty ? nil : providerMetadata
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
            request: LanguageModelV4RequestInfo(body: transformedBody),
            response: LanguageModelV4StreamResponseInfo(headers: eventStream.responseHeaders)
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
        let metadataKey: String
    }

    private func prepareRequest(options: OpenAICompatibleChatCallSettings) async throws -> PreparedRequest {
        var warnings: [SharedV4Warning] = []

        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }

        let deprecatedOptions = try await parseProviderOptions(
            provider: "openai-compatible",
            providerOptions: options.providerOptions,
            schema: openAICompatibleProviderOptionsSchema
        )

        if deprecatedOptions != nil {
            warnings.append(.deprecated(
                setting: "providerOptions key 'openai-compatible'",
                message: "Use 'openaiCompatible' instead."
            ))
        }

        let camelCaseProviderOptionsName = openAICompatibleCamelCase(providerOptionsName)
        if options.contract.usesCamelCaseProviderOptions,
           let warning = openAICompatibleDeprecatedProviderOptionsWarning(
               rawName: providerOptionsName,
               providerOptions: options.providerOptions
           ) {
            warnings.append(warning)
        }

        let compatibleOptions = try await parseProviderOptions(
            provider: "openaiCompatible",
            providerOptions: options.providerOptions,
            schema: openAICompatibleProviderOptionsSchema
        ) ?? OpenAICompatibleChatProviderOptions()

        let providerSpecificOptions = try await parseProviderOptions(
            provider: providerOptionsName,
            providerOptions: options.providerOptions,
            schema: openAICompatibleProviderOptionsSchema
        ) ?? OpenAICompatibleChatProviderOptions()

        let camelCaseProviderOptions: OpenAICompatibleChatProviderOptions
        if options.contract.usesCamelCaseProviderOptions {
            camelCaseProviderOptions = try await parseProviderOptions(
                provider: camelCaseProviderOptionsName,
                providerOptions: options.providerOptions,
                schema: openAICompatibleProviderOptionsSchema
            ) ?? OpenAICompatibleChatProviderOptions()
        } else {
            camelCaseProviderOptions = OpenAICompatibleChatProviderOptions()
        }

        // V4 merge order matches upstream: deprecated -> compatible -> raw provider -> camel provider.
        var mergedOptions = deprecatedOptions ?? OpenAICompatibleChatProviderOptions()
        if let user = compatibleOptions.user { mergedOptions.user = user }
        if let reasoningEffort = compatibleOptions.reasoningEffort { mergedOptions.reasoningEffort = reasoningEffort }
        if let textVerbosity = compatibleOptions.textVerbosity { mergedOptions.textVerbosity = textVerbosity }
        if let strictJsonSchema = compatibleOptions.strictJsonSchema { mergedOptions.strictJsonSchema = strictJsonSchema }

        if let user = providerSpecificOptions.user {
            mergedOptions.user = user
        }
        if let reasoningEffort = providerSpecificOptions.reasoningEffort {
            mergedOptions.reasoningEffort = reasoningEffort
        }
        if let textVerbosity = providerSpecificOptions.textVerbosity {
            mergedOptions.textVerbosity = textVerbosity
        }
        if let strictJsonSchema = providerSpecificOptions.strictJsonSchema {
            mergedOptions.strictJsonSchema = strictJsonSchema
        }

        if options.contract.usesCamelCaseProviderOptions {
            if let user = camelCaseProviderOptions.user {
                mergedOptions.user = user
            }
            if let reasoningEffort = camelCaseProviderOptions.reasoningEffort {
                mergedOptions.reasoningEffort = reasoningEffort
            }
            if let textVerbosity = camelCaseProviderOptions.textVerbosity {
                mergedOptions.textVerbosity = textVerbosity
            }
            if let strictJsonSchema = camelCaseProviderOptions.strictJsonSchema {
                mergedOptions.strictJsonSchema = strictJsonSchema
            }
        }

        var providerSpecificRaw = options.providerOptions?[providerOptionsName] ?? [:]
        if options.contract.usesCamelCaseProviderOptions {
            providerSpecificRaw.merge(options.providerOptions?[camelCaseProviderOptionsName] ?? [:]) { _, new in new }
        }
        let forwardedOptions = providerSpecificRaw.filter { key, _ in
            !["user", "reasoningEffort", "textVerbosity", "strictJsonSchema"].contains(key)
        }

        let messages: [JSONValue]
        switch options.prompt {
        case .v3(let prompt):
            messages = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        case .v4(let prompt):
            messages = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        }

        // Warning only if schema is present but structuredOutputs not supported
        if case let .json(schema, _, _) = options.responseFormat,
           schema != nil,
           !config.supportsStructuredOutputs {
            warnings.append(.unsupported(
                feature: "responseFormat",
                details: "JSON response format schema is only supported with structuredOutputs"
            ))
        }

        let preparedTools: OpenAICompatiblePreparedToolsV4
        switch options.tools {
        case let .v3(tools, toolChoice):
            let prepared = OpenAICompatibleToolPreparer.prepare(tools: tools, toolChoice: toolChoice)
            preparedTools = OpenAICompatiblePreparedToolsV4(
                tools: prepared.tools,
                toolChoice: prepared.toolChoice,
                warnings: prepared.warnings.map(convertOpenAICompatibleWarningToV4)
            )
        case let .v4(tools, toolChoice):
            preparedTools = OpenAICompatibleToolPreparer.prepare(tools: tools, toolChoice: toolChoice)
        }
        warnings.append(contentsOf: preparedTools.warnings)

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(messages)
        ]

        if let user = mergedOptions.user {
            body["user"] = .string(user)
        }
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

        if let responseFormat = options.responseFormat {
            switch responseFormat {
            case .text:
                break
            case let .json(schema, name, description):
                // Only use json_schema if BOTH supportsStructuredOutputs AND schema are present
                if config.supportsStructuredOutputs, let schema {
                    let strictJsonSchema = mergedOptions.strictJsonSchema ?? true
                    var payload: [String: JSONValue] = [
                        "schema": schema,
                        "name": .string(name ?? "response"),
                        "strict": .bool(strictJsonSchema)
                    ]
                    if let description {
                        payload["description"] = .string(description)
                    }
                    body["response_format"] = .object([
                        "type": .string("json_schema"),
                        "json_schema": .object(payload)
                    ])
                } else {
                    // Use json_object if either condition is false
                    body["response_format"] = .object(["type": .string("json_object")])
                }
            }
        }

        let topLevelReasoning: String?
        switch options.reasoning {
        case .some(.minimal), .some(.low), .some(.medium), .some(.high), .some(.xhigh):
            topLevelReasoning = options.reasoning?.rawValue
        case .some(.providerDefault), .some(.none), nil:
            topLevelReasoning = nil
        }
        if let reasoning = mergedOptions.reasoningEffort ?? topLevelReasoning {
            body["reasoning_effort"] = .string(reasoning)
        }
        if let verbosity = mergedOptions.textVerbosity {
            body["verbosity"] = .string(verbosity)
        }

        if let tools = preparedTools.tools {
            body["tools"] = tools
        }
        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = toolChoice
        }

        for (key, value) in forwardedOptions {
            body[key] = value
        }

        let metadataKey = options.contract.usesCamelCaseProviderOptions
            && camelCaseProviderOptionsName != providerOptionsName
            && options.providerOptions?[camelCaseProviderOptionsName] != nil
            ? camelCaseProviderOptionsName
            : providerOptionsName

        return PreparedRequest(body: body, warnings: warnings, metadataKey: metadataKey)
    }

    private func convertUsage(
        _ usage: OpenAICompatibleChatUsage?,
        raw: JSONValue?
    ) -> LanguageModelV4Usage {
        let converted: LanguageModelV4Usage
        if let customConvertUsage = config.convertUsage {
            converted = customConvertUsage(usage)
        } else if let usage {
            let promptTokens = usage.promptTokens ?? 0
            let completionTokens = usage.completionTokens ?? 0
            let cacheReadTokens = usage.promptTokensDetails?.cachedTokens ?? 0
            let reasoningTokens = usage.completionTokensDetails?.reasoningTokens ?? 0

            converted = LanguageModelV4Usage(
                inputTokens: .init(
                    total: promptTokens,
                    noCache: promptTokens - cacheReadTokens,
                    cacheRead: cacheReadTokens,
                    cacheWrite: nil
                ),
                outputTokens: .init(
                    total: completionTokens,
                    text: completionTokens - reasoningTokens,
                    reasoning: reasoningTokens
                ),
                raw: raw == .null ? nil : raw
            )
        } else {
            converted = LanguageModelV4Usage()
        }

        guard let usagePostprocessor = config.usagePostprocessor else {
            return converted
        }

        return convertOpenAICompatibleUsageToV4(
            usagePostprocessor(convertOpenAICompatibleUsageToV3(converted))
        )
    }

    private func extractUsage(from json: JSONValue?) -> JSONValue? {
        guard let json, case .object(let dict) = json else { return nil }
        guard let usage = dict["usage"], usage != .null else { return nil }
        return usage
    }

    private func transformRequestBody(_ body: [String: JSONValue]) -> [String: JSONValue] {
        config.transformRequestBody?(body) ?? body
    }

    private func makeProviderMetadata(
        usage: OpenAICompatibleChatUsage?,
        extractedMetadata: SharedV4ProviderMetadata?,
        metadataKey: String
    ) -> SharedV4ProviderMetadata {
        var metadata = extractedMetadata ?? [:]
        var providerEntry = metadata[metadataKey] ?? [:]

        if let accepted = usage?.completionTokensDetails?.acceptedPredictionTokens {
            providerEntry["acceptedPredictionTokens"] = .number(Double(accepted))
        }
        if let rejected = usage?.completionTokensDetails?.rejectedPredictionTokens {
            providerEntry["rejectedPredictionTokens"] = .number(Double(rejected))
        }

        metadata[metadataKey] = providerEntry

        return metadata
    }

    private func responseMetadata(id: String?, model: String?, created: Double?) -> (id: String?, modelId: String?, timestamp: Date?) {
        let timestamp = created.map { Date(timeIntervalSince1970: $0) }
        return (id, model, timestamp)
    }

    private func decodeJSONValue(from raw: Any?) throws -> JSONValue {
        guard let raw else { return .null }
        return try jsonValue(from: raw)
    }

    private struct PendingToolCall {
        var id: String?
        var arguments: String
        var providerMetadata: SharedV4ProviderMetadata?
    }

    private func processToolCallDelta(
        _ delta: OpenAICompatibleChatChunkToolCallDelta,
        metadataKey: String,
        pending: inout [Int: PendingToolCall],
        forwardedIndices: inout Set<Int>,
        tracker: StreamingToolCallTracker,
        contract: OpenAICompatibleChatContract
    ) throws {
        let thoughtSignature = delta.extraContent?.google?.thoughtSignature
        let providerMetadata = contract.includesToolCallProviderMetadata
            ? thoughtSignature.map {
                [metadataKey: ["thoughtSignature": JSONValue.string($0)]]
            }
            : nil

        if !contract.buffersToolCallsUntilName {
            try tracker.processDelta(StreamingToolCallDelta(
                index: delta.index,
                id: delta.id,
                type: delta.type,
                function: StreamingToolCallFunctionDelta(
                    name: delta.function?.name,
                    arguments: delta.function?.arguments
                )
            ))
            return
        }

        guard let index = delta.index else {
            try tracker.processDelta(StreamingToolCallDelta(
                id: delta.id,
                type: delta.type,
                function: StreamingToolCallFunctionDelta(
                    name: delta.function?.name,
                    arguments: delta.function?.arguments
                ),
                providerMetadata: providerMetadata
            ))
            return
        }

        if forwardedIndices.contains(index) {
            try tracker.processDelta(StreamingToolCallDelta(
                index: index,
                id: delta.id,
                type: delta.type,
                function: StreamingToolCallFunctionDelta(
                    name: delta.function?.name,
                    arguments: delta.function?.arguments
                ),
                providerMetadata: providerMetadata
            ))
            return
        }

        var state = pending[index] ?? PendingToolCall(
            id: delta.id,
            arguments: "",
            providerMetadata: providerMetadata
        )
        if state.id == nil {
            state.id = delta.id
        }
        if state.providerMetadata == nil {
            state.providerMetadata = providerMetadata
        }
        if let arguments = delta.function?.arguments {
            state.arguments += arguments
        }

        guard let name = delta.function?.name else {
            pending[index] = state
            return
        }

        try tracker.processDelta(StreamingToolCallDelta(
            index: index,
            id: state.id,
            function: StreamingToolCallFunctionDelta(name: name, arguments: state.arguments),
            providerMetadata: state.providerMetadata
        ))
        pending.removeValue(forKey: index)
        forwardedIndices.insert(index)
    }
}

public final class OpenAICompatibleChatLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleChatModelId
    private let core: OpenAICompatibleChatLanguageModelCore

    public init(modelId: OpenAICompatibleChatModelId, config: OpenAICompatibleChatConfig) {
        modelIdentifier = modelId
        core = OpenAICompatibleChatLanguageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await core.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let result = try await core.doGenerate(options: OpenAICompatibleChatCallSettings(v3: options))
        return try convertOpenAICompatibleGenerateResultToV3(result)
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let result = try await core.doStream(options: OpenAICompatibleChatCallSettings(v3: options))
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await part in result.stream {
                        continuation.yield(try convertOpenAICompatibleStreamPartToV3(part))
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
            request: result.request.map { LanguageModelV3RequestInfo(body: $0.body) },
            response: result.response.map { LanguageModelV3StreamResponseInfo(headers: $0.headers) }
        )
    }
}

public final class OpenAICompatibleChatLanguageModelV4: LanguageModelV4 {
    private let core: OpenAICompatibleChatLanguageModelCore

    public init(modelId: OpenAICompatibleChatModelId, config: OpenAICompatibleChatConfig) {
        core = OpenAICompatibleChatLanguageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await core.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        try await core.doGenerate(options: OpenAICompatibleChatCallSettings(v4: options))
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        try await core.doStream(options: OpenAICompatibleChatCallSettings(v4: options))
    }
}

private func convertOpenAICompatibleResponseFormatToV4(
    _ value: LanguageModelV3ResponseFormat
) -> LanguageModelV4ResponseFormat {
    switch value {
    case .text:
        return .text
    case let .json(schema, name, description):
        return .json(schema: schema, name: name, description: description)
    }
}

private func convertOpenAICompatibleGenerateResultToV3(
    _ result: LanguageModelV4GenerateResult
) throws -> LanguageModelV3GenerateResult {
    LanguageModelV3GenerateResult(
        content: try result.content.map(convertOpenAICompatibleContentToV3),
        finishReason: convertOpenAICompatibleFinishReasonToV3(result.finishReason),
        usage: convertOpenAICompatibleUsageToV3(result.usage),
        providerMetadata: result.providerMetadata,
        request: result.request.map { LanguageModelV3RequestInfo(body: $0.body) },
        response: result.response.map {
            LanguageModelV3ResponseInfo(
                id: $0.id,
                timestamp: $0.timestamp,
                modelId: $0.modelId,
                headers: $0.headers,
                body: $0.body
            )
        },
        warnings: result.warnings.map(convertOpenAICompatibleWarningToV3)
    )
}

private func convertOpenAICompatibleContentToV3(
    _ value: LanguageModelV4Content
) throws -> LanguageModelV3Content {
    switch value {
    case .text(let content):
        return .text(LanguageModelV3Text(text: content.text, providerMetadata: content.providerMetadata))
    case .reasoning(let content):
        return .reasoning(LanguageModelV3Reasoning(text: content.text, providerMetadata: content.providerMetadata))
    case .toolCall(let toolCall):
        return .toolCall(LanguageModelV3ToolCall(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: toolCall.input,
            providerExecuted: toolCall.providerExecuted,
            dynamic: toolCall.dynamic,
            providerMetadata: toolCall.providerMetadata
        ))
    default:
        throw UnsupportedFunctionalityError(functionality: "OpenAI-compatible V4 content \(value) on V3 facade")
    }
}

private func convertOpenAICompatibleStreamPartToV3(
    _ value: LanguageModelV4StreamPart
) throws -> LanguageModelV3StreamPart {
    switch value {
    case let .textStart(id, providerMetadata):
        return .textStart(id: id, providerMetadata: providerMetadata)
    case let .textDelta(id, delta, providerMetadata):
        return .textDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .textEnd(id, providerMetadata):
        return .textEnd(id: id, providerMetadata: providerMetadata)
    case let .reasoningStart(id, providerMetadata):
        return .reasoningStart(id: id, providerMetadata: providerMetadata)
    case let .reasoningDelta(id, delta, providerMetadata):
        return .reasoningDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .reasoningEnd(id, providerMetadata):
        return .reasoningEnd(id: id, providerMetadata: providerMetadata)
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
        return .toolCall(LanguageModelV3ToolCall(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: toolCall.input,
            providerExecuted: toolCall.providerExecuted,
            dynamic: toolCall.dynamic,
            providerMetadata: toolCall.providerMetadata
        ))
    case let .streamStart(warnings):
        return .streamStart(warnings: warnings.map(convertOpenAICompatibleWarningToV3))
    case let .responseMetadata(id, modelId, timestamp):
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)
    case let .finish(finishReason, usage, providerMetadata):
        return .finish(
            finishReason: convertOpenAICompatibleFinishReasonToV3(finishReason),
            usage: convertOpenAICompatibleUsageToV3(usage),
            providerMetadata: providerMetadata
        )
    case let .raw(rawValue):
        return .raw(rawValue: rawValue)
    case let .error(error):
        return .error(error: error)
    default:
        throw UnsupportedFunctionalityError(functionality: "OpenAI-compatible V4 stream part \(value) on V3 facade")
    }
}

private func convertOpenAICompatibleFinishReasonToV3(
    _ value: LanguageModelV4FinishReason
) -> LanguageModelV3FinishReason {
    LanguageModelV3FinishReason(
        unified: LanguageModelV3FinishReason.Unified(rawValue: value.unified.rawValue) ?? .other,
        raw: value.raw
    )
}

private func convertOpenAICompatibleUsageToV3(
    _ value: LanguageModelV4Usage
) -> LanguageModelV3Usage {
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

private func convertOpenAICompatibleUsageToV4(
    _ value: LanguageModelV3Usage
) -> LanguageModelV4Usage {
    LanguageModelV4Usage(
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

private func convertOpenAICompatibleWarningToV4(_ value: SharedV3Warning) -> SharedV4Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .other(message):
        return .other(message: message)
    }
}

private func convertOpenAICompatibleWarningToV3(_ value: SharedV4Warning) -> SharedV3Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .deprecated(setting, message):
        if setting == "providerOptions key 'openai-compatible'" {
            return .other(message: "The 'openai-compatible' key in providerOptions is deprecated. Use 'openaiCompatible' instead.")
        }
        return .other(message: "\(setting): \(message)")
    case let .other(message):
        return .other(message: message)
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let openAICompatibleChatResponseSchema = FlexibleSchema(
    Schema<OpenAICompatibleChatResponse>.codable(
        OpenAICompatibleChatResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let openAICompatibleChatChunkSchema = FlexibleSchema(
    Schema<OpenAICompatibleChatStreamChunk>.codable(
        OpenAICompatibleChatStreamChunk.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private struct OpenAICompatibleChatExtraContent: Codable {
    struct Google: Codable {
        let thoughtSignature: String?

        private enum CodingKeys: String, CodingKey {
            case thoughtSignature = "thought_signature"
        }
    }

    let google: Google?
}

public struct OpenAICompatibleChatUsage: Codable, Sendable, Equatable {
    public struct PromptTokensDetails: Codable, Sendable, Equatable {
        public let cachedTokens: Int?

        public init(cachedTokens: Int? = nil) {
            self.cachedTokens = cachedTokens
        }

        private enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    public struct CompletionTokensDetails: Codable, Sendable, Equatable {
        public let reasoningTokens: Int?
        public let acceptedPredictionTokens: Int?
        public let rejectedPredictionTokens: Int?

        public init(
            reasoningTokens: Int? = nil,
            acceptedPredictionTokens: Int? = nil,
            rejectedPredictionTokens: Int? = nil
        ) {
            self.reasoningTokens = reasoningTokens
            self.acceptedPredictionTokens = acceptedPredictionTokens
            self.rejectedPredictionTokens = rejectedPredictionTokens
        }

        private enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
            case acceptedPredictionTokens = "accepted_prediction_tokens"
            case rejectedPredictionTokens = "rejected_prediction_tokens"
        }
    }

    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
    public let promptTokensDetails: PromptTokensDetails?
    public let completionTokensDetails: CompletionTokensDetails?
    public let raw: JSONValue?

    public init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        promptTokensDetails: PromptTokensDetails? = nil,
        completionTokensDetails: CompletionTokensDetails? = nil,
        raw: JSONValue? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.promptTokensDetails = promptTokensDetails
        self.completionTokensDetails = completionTokensDetails
        self.raw = raw
    }

    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        guard case .object(let object) = raw else {
            throw DecodingError.typeMismatch(
                [String: JSONValue].self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected OpenAI-compatible usage to be an object."
                )
            )
        }

        promptTokens = Self.integer(object["prompt_tokens"])
        completionTokens = Self.integer(object["completion_tokens"])
        totalTokens = Self.integer(object["total_tokens"])

        if case .object(let details)? = object["prompt_tokens_details"] {
            promptTokensDetails = PromptTokensDetails(
                cachedTokens: Self.integer(details["cached_tokens"])
            )
        } else {
            promptTokensDetails = nil
        }

        if case .object(let details)? = object["completion_tokens_details"] {
            completionTokensDetails = CompletionTokensDetails(
                reasoningTokens: Self.integer(details["reasoning_tokens"]),
                acceptedPredictionTokens: Self.integer(details["accepted_prediction_tokens"]),
                rejectedPredictionTokens: Self.integer(details["rejected_prediction_tokens"])
            )
        } else {
            completionTokensDetails = nil
        }

        self.raw = raw
    }

    public func encode(to encoder: Encoder) throws {
        var object: [String: JSONValue]
        if case .object(let rawObject) = raw {
            object = rawObject
        } else {
            object = [:]
        }

        if let promptTokens {
            object["prompt_tokens"] = .number(Double(promptTokens))
        }
        if let completionTokens {
            object["completion_tokens"] = .number(Double(completionTokens))
        }
        if let totalTokens {
            object["total_tokens"] = .number(Double(totalTokens))
        }
        if let promptTokensDetails {
            var details = Self.object(object["prompt_tokens_details"])
            if let cachedTokens = promptTokensDetails.cachedTokens {
                details["cached_tokens"] = .number(Double(cachedTokens))
            }
            object["prompt_tokens_details"] = .object(details)
        }
        if let completionTokensDetails {
            var details = Self.object(object["completion_tokens_details"])
            if let reasoningTokens = completionTokensDetails.reasoningTokens {
                details["reasoning_tokens"] = .number(Double(reasoningTokens))
            }
            if let acceptedPredictionTokens = completionTokensDetails.acceptedPredictionTokens {
                details["accepted_prediction_tokens"] = .number(Double(acceptedPredictionTokens))
            }
            if let rejectedPredictionTokens = completionTokensDetails.rejectedPredictionTokens {
                details["rejected_prediction_tokens"] = .number(Double(rejectedPredictionTokens))
            }
            object["completion_tokens_details"] = .object(details)
        }

        try JSONValue.object(object).encode(to: encoder)
    }

    private static func integer(_ value: JSONValue?) -> Int? {
        guard case .number(let number) = value else { return nil }
        return Int(exactly: number)
    }

    private static func object(_ value: JSONValue?) -> [String: JSONValue] {
        guard case .object(let object) = value else { return [:] }
        return object
    }
}

private struct OpenAICompatibleChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            enum Role: String, Codable {
                case assistant
            }

            struct ToolCall: Codable {
                struct ToolFunction: Codable {
                    let name: String
                    let arguments: String

                    private enum CodingKeys: String, CodingKey {
                        case name
                        case arguments
                    }
                }

                let id: String?
                let type: String?
                let function: ToolFunction
                let extraContent: OpenAICompatibleChatExtraContent?

                private enum CodingKeys: String, CodingKey {
                    case id
                    case type
                    case function
                    case extraContent = "extra_content"
                }
            }

            let role: Role?
            let content: String?
            let reasoningContent: String?
            let reasoning: String?
            let toolCalls: [ToolCall]?

            private enum CodingKeys: String, CodingKey {
                case role
                case content
                case reasoningContent = "reasoning_content"
                case reasoning
                case toolCalls = "tool_calls"
            }
        }

        let message: Message
        let finishReason: String?
        let logprobs: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
            case logprobs
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: OpenAICompatibleChatUsage?

    private enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case usage
    }
}

private enum OpenAICompatibleChatStreamChunk: Codable {
    case data(OpenAICompatibleChatStreamData)
    case error(OpenAICompatibleErrorData)

    private enum CodingKeys: String, CodingKey {
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.error) {
            let error = try OpenAICompatibleErrorData(from: decoder)
            self = .error(error)
        } else {
            let data = try OpenAICompatibleChatStreamData(from: decoder)
            self = .data(data)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .data(let data):
            try data.encode(to: encoder)
        case .error(let error):
            try error.encode(to: encoder)
        }
    }
}

private struct OpenAICompatibleChatStreamData: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            enum Role: String, Codable {
                case assistant
                case empty = ""
            }

            let role: Role?
            let content: String?
            let reasoningContent: String?
            let reasoning: String?
            let toolCalls: [OpenAICompatibleChatChunkToolCallDelta]?

            private enum CodingKeys: String, CodingKey {
                case role
                case content
                case reasoningContent = "reasoning_content"
                case reasoning
                case toolCalls = "tool_calls"
            }
        }

        let delta: Delta?
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: OpenAICompatibleChatUsage?

    private enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case usage
    }
}

private struct OpenAICompatibleChatChunkToolCallDelta: Codable {
    struct ToolFunction: Codable {
        let name: String?
        let arguments: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case arguments
        }
    }

    let index: Int?
    let id: String?
    let type: String?
    let function: ToolFunction?
    let extraContent: OpenAICompatibleChatExtraContent?

    private enum CodingKeys: String, CodingKey {
        case index
        case id
        case type
        case function
        case extraContent = "extra_content"
    }
}

private extension ParseJSONResult where Output == OpenAICompatibleChatStreamChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}
