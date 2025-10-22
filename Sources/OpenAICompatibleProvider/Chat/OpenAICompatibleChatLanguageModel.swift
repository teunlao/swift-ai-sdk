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

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        metadataExtractor: OpenAICompatibleMetadataExtractor? = nil,
        supportsStructuredOutputs: Bool = false,
        supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])? = nil
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
    }
}

public final class OpenAICompatibleChatLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleChatModelId
    private let config: OpenAICompatibleChatConfig
    private let providerOptionsName: String

    public init(modelId: OpenAICompatibleChatModelId, config: OpenAICompatibleChatConfig) {
        self.modelIdentifier = modelId
        self.config = config
        self.providerOptionsName = config.provider.split(separator: ".").first.map(String.init) ?? ""
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            try await config.supportedUrls?() ?? [:]
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAICompatibleChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let choice = response.value.choices.first else {
            throw APICallError(
                message: "OpenAI-compatible response did not include choices.",
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
                requestBodyValues: prepared.body
            )
        }

        var content: [LanguageModelV3Content] = []

        if let text = choice.message.content, !text.isEmpty {
            content.append(.text(LanguageModelV3Text(text: text)))
        }

        // Note: In doGenerate, only reasoning_content is used (not reasoning field)
        // The reasoning field is only used in streaming
        if let reasoning = choice.message.reasoningContent, !reasoning.isEmpty {
            content.append(.reasoning(LanguageModelV3Reasoning(text: reasoning)))
        }

        if let toolCalls = choice.message.toolCalls {
            for toolCall in toolCalls {
                guard let function = toolCall.function, let name = function.name else { continue }
                let arguments = function.arguments ?? "{}"
                let toolCallId = toolCall.id ?? generateID()
                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: name,
                    input: arguments,
                    providerExecuted: nil,
                    providerMetadata: nil
                )))
            }
        }

        let usage = mapUsage(response.value.usage)
        let finishReason = mapOpenAICompatibleFinishReason(choice.finishReason)
        let metadata = responseMetadata(id: response.value.id, model: response.value.model, created: response.value.created)

        let rawJSON = try decodeJSONValue(from: response.rawValue)
        let extractedMetadata = try await config.metadataExtractor?.extractMetadata(parsedBody: rawJSON)
        let providerMetadata = makeProviderMetadata(
            usage: response.value.usage,
            extractedMetadata: extractedMetadata
        )

        return LanguageModelV3GenerateResult(
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
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        if config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }

        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let eventStream = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/chat/completions")),
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAICompatibleChatChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let metadataExtractor = config.metadataExtractor?.createStreamExtractor()
        let providerKey = providerOptionsName

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var isFirstChunk = true
                var isActiveText = false
                var isActiveReasoning = false
                var toolCalls: [Int: ToolCallState] = [:]
                var providerValues: [String: JSONValue] = [:]

                do {
                    for try await parseResult in eventStream.value {
                        if options.includeRawChunks == true, let rawJSON = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: rawJSON))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .error
                            continuation.yield(.error(error: .string(String(describing: error))))
                        case .success(let chunk, let raw):
                            if let metadataExtractor, let json = try? jsonValue(from: raw) {
                                metadataExtractor.processChunk(json)
                            }

                            switch chunk {
                            case .error(let errorData):
                                finishReason = .error
                                if let encoded = try? JSONEncoder().encodeToJSONValue(errorData) {
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
                                    usage = mapUsage(usageValue)
                                    if let accepted = usageValue.completionTokensDetails?.acceptedPredictionTokens {
                                        providerValues["acceptedPredictionTokens"] = .number(Double(accepted))
                                    }
                                    if let rejected = usageValue.completionTokensDetails?.rejectedPredictionTokens {
                                        providerValues["rejectedPredictionTokens"] = .number(Double(rejected))
                                    }
                                }

                                guard let choice = data.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = mapOpenAICompatibleFinishReason(finish)
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
                                        if !isActiveText {
                                            isActiveText = true
                                            continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                        }
                                        continuation.yield(.textDelta(id: "0", delta: text, providerMetadata: nil))
                                    }

                                    if let toolCallDeltas = delta.toolCalls {
                                        try handleToolCallDeltas(toolCallDeltas, toolCalls: &toolCalls, continuation: continuation)
                                    }
                                }
                            }
                        }
                    }

                    if isActiveText {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                    }
                    if isActiveReasoning {
                        continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                    }

                    var providerMetadata = metadataExtractor?.buildMetadata() ?? [:]
                    if !providerValues.isEmpty {
                        var entry = providerMetadata[providerKey] ?? [:]
                        entry.merge(providerValues) { _, new in new }
                        providerMetadata[providerKey] = entry
                    }
                    let finalMetadata = providerMetadata.isEmpty ? nil : providerMetadata

                    continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: finalMetadata))
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
        let warnings: [LanguageModelV3CallWarning]
    }

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [LanguageModelV3CallWarning] = []

        if options.topK != nil {
            warnings.append(.unsupportedSetting(setting: "topK", details: nil))
        }

        let baseOptions = try await parseProviderOptions(
            provider: "openai-compatible",
            providerOptions: options.providerOptions,
            schema: openAICompatibleProviderOptionsSchema
        ) ?? OpenAICompatibleChatProviderOptions()

        let providerSpecificOptions = try await parseProviderOptions(
            provider: providerOptionsName,
            providerOptions: options.providerOptions,
            schema: openAICompatibleProviderOptionsSchema
        ) ?? OpenAICompatibleChatProviderOptions()

        var mergedOptions = baseOptions
        if let user = providerSpecificOptions.user {
            mergedOptions.user = user
        }
        if let reasoningEffort = providerSpecificOptions.reasoningEffort {
            mergedOptions.reasoningEffort = reasoningEffort
        }
        if let textVerbosity = providerSpecificOptions.textVerbosity {
            mergedOptions.textVerbosity = textVerbosity
        }

        let providerSpecificRaw = options.providerOptions?[providerOptionsName] ?? [:]
        let forwardedOptions = providerSpecificRaw.filter { key, _ in
            !["user", "reasoningEffort", "textVerbosity"].contains(key)
        }

        let messages = try convertToOpenAICompatibleChatMessages(prompt: options.prompt)

        // Warning only if schema is present but structuredOutputs not supported
        if case let .json(schema, _, _) = options.responseFormat,
           schema != nil,
           !config.supportsStructuredOutputs {
            warnings.append(.unsupportedSetting(
                setting: "responseFormat",
                details: "JSON response format schema is only supported with structuredOutputs"
            ))
        }

        let preparedTools = OpenAICompatibleToolPreparer.prepare(
            tools: options.tools,
            toolChoice: options.toolChoice
        )
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
                    var payload: [String: JSONValue] = [
                        "schema": schema,
                        "name": .string(name ?? "response")
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

        if let reasoning = mergedOptions.reasoningEffort {
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

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func mapUsage(_ usage: OpenAICompatibleUsage?) -> LanguageModelV3Usage {
        guard let usage else { return LanguageModelV3Usage() }

        return LanguageModelV3Usage(
            inputTokens: usage.promptTokens,
            outputTokens: usage.completionTokens,
            totalTokens: usage.totalTokens,
            reasoningTokens: usage.completionTokensDetails?.reasoningTokens,
            cachedInputTokens: usage.promptTokensDetails?.cachedTokens
        )
    }

    private func makeProviderMetadata(
        usage: OpenAICompatibleUsage?,
        extractedMetadata: SharedV3ProviderMetadata?
    ) -> SharedV3ProviderMetadata? {
        var metadata = extractedMetadata ?? [:]
        var providerEntry = metadata[providerOptionsName] ?? [:]

        if let accepted = usage?.completionTokensDetails?.acceptedPredictionTokens {
            providerEntry["acceptedPredictionTokens"] = .number(Double(accepted))
        }
        if let rejected = usage?.completionTokensDetails?.rejectedPredictionTokens {
            providerEntry["rejectedPredictionTokens"] = .number(Double(rejected))
        }

        if !providerEntry.isEmpty {
            metadata[providerOptionsName] = providerEntry
        }

        return metadata.isEmpty ? nil : metadata
    }

    private func responseMetadata(id: String?, model: String?, created: Double?) -> (id: String?, modelId: String?, timestamp: Date?) {
        let timestamp = created.map { Date(timeIntervalSince1970: $0) }
        return (id, model, timestamp)
    }

    private func decodeJSONValue(from raw: Any?) throws -> JSONValue {
        guard let raw else { return .null }
        return try jsonValue(from: raw)
    }

    private func handleToolCallDeltas(
        _ deltas: [OpenAICompatibleChatChunkToolCallDelta],
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

                var state = ToolCallState(toolCallId: id, toolName: name, arguments: delta.function?.arguments ?? "", hasFinished: false)
                continuation.yield(.toolInputStart(id: id, toolName: name, providerMetadata: nil, providerExecuted: nil))

                if !state.arguments.isEmpty {
                    continuation.yield(.toolInputDelta(id: id, delta: state.arguments, providerMetadata: nil))
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
            if state.hasFinished { continue }

            if let name = delta.function?.name, !name.isEmpty {
                state.toolName = name
            }

            if let argumentDelta = delta.function?.arguments, !argumentDelta.isEmpty {
                state.arguments += argumentDelta
                continuation.yield(.toolInputDelta(id: state.toolCallId, delta: argumentDelta, providerMetadata: nil))
            }

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

private struct OpenAICompatibleChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            struct ToolCall: Codable {
                struct ToolFunction: Codable {
                    let name: String?
                    let arguments: String?

                    private enum CodingKeys: String, CodingKey {
                        case name
                        case arguments
                    }
                }

                let id: String?
                let type: String?
                let function: ToolFunction?

                private enum CodingKeys: String, CodingKey {
                    case id
                    case type
                    case function
                }
            }

            let content: String?
            let reasoningContent: String?
            let reasoning: String?
            let toolCalls: [ToolCall]?

            private enum CodingKeys: String, CodingKey {
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
    let usage: OpenAICompatibleUsage?

    private enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case usage
    }
}

private struct OpenAICompatibleUsage: Codable {
    struct PromptTokensDetails: Codable {
        let cachedTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    struct CompletionTokensDetails: Codable {
        let reasoningTokens: Int?
        let acceptedPredictionTokens: Int?
        let rejectedPredictionTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
            case acceptedPredictionTokens = "accepted_prediction_tokens"
            case rejectedPredictionTokens = "rejected_prediction_tokens"
        }
    }

    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let promptTokensDetails: PromptTokensDetails?
    let completionTokensDetails: CompletionTokensDetails?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
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
            let content: String?
            let reasoningContent: String?
            let reasoning: String?
            let toolCalls: [OpenAICompatibleChatChunkToolCallDelta]?

            private enum CodingKeys: String, CodingKey {
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
    let usage: OpenAICompatibleUsage?

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

    let index: Int
    let id: String?
    let type: String?
    let function: ToolFunction?

    private enum CodingKeys: String, CodingKey {
        case index
        case id
        case type
        case function
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
