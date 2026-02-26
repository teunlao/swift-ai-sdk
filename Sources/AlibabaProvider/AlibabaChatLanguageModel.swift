import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/alibaba-chat-language-model.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

private let alibabaHTTPRegex: NSRegularExpression = {
    try! NSRegularExpression(pattern: "^https?:\\/\\/.*$")
}()

struct AlibabaChatConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let includeUsage: Bool
    let generateId: IDGenerator

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () throws -> [String: String?],
        fetch: FetchFunction?,
        includeUsage: Bool,
        generateId: @escaping IDGenerator = generateID
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.includeUsage = includeUsage
        self.generateId = generateId
    }
}

private struct AlibabaPreparedTools {
    let tools: JSONValue?
    let toolChoice: JSONValue?
    let warnings: [SharedV3Warning]
}

private func prepareAlibabaTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?
) -> AlibabaPreparedTools {
    guard let tools, !tools.isEmpty else {
        return AlibabaPreparedTools(tools: nil, toolChoice: nil, warnings: [])
    }

    var warnings: [SharedV3Warning] = []
    var prepared: [JSONValue] = []
    prepared.reserveCapacity(tools.count)

    for tool in tools {
        switch tool {
        case .function(let function):
            var functionObject: [String: JSONValue] = [
                "name": .string(function.name),
                "parameters": function.inputSchema,
            ]

            if let description = function.description {
                functionObject["description"] = .string(description)
            }
            if let strict = function.strict {
                functionObject["strict"] = .bool(strict)
            }

            prepared.append(.object([
                "type": .string("function"),
                "function": .object(functionObject),
            ]))

        case .provider(let providerTool):
            warnings.append(.unsupported(feature: "provider-defined tool \(providerTool.id)", details: nil))
        }
    }

    let toolChoiceValue: JSONValue?
    if let toolChoice {
        switch toolChoice {
        case .auto:
            toolChoiceValue = .string("auto")
        case .none:
            toolChoiceValue = .string("none")
        case .required:
            toolChoiceValue = .string("required")
        case .tool(let name):
            toolChoiceValue = .object([
                "type": .string("function"),
                "function": .object(["name": .string(name)]),
            ])
        }
    } else {
        toolChoiceValue = nil
    }

    return AlibabaPreparedTools(
        tools: prepared.isEmpty ? nil : .array(prepared),
        toolChoice: toolChoiceValue,
        warnings: warnings
    )
}

