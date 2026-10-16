import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleChatConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () throws -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) throws -> String
    public let fetch: FetchFunction?
    public let includeUsage: Bool
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let metadataExtractor: OpenAICompatibleMetadataExtractor?
    public let supportsStructuredOutputs: Bool
    public let supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])?
    public let transformRequestBody: (@Sendable (_ body: [String: JSONValue]) -> [String: JSONValue])?
    public let convertUsage: (@Sendable (_ usage: OpenAICompatibleChatUsage?) -> LanguageModelV4Usage)?

    public init(
        provider: String,
        headers: @escaping @Sendable () throws -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) throws -> String,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        metadataExtractor: OpenAICompatibleMetadataExtractor? = nil,
        supportsStructuredOutputs: Bool = false,
        supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])? = nil,
        transformRequestBody: (@Sendable (_ body: [String: JSONValue]) -> [String: JSONValue])? = nil,
        convertUsage: (@Sendable (_ usage: OpenAICompatibleChatUsage?) -> LanguageModelV4Usage)? = nil
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
    }
}

public final class OpenAICompatibleChatLanguageModel: LanguageModelV4 {
    public let specificationVersion = "v4"
    private let modelIdentifier: OpenAICompatibleChatModelId
    private let config: OpenAICompatibleChatConfig
    private let providerOptionsName: String

    public init(modelId: OpenAICompatibleChatModelId, config: OpenAICompatibleChatConfig) {
        self.modelIdentifier = modelId
        self.config = config
        self.providerOptionsName = config.provider.split(separator: ".").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            try await config.supportedUrls?() ?? [:]
        }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let transformedBody = transformRequestBody(prepared.body)
        let defaultHeaders = try config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: try config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
            headers: headers,
            body: JSONValue.object(transformedBody),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAICompatibleChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let choice = response.value.choices.first else {
            throw InvalidResponseDataError(data: response.rawValue, message: "Response did not contain any choices.")
        }

        var content = choice.message.content?.parts ?? []

        let reasoning = choice.message.reasoningContent
            ?? choice.message.reasoning
        if let reasoning, !reasoning.isEmpty {
            content.append(.reasoning(LanguageModelV4Reasoning(text: reasoning)))
        }

