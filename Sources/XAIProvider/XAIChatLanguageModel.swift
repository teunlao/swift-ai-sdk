import Foundation
import AISDKProvider
import AISDKProviderUtils

/// xAI chat language model implementation.
/// Mirrors `packages/xai/src/xai-chat-language-model.ts`.
public final class XAIChatLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let generateId: @Sendable () -> String
        let fetch: FetchFunction?
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
        let messages: XAIChatPrompt
    }

    private let modelIdentifier: XAIChatModelId
    private let config: Config

    private let httpRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
    }()

    init(modelId: XAIChatModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public let specificationVersion: String = "v3"

    public var provider: String { config.provider }

    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            ["image/*": [httpRegex]]
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)

        let url = "\(config.baseURL)/chat/completions"

        let response = try await postJsonToAPI(
            url: url,
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: xaiChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        if let errorMessage = response.value.error {
            let responseBody = stringifyJSON(response.rawValue)
            throw APICallError(
                message: errorMessage,
                url: url,
                requestBodyValues: prepared.body,
                statusCode: 200,
                responseHeaders: response.responseHeaders,
                responseBody: responseBody,
                isRetryable: response.value.code == "The service is currently unavailable"
            )
        }

        var contents: [LanguageModelV3Content] = []
        let lastMessage = prepared.messages.last
        if let choice = response.value.choices?.first {
            if let text = choice.message.content, !text.isEmpty {
                let shouldEmit = !(lastMessage?.role == .assistant && lastMessage?.assistantContent == text)
                if shouldEmit {
                    contents.append(.text(LanguageModelV3Text(text: text)))
                }
            }

            if let reasoning = choice.message.reasoningContent, !reasoning.isEmpty {
                contents.append(.reasoning(LanguageModelV3Reasoning(text: reasoning)))
            }

            if let toolCalls = choice.message.toolCalls {
                for call in toolCalls {
                    contents.append(.toolCall(
                        LanguageModelV3ToolCall(
                            toolCallId: call.id,
                            toolName: call.function.name,
                            input: call.function.arguments
                        )
                    ))
                }
            }
        }

        if let citations = response.value.citations {
            for url in citations {
                contents.append(.source(.url(id: config.generateId(), url: url, title: nil, providerMetadata: nil)))
            }
        }

        let usage = response.value.usage.map(convertXaiChatUsage) ?? defaultXaiChatUsage()
        let rawFinishReason = response.value.choices?.first?.finishReason
        let finishReason = LanguageModelV3FinishReason(
            unified: mapXaiFinishReason(rawFinishReason),
            raw: rawFinishReason
        )

        let metadata = xaiResponseMetadata(
            id: response.value.id,
            model: response.value.model,
            created: response.value.created
        )

        return LanguageModelV3GenerateResult(
            content: contents,
            finishReason: finishReason,
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
        let prepared = try await prepareRequest(options: options)

        var streamBody = prepared.body
        streamBody["stream"] = .bool(true)
        streamBody["stream_options"] = .object([
            "include_usage": .bool(true)
        ])

        let requestBody = streamBody
        let url = "\(config.baseURL)/chat/completions"

        let streamResponse = try await postJsonToAPI(
            url: url,
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(requestBody),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: { input in
                let headers = extractResponseHeaders(from: input.response.httpResponse)
                let contentType = headers["content-type"] ?? ""

                if contentType.contains("application/json") {
                    let data = try await input.response.body.collectData()
                    let bodyText = String(data: data, encoding: .utf8) ?? ""

                    let parsedError = await safeParseJSON(ParseJSONWithSchemaOptions(text: bodyText, schema: xaiStreamErrorSchema))
                    switch parsedError {
                    case .success(let value, _):
                        throw APICallError(
                            message: value.error,
                            url: url,
                            requestBodyValues: requestBody,
                            statusCode: 200,
                            responseHeaders: headers,
                            responseBody: bodyText,
                            isRetryable: value.code == "The service is currently unavailable"
                        )
                    case .failure:
                        throw APICallError(
                            message: "Invalid JSON response",
                            url: url,
                            requestBodyValues: requestBody,
                            statusCode: 200,
                            responseHeaders: headers,
                            responseBody: bodyText
                        )
                    }
                }

                return try await createEventSourceResponseHandler(chunkSchema: xaiChatChunkSchema)(input)
            },
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let messages = prepared.messages

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .init(unified: .other, raw: nil)
                var usage: LanguageModelV3Usage? = nil
                var isFirstChunk = true
                var contentBlocks: [String: ContentBlockState] = [:]
                var contentBlockOrder: [String] = []
                var lastReasoningDeltas: [String: String] = [:]
                var activeReasoningBlockId: String? = nil

                do {
                    for try await parseResult in streamResponse.value {
                        if options.includeRawChunks == true, let raw = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            continuation.yield(.error(error: .string(String(describing: error))))
                            continue
                        case .success(let chunk, _):
                            if isFirstChunk {
                                isFirstChunk = false
                                let metadata = xaiResponseMetadata(id: chunk.id, model: chunk.model, created: chunk.created)
                                continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                            }

                            if let citations = chunk.citations {
                                for url in citations {
                                    continuation.yield(.source(.url(id: config.generateId(), url: url, title: nil, providerMetadata: nil)))
                                }
                            }

                            if let usageInfo = chunk.usage {
                                usage = convertXaiChatUsage(usageInfo)
                            }

                            guard let choice = chunk.choices.first else { continue }
                            if let finish = choice.finishReason {
                                finishReason = LanguageModelV3FinishReason(
                                    unified: mapXaiFinishReason(finish),
                                    raw: finish
                                )
                            }

                            guard let delta = choice.delta else { continue }

                            if let text = delta.content, !text.isEmpty {
                                // End active reasoning block when text content arrives.
                                if let activeId = activeReasoningBlockId,
                                   let block = contentBlocks[activeId],
                                   block.ended == false {
                                    continuation.yield(.reasoningEnd(id: activeId, providerMetadata: nil))
                                    contentBlocks[activeId] = block.ending()
                                    activeReasoningBlockId = nil
                                }

                                // Skip if this content duplicates the last assistant message.
                                if messages.last?.role == .assistant && messages.last?.assistantContent == text {
                                    continue
                                }

                                let blockId = "text-\(chunk.id ?? String(choice.index))"
                                if contentBlocks[blockId] == nil {
                                    contentBlocks[blockId] = ContentBlockState(type: .text, ended: false)
                                    contentBlockOrder.append(blockId)
                                    continuation.yield(.textStart(id: blockId, providerMetadata: nil))
                                }

                                continuation.yield(.textDelta(id: blockId, delta: text, providerMetadata: nil))
                            }

                            if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                                let blockId = "reasoning-\(chunk.id ?? String(choice.index))"
                                if lastReasoningDeltas[blockId] != reasoning {
                                    lastReasoningDeltas[blockId] = reasoning
                                    if contentBlocks[blockId] == nil {
                                        contentBlocks[blockId] = ContentBlockState(type: .reasoning, ended: false)
                                        contentBlockOrder.append(blockId)
                                        activeReasoningBlockId = blockId
                                        continuation.yield(.reasoningStart(id: blockId, providerMetadata: nil))
                                    }
                                    continuation.yield(.reasoningDelta(id: blockId, delta: reasoning, providerMetadata: nil))
                                }
                            }

                            if let toolCalls = delta.toolCalls {
                                // End active reasoning block before tool calls start.
                                if let activeId = activeReasoningBlockId,
                                   let block = contentBlocks[activeId],
                                   block.ended == false {
                                    continuation.yield(.reasoningEnd(id: activeId, providerMetadata: nil))
                                    contentBlocks[activeId] = block.ending()
                                    activeReasoningBlockId = nil
                                }

                                for call in toolCalls {
                                    continuation.yield(.toolInputStart(
                                        id: call.id,
                                        toolName: call.function.name,
                                        providerMetadata: nil,
                                        providerExecuted: nil,
                                        dynamic: nil,
                                        title: nil
                                    ))
                                    continuation.yield(.toolInputDelta(id: call.id, delta: call.function.arguments, providerMetadata: nil))
                                    continuation.yield(.toolInputEnd(id: call.id, providerMetadata: nil))
                                    continuation.yield(.toolCall(LanguageModelV3ToolCall(toolCallId: call.id, toolName: call.function.name, input: call.function.arguments)))
                                }
                            }
                        }
                    }

                    for blockId in contentBlockOrder {
                        guard let block = contentBlocks[blockId], block.ended == false else { continue }
                        switch block.type {
                        case .text:
                            continuation.yield(.textEnd(id: blockId, providerMetadata: nil))
                        case .reasoning:
                            continuation.yield(.reasoningEnd(id: blockId, providerMetadata: nil))
                        }
                    }

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: usage ?? defaultXaiChatUsage(),
                        providerMetadata: nil
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: requestBody),
            response: LanguageModelV3StreamResponseInfo(headers: streamResponse.responseHeaders)
        )
    }

    // MARK: - Preparation

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        let providerOptions = try await parseProviderOptions(
            provider: "xai",
            providerOptions: options.providerOptions,
            schema: xaiProviderOptionsSchema
        )

        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }
        if options.frequencyPenalty != nil {
            warnings.append(.unsupported(feature: "frequencyPenalty", details: nil))
        }
        if options.presencePenalty != nil {
            warnings.append(.unsupported(feature: "presencePenalty", details: nil))
        }
        if options.stopSequences != nil {
            warnings.append(.unsupported(feature: "stopSequences", details: nil))
        }

        let conversion = try convertToXAIChatMessages(options.prompt)
        warnings.append(contentsOf: conversion.warnings)

        let preparedTools = prepareXAITools(tools: options.tools, toolChoice: options.toolChoice)
        warnings.append(contentsOf: preparedTools.warnings)

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(conversion.messages.map { $0.toJSON() })
        ]

        if let maxTokens = options.maxOutputTokens {
            body["max_completion_tokens"] = .number(Double(maxTokens))
        }
        if let temperature = options.temperature {
            body["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            body["top_p"] = .number(topP)
        }
        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }
        if let reasoningEffort = providerOptions?.reasoningEffort {
            body["reasoning_effort"] = .string(reasoningEffort.rawValue)
        }
        if let parallelFunctionCalling = providerOptions?.parallelFunctionCalling {
            body["parallel_function_calling"] = .bool(parallelFunctionCalling)
        }

        if let responseFormat = options.responseFormat {
            switch responseFormat {
            case .text:
                break
            case let .json(schema, name, _):
                if let schema {
                    body["response_format"] = .object([
                        "type": .string("json_schema"),
                        "json_schema": .object([
                            "name": .string(name ?? "response"),
                            "schema": schema,
                            "strict": .bool(true)
                        ])
                    ])
                } else {
                    body["response_format"] = .object([
                        "type": .string("json_object")
                    ])
                }
            }
        }

        if let searchParameters = providerOptions?.searchParameters {
            body["search_parameters"] = searchParameters.toJSONValue()
        }

        if let tools = preparedTools.tools {
            body["tools"] = .array(tools)
        }
        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = toolChoice
        }

        return PreparedRequest(body: body, warnings: warnings, messages: conversion.messages)
    }
}