public final class AlibabaChatLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"

    private let modelIdentifier: AlibabaChatModelId
    private let config: AlibabaChatConfig

    init(
        modelId: AlibabaChatModelId,
        config: AlibabaChatConfig
    ) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            ["image/*": [alibabaHTTPRegex]]
        }
    }

    private struct PreparedArgs {
        let args: [String: JSONValue]
        let warnings: [SharedV3Warning]
    }

    private func getArgs(_ options: LanguageModelV3CallOptions) async throws -> PreparedArgs {
        var warnings: [SharedV3Warning] = []

        let cacheControlValidator = CacheControlValidator()
        let alibabaOptions = try await parseProviderOptions(
            provider: "alibaba",
            providerOptions: options.providerOptions,
            schema: alibabaLanguageModelOptionsFlexibleSchema
        )

        if options.frequencyPenalty != nil {
            warnings.append(.unsupported(feature: "frequencyPenalty", details: nil))
        }

        var args: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
        ]

        if let maxTokens = options.maxOutputTokens {
            args["max_tokens"] = .number(Double(maxTokens))
        }
        if let temperature = options.temperature {
            args["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            args["top_p"] = .number(topP)
        }
        if let topK = options.topK {
            args["top_k"] = .number(Double(topK))
        }
        if let presencePenalty = options.presencePenalty {
            args["presence_penalty"] = .number(presencePenalty)
        }
        if let stop = options.stopSequences, !stop.isEmpty {
            args["stop"] = .array(stop.map { .string($0) })
        }
        if let seed = options.seed {
            args["seed"] = .number(Double(seed))
        }

        if let responseFormat = options.responseFormat {
            switch responseFormat {
            case .text:
                break
            case let .json(schema, name, description):
                if let schema {
                    var jsonSchema: [String: JSONValue] = [
                        "schema": schema,
                        "name": .string(name ?? "response"),
                    ]
                    if let description {
                        jsonSchema["description"] = .string(description)
                    }
                    args["response_format"] = .object([
                        "type": .string("json_schema"),
                        "json_schema": .object(jsonSchema),
                    ])
                } else {
                    args["response_format"] = .object(["type": .string("json_object")])
                }
            }
        }

        if let enableThinking = alibabaOptions?.enableThinking {
            args["enable_thinking"] = .bool(enableThinking)
        }
        if let thinkingBudget = alibabaOptions?.thinkingBudget {
            args["thinking_budget"] = .number(thinkingBudget)
        }

        let messages = try convertToAlibabaChatMessages(
            prompt: options.prompt,
            cacheControlValidator: cacheControlValidator
        )
        args["messages"] = .array(messages)

        let preparedTools = prepareAlibabaTools(tools: options.tools, toolChoice: options.toolChoice)
        warnings.append(contentsOf: cacheControlValidator.getWarnings())
        warnings.append(contentsOf: preparedTools.warnings)

        if let tools = preparedTools.tools {
            args["tools"] = tools
        }
        if let toolChoice = preparedTools.toolChoice {
            args["tool_choice"] = toolChoice
        }

        if preparedTools.tools != nil, let parallelToolCalls = alibabaOptions?.parallelToolCalls {
            args["parallel_tool_calls"] = .bool(parallelToolCalls)
        }

        return PreparedArgs(args: args, warnings: warnings)
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await getArgs(options)

        let defaultHeaders = try config.headers()
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions",
            headers: headers,
            body: JSONValue.object(prepared.args),
            failedResponseHandler: alibabaFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: alibabaChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let choice = response.value.choices.first else {
            throw APICallError(
                message: "Alibaba response did not include choices.",
                url: "\(config.baseURL)/chat/completions",
                requestBodyValues: prepared.args
            )
        }

        var content: [LanguageModelV3Content] = []

        if let text = choice.message.content, !text.isEmpty {
            content.append(.text(LanguageModelV3Text(text: text)))
        }

        if let reasoning = choice.message.reasoningContent, !reasoning.isEmpty {
            content.append(.reasoning(LanguageModelV3Reasoning(text: reasoning)))
        }

        if let toolCalls = choice.message.toolCalls {
            for toolCall in toolCalls {
                guard let name = toolCall.function.name else { continue }
                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCall.id,
                    toolName: name,
                    input: toolCall.function.arguments ?? "{}",
                    providerExecuted: nil,
                    dynamic: nil,
                    providerMetadata: nil
                )))
            }
        }

        let finishReason = LanguageModelV3FinishReason(
            unified: mapFinishReason(choice.finishReason),
            raw: choice.finishReason
        )

        let metadata = responseMetadata(id: response.value.id, model: response.value.model, created: response.value.created)

        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: convertAlibabaUsage(response.value.usage),
            request: LanguageModelV3RequestInfo(body: prepared.args),
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
        let prepared = try await getArgs(options)

        var body = prepared.args
        body["stream"] = .bool(true)
        if config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }

        let defaultHeaders = try config.headers()
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let eventStream = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions",
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: alibabaFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: alibabaChatChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason = LanguageModelV3FinishReason(unified: .other, raw: nil)
                var usage: AlibabaUsage? = nil

                var isFirstChunk = true
                var activeText = false
                var activeReasoningId: String? = nil
                var toolCalls: [ToolCallState?] = []

                do {
                    for try await parseResult in eventStream.value {
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
                                let meta = responseMetadata(id: chunk.id, model: chunk.model, created: chunk.created)
                                continuation.yield(.responseMetadata(id: meta.id, modelId: meta.modelId, timestamp: meta.timestamp))
                            }

                            if let chunkUsage = chunk.usage {
                                usage = chunkUsage
                            }

                            if chunk.choices.isEmpty {
                                continue
                            }

                            let choice = chunk.choices[0]

                            if let raw = choice.finishReason {
                                finishReason = .init(
                                    unified: mapFinishReason(raw),
                                    raw: raw
                                )
                            }

                            let delta = choice.delta

                            if let reasoningDelta = delta.reasoningContent, !reasoningDelta.isEmpty {
                                if activeReasoningId == nil {
                                    if activeText {
                                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                                        activeText = false
                                    }

                                    let id = config.generateId()
                                    activeReasoningId = id
                                    continuation.yield(.reasoningStart(id: id, providerMetadata: nil))
                                }

                                continuation.yield(.reasoningDelta(id: activeReasoningId!, delta: reasoningDelta, providerMetadata: nil))
                            }

                            if let textDelta = delta.content, !textDelta.isEmpty {
                                if let id = activeReasoningId {
                                    continuation.yield(.reasoningEnd(id: id, providerMetadata: nil))
                                    activeReasoningId = nil
                                }

                                if !activeText {
                                    continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                    activeText = true
                                }

                                continuation.yield(.textDelta(id: "0", delta: textDelta, providerMetadata: nil))
                            }

                            if let toolCallDeltas = delta.toolCalls {
                                if let id = activeReasoningId {
                                    continuation.yield(.reasoningEnd(id: id, providerMetadata: nil))
                                    activeReasoningId = nil
                                }
                                if activeText {
                                    continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                                    activeText = false
                                }

                                try handleToolCallDeltas(
                                    toolCallDeltas,
                                    toolCalls: &toolCalls,
                                    continuation: continuation
                                )
                            }
                        }
                    }

                    if let activeReasoningId {
                        continuation.yield(.reasoningEnd(id: activeReasoningId, providerMetadata: nil))
                    }
                    if activeText {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                    }

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: convertAlibabaUsage(usage),
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
            request: LanguageModelV3RequestInfo(body: body),
            response: LanguageModelV3StreamResponseInfo(headers: eventStream.responseHeaders)
        )
    }

    private func handleToolCallDeltas(
        _ deltas: [AlibabaChatChunkToolCallDelta],
        toolCalls: inout [ToolCallState?],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) throws {
        for delta in deltas {
            let index = delta.index ?? toolCalls.count
            if index >= toolCalls.count {
                toolCalls.append(contentsOf: Array(repeating: nil, count: index - toolCalls.count + 1))
            }

            if toolCalls[index] == nil {
                guard let id = delta.id else {
                    throw InvalidResponseDataError(data: delta, message: "Expected 'id' to be a string.")
                }
                guard let name = delta.function?.name else {
                    throw InvalidResponseDataError(data: delta, message: "Expected 'function.name' to be a string.")
                }

                continuation.yield(.toolInputStart(
                    id: id,
                    toolName: name,
                    providerMetadata: nil,
                    providerExecuted: nil,
                    dynamic: nil,
                    title: nil
                ))

                var state = ToolCallState(id: id, name: name, arguments: delta.function?.arguments ?? "", hasFinished: false)
                toolCalls[index] = state

                if !state.arguments.isEmpty {
                    continuation.yield(.toolInputDelta(id: id, delta: state.arguments, providerMetadata: nil))
                }

                if isParsableJson(state.arguments) {
                    continuation.yield(.toolInputEnd(id: id, providerMetadata: nil))
                    continuation.yield(.toolCall(LanguageModelV3ToolCall(
                        toolCallId: id,
                        toolName: name,
                        input: state.arguments,
                        providerExecuted: nil,
                        dynamic: nil,
                        providerMetadata: nil
                    )))
                    state.hasFinished = true
                    toolCalls[index] = state
                }

                continue
            }

            var state = toolCalls[index]!
            if state.hasFinished {
                continue
            }

            if let argumentDelta = delta.function?.arguments {
                state.arguments += argumentDelta
                continuation.yield(.toolInputDelta(id: state.id, delta: argumentDelta, providerMetadata: nil))

                if isParsableJson(state.arguments) {
                    continuation.yield(.toolInputEnd(id: state.id, providerMetadata: nil))
                    continuation.yield(.toolCall(LanguageModelV3ToolCall(
                        toolCallId: state.id,
                        toolName: state.name,
                        input: state.arguments,
                        providerExecuted: nil,
                        dynamic: nil,
                        providerMetadata: nil
                    )))
                    state.hasFinished = true
                }
            }

            toolCalls[index] = state
        }
    }

    private struct ToolCallState {
        var id: String
        var name: String
        var arguments: String
        var hasFinished: Bool
    }
}