        if let toolCalls = choice.message.toolCalls {
            for toolCall in toolCalls {
                let function = toolCall.function
                let toolCallId = toolCall.id.flatMap { $0.isEmpty ? nil : $0 } ?? generateID()
                let thoughtSignature = toolCall.extraContent?.google?.thoughtSignature.flatMap {
                    $0.isEmpty ? nil : $0
                }
                let toolMetadata = thoughtSignature.map {
                        [prepared.metadataKey: ["thoughtSignature": JSONValue.string($0)]]
                    }
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
            unified: mapOpenAICompatibleFinishReason(rawFinishReason),
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

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        if config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }
        let transformedBody = transformRequestBody(body)

        let defaultHeaders = try config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let eventStream = try await postJsonToAPI(
            url: try config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
            headers: headers,
            body: JSONValue.object(transformedBody),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(
                chunkSchema: openAICompatibleChatChunkSchema(
                    errorConfiguration: config.errorConfiguration
                )
            ),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let metadataExtractor = config.metadataExtractor?.createStreamExtractor()
        let metadataKey = prepared.metadataKey

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            let task = Task {
                var finishReason: LanguageModelV4FinishReason?
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
                        typeValidation: .none,
                        emitsEmptyInitialArgumentDelta: false,
                        extractMetadata: {
                            $0.providerMetadata
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
                            continuation.yield(.error(error: .error(error)))
                        case .success(let chunk, let raw):
                            if let metadataExtractor, let json = try? jsonValue(from: raw) {
                                metadataExtractor.processChunk(json)
                            }

                            switch chunk {
                            case .error(let errorData):
                                finishReason = .init(unified: .error, raw: nil)
                                let payload: JSONValue
                                if case .object(let object) = errorData.rawValue, let error = object["error"] { payload = error }
                                else { payload = .string(errorData.message) }
                                continuation.yield(.error(error: .value(payload)))

                            case .data(let data):
                                if isFirstChunk {
                                    let meta = responseMetadata(id: data.id, model: data.model, created: data.created)
                                    if meta.id?.isEmpty == false || meta.modelId?.isEmpty == false || meta.timestamp != nil {
                                        isFirstChunk = false
                                        continuation.yield(.responseMetadata(id: meta.id, modelId: meta.modelId, timestamp: meta.timestamp))
                                    }
                                }

                                if let usageValue = data.usage {
                                    usage = usageValue
                                    usageRaw = extractUsage(from: parseResult.rawJSONValue)
                                }

                                guard let choice = data.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = LanguageModelV4FinishReason(
                                        unified: mapOpenAICompatibleFinishReason(finish),
                                        raw: finish
                                    )
                                }

                                if let delta = choice.delta {
                                    var pieces: [LanguageModelV4Content] = []
                                    if let reasoning = delta.reasoningContent ?? delta.reasoning, !reasoning.isEmpty {
                                        pieces.append(.reasoning(.init(text: reasoning)))
                                    }
                                    pieces += delta.content?.parts ?? []
                                    for piece in pieces {
                                        switch piece {
                                        case .reasoning(let reasoning):
                                            if isActiveText {
                                                continuation.yield(.textEnd(id: "txt-0", providerMetadata: nil))
                                                isActiveText = false
                                            }
                                            if !isActiveReasoning {
                                                continuation.yield(.reasoningStart(id: "reasoning-0", providerMetadata: nil))
                                                isActiveReasoning = true
                                            }
                                            continuation.yield(.reasoningDelta(id: "reasoning-0", delta: reasoning.text, providerMetadata: nil))
                                        case .text(let text):
                                            if isActiveReasoning {
                                                continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                                                isActiveReasoning = false
                                            }
                                            if !isActiveText {
                                                continuation.yield(.textStart(id: "txt-0", providerMetadata: nil))
                                                isActiveText = true
                                            }
                                            continuation.yield(.textDelta(id: "txt-0", delta: text.text, providerMetadata: nil))
                                        default: break
                                        }
                                    }

                                    if let toolCallDeltas = delta.toolCalls {
                                        if isActiveReasoning {
                                            isActiveReasoning = false
                                            continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                                        }
                                        for toolCallDelta in toolCallDeltas {
                                            try processToolCallDelta(
                                                toolCallDelta,
                                                metadataKey: metadataKey,
                                                pending: &pendingToolCalls,
                                                forwardedIndices: &forwardedToolCallIndices,
                                                tracker: toolCallTracker
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if isActiveReasoning {
                        continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                    }
                    if isActiveText {
                        continuation.yield(.textEnd(
                            id: "txt-0",
                            providerMetadata: nil
                        ))
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

                    var providerMetadata: SharedV4ProviderMetadata = [metadataKey: [:]]
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
                    providerMetadata[metadataKey] = providerEntry

                    if finishReason == nil {
                        finishReason = .init(unified: .error)
                        continuation.yield(.error(error: .error(InvalidResponseDataError(data: nil, message: "Response stream ended without a finish reason."))))
                    }
                    continuation.yield(.finish(
                        finishReason: finishReason ?? .init(unified: .error),
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

    private func prepareRequest(options: LanguageModelV4CallOptions) async throws -> PreparedRequest {
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
        if let warning = openAICompatibleDeprecatedProviderOptionsWarning(
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
        camelCaseProviderOptions = try await parseProviderOptions(
            provider: camelCaseProviderOptionsName,
            providerOptions: options.providerOptions,
            schema: openAICompatibleProviderOptionsSchema
        ) ?? OpenAICompatibleChatProviderOptions()

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

        var providerSpecificRaw = options.providerOptions?[providerOptionsName] ?? [:]
        providerSpecificRaw.merge(options.providerOptions?[camelCaseProviderOptionsName] ?? [:]) { _, new in new }

        let forwardedOptions = providerSpecificRaw.filter { key, _ in
            !["user", "reasoningEffort", "textVerbosity", "strictJsonSchema"].contains(key)
        }

        let messages = try convertToOpenAICompatibleChatMessages(prompt: options.prompt)

        // Warning only if schema is present but structuredOutputs not supported
        if case let .json(schema, _, _) = options.responseFormat,
           schema != nil,
           !config.supportsStructuredOutputs {
            warnings.append(.unsupported(
                feature: "responseFormat",
                details: "JSON response format schema is only supported with structuredOutputs"
            ))
        }

        let preparedTools = OpenAICompatibleToolPreparer.prepare(tools: options.tools, toolChoice: options.toolChoice)
        warnings.append(contentsOf: preparedTools.warnings)

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue)
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

        for (key, value) in forwardedOptions {
            body[key] = value
        }

        let topLevelReasoning: String?
        switch options.reasoning {
        case .some(.minimal), .some(.low), .some(.medium), .some(.high), .some(.xhigh), .some(.max):
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

        body["messages"] = .array(messages)

        if let tools = preparedTools.tools {
            body["tools"] = tools
        }
        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = toolChoice
        }

        let metadataKey = openAICompatibleProviderOptionsKey(
                rawName: providerOptionsName,
                providerOptions: options.providerOptions
            )

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
                    text: max(0, completionTokens - reasoningTokens),
                    reasoning: reasoningTokens
                ),
                raw: raw == .null ? nil : raw
            )
        } else {
            converted = LanguageModelV4Usage()
        }

        return converted
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
        tracker: StreamingToolCallTracker
    ) throws {
        let thoughtSignature = delta.extraContent?.google?.thoughtSignature.flatMap {
            $0.isEmpty ? nil : $0
        }
        let providerMetadata = thoughtSignature.map {
                [metadataKey: ["thoughtSignature": JSONValue.string($0)]]
            }

        guard let index = delta.index else {
            try tracker.processDelta(StreamingToolCallDelta(
                id: delta.id,
                function: StreamingToolCallFunctionDelta(
                    name: delta.function.name,
                    arguments: delta.function.arguments
                ),
                providerMetadata: providerMetadata
            ))
            return
        }

        if forwardedIndices.contains(index) {
            try tracker.processDelta(StreamingToolCallDelta(
                index: index,
                id: delta.id,
                function: StreamingToolCallFunctionDelta(
                    name: delta.function.name,
                    arguments: delta.function.arguments
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
        if let arguments = delta.function.arguments {
            state.arguments += arguments
        }

        guard let name = delta.function.name else {
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

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let openAICompatibleChatResponseSchema = FlexibleSchema(
    Schema<OpenAICompatibleChatResponse>.codable(
        OpenAICompatibleChatResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private func openAICompatibleChatChunkSchema(
    errorConfiguration: OpenAICompatibleErrorConfiguration
) -> FlexibleSchema<OpenAICompatibleChatStreamChunk> {
    createOpenAICompatibleStreamSchema(
        dataType: OpenAICompatibleChatStreamData.self,
        errorConfiguration: errorConfiguration,
        transformData: OpenAICompatibleChatStreamChunk.data,
        transformError: OpenAICompatibleChatStreamChunk.error
    )
}

private struct OpenAICompatibleChatExtraContent: Codable, Sendable {
    struct Google: Codable, Sendable {
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

private enum OpenAICompatibleChatContent: Codable, Sendable {
    case text(String)
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { self = .text(text); return }
        let values = try container.decode([JSONValue].self)
        for value in values {
            guard case .object(let object) = value, case .string = object["type"] else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected content part with a string type")
            }
        }
        self = .array(values)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .array(let values): try container.encode(values)
        }
    }
    var parts: [LanguageModelV4Content] {
        switch self {
        case .text(let text): return text.isEmpty ? [] : [.text(.init(text: text))]
        case .array(let values):
            return values.compactMap { value in
                guard case .object(let object) = value else { return nil }
                if object["type"] == "text", case .string(let text) = object["text"], !text.isEmpty {
                    return .text(.init(text: text))
                }
                if object["type"] == "thinking", case .array(let chunks) = object["thinking"] {
                    let text = chunks.compactMap { chunk -> String? in
                        guard case .object(let item) = chunk, item["type"] == "text", case .string(let text) = item["text"] else { return nil }
                        return text
                    }.joined()
                    if !text.isEmpty { return .reasoning(.init(text: text)) }
                }
                return nil
            }
        }
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
                let function: ToolFunction
                let extraContent: OpenAICompatibleChatExtraContent?

                private enum CodingKeys: String, CodingKey {
                    case id
                    case function
                    case extraContent = "extra_content"
                }
            }

            let role: Role?
            let content: OpenAICompatibleChatContent?
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

private enum OpenAICompatibleChatStreamChunk: Sendable {
    case data(OpenAICompatibleChatStreamData)
    case error(OpenAICompatibleParsedStreamError)
}

private struct OpenAICompatibleChatStreamData: Codable, Sendable {
    struct Choice: Codable, Sendable {
        struct Delta: Codable, Sendable {
            enum Role: String, Codable, Sendable {
                case assistant
                case empty = ""
            }

            let role: Role?
            let content: OpenAICompatibleChatContent?
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

private struct OpenAICompatibleChatChunkToolCallDelta: Codable, Sendable {
    struct ToolFunction: Codable, Sendable {
        let name: String?
        let arguments: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case arguments
        }
    }

    let index: Int?
    let id: String?
    let function: ToolFunction
    let extraContent: OpenAICompatibleChatExtraContent?

    private enum CodingKeys: String, CodingKey {
        case index
        case id
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