private enum ContentBlockType {
    case text
    case reasoning
}

private struct ContentBlockState {
    let type: ContentBlockType
    let ended: Bool

    func ending() -> Self {
        Self(type: type, ended: true)
    }
}

private func defaultXaiChatUsage() -> LanguageModelV3Usage {
    LanguageModelV3Usage(
        inputTokens: .init(
            total: 0,
            noCache: 0,
            cacheRead: 0,
            cacheWrite: 0
        ),
        outputTokens: .init(
            total: 0,
            text: 0,
            reasoning: 0
        )
    )
}

private func stringifyJSON(_ raw: Any?) -> String? {
    guard let raw else { return nil }

    if raw is NSNull {
        return "null"
    }

    if let string = raw as? String {
        return string
    }

    if JSONSerialization.isValidJSONObject(raw),
       let data = try? JSONSerialization.data(withJSONObject: raw, options: []),
       let string = String(data: data, encoding: .utf8) {
        return string
    }

    return String(describing: raw)
}

private func convertXaiChatUsage(_ usage: XAIChatResponse.Usage) -> LanguageModelV3Usage {
    // Port of `packages/xai/src/convert-xai-chat-usage.ts`
    let cacheReadTokens = usage.promptTokensDetails?.cachedTokens ?? 0
    let reasoningTokens = usage.completionTokensDetails?.reasoningTokens ?? 0
    let promptTokensIncludesCached = cacheReadTokens <= usage.promptTokens

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: promptTokensIncludesCached ? usage.promptTokens : usage.promptTokens + cacheReadTokens,
            noCache: promptTokensIncludesCached ? usage.promptTokens - cacheReadTokens : usage.promptTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: usage.completionTokens + reasoningTokens,
            text: usage.completionTokens,
            reasoning: reasoningTokens
        ),
        raw: try? JSONEncoder().encodeToJSONValue(usage)
    )
}