private struct AlibabaChatResponse: Codable {
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

                let id: String
                let type: String?
                let function: ToolFunction

                private enum CodingKeys: String, CodingKey {
                    case id
                    case type
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
        let finishReason: String?
        let index: Int

        private enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
            case index
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: AlibabaUsage?

    private enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case usage
    }
}

private struct AlibabaChatChunkDelta: Codable {
    let role: String?
    let content: String?
    let reasoningContent: String?
    let toolCalls: [AlibabaChatChunkToolCallDelta]?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
    }
}

private struct AlibabaChatChunkChoice: Codable {
    let delta: AlibabaChatChunkDelta
    let finishReason: String?
    let index: Int

    private enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
        case index
    }
}

private struct AlibabaChatChunk: Codable {
    let id: String?
    let created: Double?
    let model: String?
    let choices: [AlibabaChatChunkChoice]
    let usage: AlibabaUsage?

    private enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case choices
        case usage
    }
}

private struct AlibabaChatChunkToolCallDelta: Codable {
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

    private enum CodingKeys: String, CodingKey {
        case index
        case id
        case type
        case function
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let alibabaChatResponseSchema = FlexibleSchema(
    Schema<AlibabaChatResponse>.codable(
        AlibabaChatResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let alibabaChatChunkSchema = FlexibleSchema(
    Schema<AlibabaChatChunk>.codable(
        AlibabaChatChunk.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private extension ParseJSONResult where Output == AlibabaChatChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}

private func mapFinishReason(_ finishReason: String?) -> LanguageModelV3FinishReason.Unified {
    switch finishReason {
    case "stop":
        return .stop
    case "length":
        return .length
    case "content_filter":
        return .contentFilter
    case "function_call", "tool_calls":
        return .toolCalls
    default:
        return .other
    }
}

private func responseMetadata(
    id: String?,
    model: String?,
    created: Double?
) -> (id: String?, modelId: String?, timestamp: Date?) {
    let timestamp = created.map { Date(timeIntervalSince1970: $0) }
    return (id, model, timestamp)
}
