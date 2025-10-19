import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GroqChatLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        struct RequestOptions {
            let modelId: GroqChatModelId
            let path: String
        }

        let provider: String
        let url: @Sendable (RequestOptions) -> String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let generateId: @Sendable () -> String
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [LanguageModelV3CallWarning]
    }

    private let modelIdentifier: GroqChatModelId
    private let config: Config

    private let imageRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
    }()

    init(modelId: GroqChatModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public let specificationVersion: String = "v3"
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            ["image/*": [imageRegex]]
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options, stream: false)

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/chat/completions")),
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: groqFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: groqChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let choice = response.value.choices.first
        var content: [LanguageModelV3Content] = []

        if let text = choice?.message.content, !text.isEmpty {
            content.append(.text(LanguageModelV3Text(text: text)))
        }

        if let reasoning = choice?.message.reasoning, !reasoning.isEmpty {
            content.append(.reasoning(LanguageModelV3Reasoning(text: reasoning)))
        }

        if let toolCalls = choice?.message.toolCalls {
            for call in toolCalls {
                content.append(.toolCall(
                    LanguageModelV3ToolCall(
                        toolCallId: call.id ?? config.generateId(),
                        toolName: call.function.name,
                        input: call.function.arguments
                    )
                ))
            }
        }

        let usage = LanguageModelV3Usage(
            inputTokens: response.value.usage?.promptTokens,
            outputTokens: response.value.usage?.completionTokens,
            totalTokens: response.value.usage?.totalTokens,
            reasoningTokens: nil,
            cachedInputTokens: response.value.usage?.promptTokensDetails?.cachedTokens
        )

        let metadata = groqResponseMetadata(
            id: response.value.id,
            model: response.value.model,
            created: response.value.created
        )

        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: mapGroqFinishReason(choice?.finishReason),
            usage: usage,
            providerMetadata: nil,
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
        let prepared = try await prepareRequest(options: options, stream: true)

        let streamResponse = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/chat/completions")),
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: groqFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: groqChatStreamSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var toolCalls: [GroqStreamingToolCall] = []
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var isFirstChunk = true
                var isActiveText = false
                var isActiveReasoning = false

                do {
                    for try await parseResult in streamResponse.value {
                        if options.includeRawChunks == true, let raw = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .error
                            continuation.yield(.error(error: .string(String(describing: error))))
                            continue
                        case .success(let event, _):
                            switch event {
                            case .error(let errorData):
                                finishReason = .error
                                if let json = try? JSONEncoder().encodeToJSONValue(errorData) {
                                    continuation.yield(.error(error: json))
                                } else {
                                    continuation.yield(.error(error: .string(errorData.error.message)))
                                }
                            case .chunk(let chunk):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let metadata = groqResponseMetadata(id: chunk.id, model: chunk.model, created: chunk.created)
                                    continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                                }

                                if let usageMetadata = chunk.xGroq?.usage {
                                    usage = LanguageModelV3Usage(
                                        inputTokens: usageMetadata.promptTokens,
                                        outputTokens: usageMetadata.completionTokens,
                                        totalTokens: usageMetadata.totalTokens,
                                        reasoningTokens: nil,
                                        cachedInputTokens: usageMetadata.promptTokensDetails?.cachedTokens
                                    )
                                }

                                guard let choice = chunk.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = mapGroqFinishReason(finish)
                                }

                                guard let delta = choice.delta else { continue }

                                if let text = delta.content, !text.isEmpty {
                                    if !isActiveText {
                                        isActiveText = true
                                        continuation.yield(.textStart(id: "txt-0", providerMetadata: nil))
                                    }
                                    continuation.yield(.textDelta(id: "txt-0", delta: text, providerMetadata: nil))
                                }

                                if let reasoning = delta.reasoning, !reasoning.isEmpty {
                                    if !isActiveReasoning {
                                        isActiveReasoning = true
                                        continuation.yield(.reasoningStart(id: "reasoning-0", providerMetadata: nil))
                                    }
                                    continuation.yield(.reasoningDelta(id: "reasoning-0", delta: reasoning, providerMetadata: nil))
                                }

                                if let callDeltas = delta.toolCalls {
                                    try handleToolCallDeltas(
                                        callDeltas,
                                        toolCalls: &toolCalls,
                                        continuation: continuation
                                    )
                                }
                            }
                        }
                    }

                    if isActiveReasoning {
                        continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                    }

                    if isActiveText {
                        continuation.yield(.textEnd(id: "txt-0", providerMetadata: nil))
                    }

                    continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3StreamResponseInfo(headers: streamResponse.responseHeaders)
        )
    }

    // MARK: - Preparation

    private func prepareRequest(options: LanguageModelV3CallOptions, stream: Bool) async throws -> PreparedRequest {
        var warnings: [LanguageModelV3CallWarning] = []

        let groqOptions = try await parseProviderOptions(
            provider: "groq",
            providerOptions: options.providerOptions,
            schema: groqProviderOptionsSchema
        )

        let structuredOutputs = groqOptions?.structuredOutputs ?? true

        if options.topK != nil {
            warnings.append(.unsupportedSetting(setting: "topK", details: nil))
        }

        if case let .json(schema, _, _)? = options.responseFormat,
           schema != nil,
           structuredOutputs == false {
            warnings.append(
                .unsupportedSetting(
                    setting: "responseFormat",
                    details: "JSON response format schema is only supported with structuredOutputs"
                )
            )
        }

        let preparedTools = prepareGroqTools(
            tools: options.tools,
            toolChoice: options.toolChoice,
            modelId: modelIdentifier
        )
        warnings.append(contentsOf: preparedTools.toolWarnings)

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(try convertToGroqChatMessages(options.prompt))
        ]

        if let value = options.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if let value = options.temperature { body["temperature"] = .number(value) }
        if let value = options.topP { body["top_p"] = .number(value) }
        if let value = options.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if let value = options.presencePenalty { body["presence_penalty"] = .number(value) }
        if let value = options.seed { body["seed"] = .number(Double(value)) }
        if let value = options.stopSequences, !value.isEmpty {
            body["stop"] = .array(value.map(JSONValue.string))
        }

        if let groqOptions {
            if let user = groqOptions.user {
                body["user"] = .string(user)
            }
            if let parallel = groqOptions.parallelToolCalls {
                body["parallel_tool_calls"] = .bool(parallel)
            }
            if let reasoningFormat = groqOptions.reasoningFormat {
                body["reasoning_format"] = .string(reasoningFormat.rawValue)
            }
            if let reasoningEffort = groqOptions.reasoningEffort {
                body["reasoning_effort"] = .string(reasoningEffort)
            }
            if let serviceTier = groqOptions.serviceTier {
                body["service_tier"] = .string(serviceTier.rawValue)
            }
        }

        if let responseFormat = options.responseFormat {
            switch responseFormat {
            case .text:
                break
            case let .json(schema, name, description):
                if structuredOutputs, let schema {
                    var schemaObject: [String: JSONValue] = ["schema": schema, "name": .string(name ?? "response")]
                    if let description = description {
                        schemaObject["description"] = .string(description)
                    }
                    body["response_format"] = .object([
                        "type": .string("json_schema"),
                        "json_schema": .object(schemaObject)
                    ])
                } else {
                    body["response_format"] = .object([
                        "type": .string("json_object")
                    ])
                }
            }
        }

        if let tools = preparedTools.tools {
            body["tools"] = .array(tools)
        }
        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = toolChoice
        }

        if stream {
            body["stream"] = .bool(true)
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func handleToolCallDeltas(
        _ deltas: [GroqChatChunk.Choice.Delta.ToolCallDelta],
        toolCalls: inout [GroqStreamingToolCall],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) throws {
        for toolCallDelta in deltas {
            let index = toolCallDelta.index
            if index >= toolCalls.count {
                toolCalls.append(contentsOf: Array(repeating: GroqStreamingToolCall.empty, count: index - toolCalls.count + 1))
            }

            let current = toolCalls[index]

            if current.isEmpty {
                guard toolCallDelta.type == nil || toolCallDelta.type == "function" else {
                    throw InvalidResponseDataError(data: toolCallDelta, message: "Expected 'function' type.")
                }

                guard let id = toolCallDelta.id else {
                    throw InvalidResponseDataError(data: toolCallDelta, message: "Expected 'id' to be a string.")
                }

                guard let name = toolCallDelta.function?.name else {
                    throw InvalidResponseDataError(data: toolCallDelta, message: "Expected function name.")
                }

                continuation.yield(.toolInputStart(id: id, toolName: name, providerMetadata: nil, providerExecuted: nil))

                var newCall = GroqStreamingToolCall(id: id, name: name, arguments: "")
                if let arguments = toolCallDelta.function?.arguments {
                    newCall.arguments = arguments
                    if !arguments.isEmpty {
                        continuation.yield(.toolInputDelta(id: id, delta: arguments, providerMetadata: nil))
                    }
                }
                toolCalls[index] = newCall

                if isParsableJson(newCall.arguments) {
                    continuation.yield(.toolInputEnd(id: id, providerMetadata: nil))
                    continuation.yield(.toolCall(LanguageModelV3ToolCall(toolCallId: id, toolName: name, input: newCall.arguments)))
                    toolCalls[index].hasFinished = true
                }
            } else {
                guard !current.hasFinished else { continue }

                var updated = current

                if let name = toolCallDelta.function?.name, !name.isEmpty {
                    updated.name = name
                }

                let argumentDelta = toolCallDelta.function?.arguments ?? ""
                if !argumentDelta.isEmpty {
                    updated.arguments += argumentDelta
                }

                continuation.yield(.toolInputDelta(id: updated.id, delta: argumentDelta, providerMetadata: nil))

                if isParsableJson(updated.arguments) {
                    continuation.yield(.toolInputEnd(id: updated.id, providerMetadata: nil))
                    continuation.yield(.toolCall(LanguageModelV3ToolCall(toolCallId: updated.id, toolName: updated.name, input: updated.arguments)))
                    updated.hasFinished = true
                }

                toolCalls[index] = updated
            }
        }
    }
}