private func convertXaiChatUsage(_ usage: XAIChatChunk.Usage) -> LanguageModelV3Usage {
    // Port of `packages/xai/src/convert-xai-chat-usage.ts`
    let cacheReadTokens = usage.promptTokensDetails?.cachedTokens ?? 0
    let reasoningTokens = usage.completionTokensDetails?.reasoningTokens ?? 0
    let promptTokensIncludesCached = cacheReadTokens <= usage.promptTokens

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: promptTokensIncludesCached ? usage.promptTokens : usage.promptTokens + cacheReadTokens,
            noCache: promptTokensIncludesCached ? usage.promptTokens - cacheReadTokens : usage.promptTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: usage.completionTokens + reasoningTokens,
            text: usage.completionTokens,
            reasoning: reasoningTokens
        ),
        raw: try? JSONEncoder().encodeToJSONValue(usage)
    )
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}

// MARK: - Response Models

private struct XAIChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            struct ToolCall: Codable {
                struct Function: Codable {
                    let name: String
                    let arguments: String

                    private enum CodingKeys: String, CodingKey {
                        case name
                        case arguments
                    }
                }

                let id: String
                let function: Function

                private enum CodingKeys: String, CodingKey {
                    case id
                    case function
                }
            }

            let content: String?
            let reasoningContent: String?
            let toolCalls: [ToolCall]?

            private enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
        }

        let message: Message
        let index: Int
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case message
            case index
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Codable {
        struct PromptDetails: Codable {
            let textTokens: Int?
            let audioTokens: Int?
            let imageTokens: Int?
            let cachedTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case textTokens = "text_tokens"
                case audioTokens = "audio_tokens"
                case imageTokens = "image_tokens"
                case cachedTokens = "cached_tokens"
            }
        }

        struct CompletionDetails: Codable {
            let reasoningTokens: Int?
            let audioTokens: Int?
            let acceptedPredictionTokens: Int?
            let rejectedPredictionTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
                case audioTokens = "audio_tokens"
                case acceptedPredictionTokens = "accepted_prediction_tokens"
                case rejectedPredictionTokens = "rejected_prediction_tokens"
            }
        }

        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        let promptTokensDetails: PromptDetails?
        let completionTokensDetails: CompletionDetails?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptTokensDetails = "prompt_tokens_details"
            case completionTokensDetails = "completion_tokens_details"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]?
    let object: String?
    let usage: Usage?
    let citations: [String]?
    let code: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case object
        case usage
        case citations
        case code
        case error
    }
}

