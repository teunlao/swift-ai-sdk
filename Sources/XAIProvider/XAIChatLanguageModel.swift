import Foundation
import AISDKProvider
import AISDKProviderUtils

/// xAI chat language model implementation.
/// Mirrors `packages/xai/src/xai-chat-language-model.ts`.
public final class XAIChatLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () -> [String: String?]
        let generateId: @Sendable () -> String
        let fetch: FetchFunction?
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [LanguageModelV3CallWarning]
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

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: xaiChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        var contents: [LanguageModelV3Content] = []
        let lastMessage = prepared.messages.last
        if let choice = response.value.choices.first {
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

        let usage = LanguageModelV3Usage(
            inputTokens: response.value.usage.promptTokens,
            outputTokens: response.value.usage.completionTokens,
            totalTokens: response.value.usage.totalTokens,
            reasoningTokens: response.value.usage.completionTokensDetails?.reasoningTokens,
            cachedInputTokens: nil
        )

        let metadata = xaiResponseMetadata(
            id: response.value.id,
            model: response.value.model,
            created: response.value.created
        )

        return LanguageModelV3GenerateResult(
            content: contents,
            finishReason: mapXaiFinishReason(response.value.choices.first?.finishReason),
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

        let streamResponse = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(streamBody),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: xaiChatChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let messages = prepared.messages

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var isFirstChunk = true
                var contentBlocks: [String: ContentBlockType] = [:]
                var lastReasoningDeltas: [String: String] = [:]

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
                                usage = LanguageModelV3Usage(
                                    inputTokens: usageInfo.promptTokens,
                                    outputTokens: usageInfo.completionTokens,
                                    totalTokens: usageInfo.totalTokens,
                                    reasoningTokens: usageInfo.completionTokensDetails?.reasoningTokens,
                                    cachedInputTokens: nil
                                )
                            }

                            guard let choice = chunk.choices.first else { continue }
                            if let finish = choice.finishReason {
                                finishReason = mapXaiFinishReason(finish)
                            }

                            guard let delta = choice.delta else { continue }

                            if let text = delta.content, !text.isEmpty {
                                let shouldEmit = !(messages.last?.role == .assistant && messages.last?.assistantContent == text)
                                if shouldEmit {
                                    let blockId = "text-\(chunk.id ?? String(choice.index))"
                                    if contentBlocks[blockId] == nil {
                                        contentBlocks[blockId] = .text
                                        continuation.yield(.textStart(id: blockId, providerMetadata: nil))
                                    }
                                    continuation.yield(.textDelta(id: blockId, delta: text, providerMetadata: nil))
                                }
                            }

                            if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                                let blockId = "reasoning-\(chunk.id ?? String(choice.index))"
                                if lastReasoningDeltas[blockId] != reasoning {
                                    lastReasoningDeltas[blockId] = reasoning
                                    if contentBlocks[blockId] == nil {
                                        contentBlocks[blockId] = .reasoning
                                        continuation.yield(.reasoningStart(id: blockId, providerMetadata: nil))
                                    }
                                    continuation.yield(.reasoningDelta(id: blockId, delta: reasoning, providerMetadata: nil))
                                }
                            }

                            if let toolCalls = delta.toolCalls {
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

                    for (blockId, blockType) in contentBlocks {
                        switch blockType {
                        case .text:
                            continuation.yield(.textEnd(id: blockId, providerMetadata: nil))
                        case .reasoning:
                            continuation.yield(.reasoningEnd(id: blockId, providerMetadata: nil))
                        }
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
            request: LanguageModelV3RequestInfo(body: streamBody),
            response: LanguageModelV3StreamResponseInfo(headers: streamResponse.responseHeaders)
        )
    }

    // MARK: - Preparation

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [LanguageModelV3CallWarning] = []

        let providerOptions = try await parseProviderOptions(
            provider: "xai",
            providerOptions: options.providerOptions,
            schema: xaiProviderOptionsSchema
        )

        if options.topK != nil {
            warnings.append(.unsupportedSetting(setting: "topK", details: nil))
        }
        if options.frequencyPenalty != nil {
            warnings.append(.unsupportedSetting(setting: "frequencyPenalty", details: nil))
        }
        if options.presencePenalty != nil {
            warnings.append(.unsupportedSetting(setting: "presencePenalty", details: nil))
        }
        if options.stopSequences != nil {
            warnings.append(.unsupportedSetting(setting: "stopSequences", details: nil))
        }

        if case let .json(schema, _, _) = options.responseFormat, schema != nil {
            warnings.append(.unsupportedSetting(setting: "responseFormat", details: "JSON response format schema is not supported"))
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
            body["max_tokens"] = .number(Double(maxTokens))
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
        struct CompletionDetails: Codable {
            let reasoningTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        let completionTokensDetails: CompletionDetails?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case completionTokensDetails = "completion_tokens_details"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let object: String?
    let usage: Usage
    let citations: [String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case object
        case usage
        case citations
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
        struct CompletionDetails: Codable {
            let reasoningTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        let completionTokensDetails: CompletionDetails?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
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