// MARK: - Streaming Helpers

private struct GroqStreamingToolCall {
    var id: String
    var name: String
    var arguments: String
    var hasFinished: Bool

    init(id: String = "", name: String = "", arguments: String = "", hasFinished: Bool = false) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.hasFinished = hasFinished
    }

    var isEmpty: Bool { id.isEmpty && name.isEmpty }

    static let empty = GroqStreamingToolCall()
}

private struct GroqChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String?
            let reasoning: String?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoning
                case toolCalls = "tool_calls"
            }
        }

        struct ToolCall: Codable {
            let id: String?
            let function: Function

            struct Function: Codable {
                let name: String
                let arguments: String
            }

            enum CodingKeys: String, CodingKey {
                case id
                case function
            }
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Codable {
        struct PromptTokensDetails: Codable {
            let cachedTokens: Int?

            enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }

        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        let promptTokensDetails: PromptTokensDetails?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptTokensDetails = "prompt_tokens_details"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: Usage?
}

private struct GroqChatChunk: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            struct ToolCallDelta: Codable {
                struct Function: Codable {
                    let name: String?
                    var arguments: String?
                }

                let index: Int
                let id: String?
                let type: String?
                let function: Function?

                enum CodingKeys: String, CodingKey {
                    case index
                    case id
                    case type
                    case function
                }
            }

            let content: String?
            let reasoning: String?
            let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoning
                case toolCalls = "tool_calls"
            }
        }

        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Codable {
        struct PromptTokensDetails: Codable {
            let cachedTokens: Int?

            enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }

        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        let promptTokensDetails: PromptTokensDetails?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptTokensDetails = "prompt_tokens_details"
        }
    }

    struct XGroq: Codable {
        let usage: Usage?
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let xGroq: XGroq?

    enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case xGroq = "x_groq"
    }
}

private enum GroqChatStreamEvent: Codable {
    case chunk(GroqChatChunk)
    case error(GroqErrorData)

    init(from decoder: Decoder) throws {
        if let error = try? GroqErrorData(from: decoder) {
            self = .error(error)
        } else {
            let chunk = try GroqChatChunk(from: decoder)
            self = .chunk(chunk)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .chunk(let chunk):
            try chunk.encode(to: encoder)
        case .error(let error):
            try error.encode(to: encoder)
        }
    }
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

private let groqChatResponseSchema = FlexibleSchema(
    Schema<GroqChatResponse>.codable(
        GroqChatResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let groqChatStreamSchema = FlexibleSchema(
    Schema<GroqChatStreamEvent>.codable(
        GroqChatStreamEvent.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private extension ParseJSONResult where Output == GroqChatStreamEvent {
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