private struct XAIChatChunk: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            struct ToolCall: Codable {
                struct Function: Codable {
                    let name: String
                    let arguments: String

                    private enum CodingKeys: String, CodingKey {
                        case name
                        case arguments
                    }
                }

                let id: String
                let function: Function

                private enum CodingKeys: String, CodingKey {
                    case id
                    case function
                }
            }

            let role: String?
            let content: String?
            let reasoningContent: String?
            let toolCalls: [ToolCall]?

            private enum CodingKeys: String, CodingKey {
                case role
                case content
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
        }

        let delta: Delta?
        let finishReason: String?
        let index: Int

        private enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
            case index
        }
    }

    struct Usage: Codable {
        struct PromptDetails: Codable {
            let textTokens: Int?
            let audioTokens: Int?
            let imageTokens: Int?
            let cachedTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case textTokens = "text_tokens"
                case audioTokens = "audio_tokens"
                case imageTokens = "image_tokens"
                case cachedTokens = "cached_tokens"
            }
        }

        struct CompletionDetails: Codable {
            let reasoningTokens: Int?
            let audioTokens: Int?
            let acceptedPredictionTokens: Int?
            let rejectedPredictionTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
                case audioTokens = "audio_tokens"
                case acceptedPredictionTokens = "accepted_prediction_tokens"
                case rejectedPredictionTokens = "rejected_prediction_tokens"
            }
        }

        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        let promptTokensDetails: PromptDetails?
        let completionTokensDetails: CompletionDetails?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptTokensDetails = "prompt_tokens_details"
            case completionTokensDetails = "completion_tokens_details"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: Usage?
    let citations: [String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case usage
        case citations
    }
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

private let xaiChatResponseSchema = FlexibleSchema(
    Schema<XAIChatResponse>.codable(
        XAIChatResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let xaiChatChunkSchema = FlexibleSchema(
    Schema<XAIChatChunk>.codable(
        XAIChatChunk.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private struct XAIStreamError: Codable {
    let code: String
    let error: String
}

private let xaiStreamErrorSchema = FlexibleSchema(
    Schema<XAIStreamError>.codable(
        XAIStreamError.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private extension ParseJSONResult where Output == XAIChatChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}
