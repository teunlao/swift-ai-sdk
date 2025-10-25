import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-chat-language-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class CohereChatLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let generateId: @Sendable () -> String
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [LanguageModelV3CallWarning]
    }

    private let modelIdentifier: CohereChatModelId
    private let config: Config

    init(modelId: CohereChatModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options, stream: false)

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: cohereFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: cohereChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        var content: [LanguageModelV3Content] = []

        if let messageContent = response.value.message.content {
            for item in messageContent {
                switch item {
                case .text(let value) where !value.text.isEmpty:
                    content.append(.text(LanguageModelV3Text(text: value.text)))
                case .thinking(let value) where !value.thinking.isEmpty:
                    content.append(.reasoning(LanguageModelV3Reasoning(text: value.thinking)))
                default:
                    continue
                }
            }
        }

        if let citations = response.value.message.citations {
            for citation in citations {
                let providerMetadata: SharedV3ProviderMetadata = [
                    "cohere": buildCitationMetadata(citation)
                ]

                let title = citation.sources.first?.document.title ?? "Document"
                let filename = citation.sources.first?.document.id

                content.append(
                    .source(
                        .document(
                            id: config.generateId(),
                            mediaType: "text/plain",
                            title: title,
                            filename: filename,
                            providerMetadata: providerMetadata
                        )
                    )
                )
            }
        }

        if let toolCalls = response.value.message.toolCalls {
            for call in toolCalls {
                let arguments = call.function.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedArguments = sanitizeToolArguments(arguments)
                content.append(
                    .toolCall(
                        LanguageModelV3ToolCall(
                            toolCallId: call.id,
                            toolName: call.function.name,
                            input: normalizedArguments
                        )
                    )
                )
            }
        }

        let usageTokens = response.value.usage.tokens
        let usage = LanguageModelV3Usage(
            inputTokens: usageTokens.inputTokens,
            outputTokens: usageTokens.outputTokens,
            totalTokens: usageTokens.inputTokens + usageTokens.outputTokens,
            reasoningTokens: nil,
            cachedInputTokens: nil
        )

        let responseInfo = LanguageModelV3ResponseInfo(
            id: response.value.generationId,
            timestamp: nil,
            modelId: nil,
            headers: response.responseHeaders,
            body: response.rawValue
        )

        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: mapCohereFinishReason(response.value.finishReason),
            usage: usage,
            providerMetadata: nil,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: responseInfo,
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options, stream: true)

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: cohereFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: cohereChatChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()

                var pendingToolCall: PendingToolCall?
                var activeReasoningIdentifiers: Set<String> = []

                do {
                    for try await parseResult in response.value {
                        if options.includeRawChunks == true, let raw = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .error
                            continuation.yield(.error(error: .string(String(describing: error))))

                        case .success(let event, _):
                            switch event.type {
                            case .contentStart:
                                if event.delta?.message?.content?.type == "thinking" {
                                    let identifier = String(event.index ?? 0)
                                    activeReasoningIdentifiers.insert(identifier)
                                    continuation.yield(.reasoningStart(id: identifier, providerMetadata: nil))
                                } else {
                                    continuation.yield(.textStart(id: String(event.index ?? 0), providerMetadata: nil))
                                }

                            case .contentDelta:
                                if let thinking = event.delta?.message?.content?.thinking {
                                    let identifier = String(event.index ?? 0)
                                    continuation.yield(.reasoningDelta(id: identifier, delta: thinking, providerMetadata: nil))
                                } else if let text = event.delta?.message?.content?.text {
                                    continuation.yield(.textDelta(id: String(event.index ?? 0), delta: text, providerMetadata: nil))
                                }

                            case .contentEnd:
                                let identifier = String(event.index ?? 0)
                                if activeReasoningIdentifiers.contains(identifier) {
                                    activeReasoningIdentifiers.remove(identifier)
                                    continuation.yield(.reasoningEnd(id: identifier, providerMetadata: nil))
                                } else {
                                    continuation.yield(.textEnd(id: identifier, providerMetadata: nil))
                                }

                            case .toolCallStart:
                                guard let call = event.delta?.message?.toolCalls else { continue }
                                let toolId = call.id
                                let initialArguments = call.function.arguments
                                pendingToolCall = PendingToolCall(
                                    id: toolId,
                                    name: call.function.name,
                                    arguments: initialArguments
                                )

                                continuation.yield(.toolInputStart(id: toolId, toolName: call.function.name, providerMetadata: nil, providerExecuted: nil))

                                if !initialArguments.isEmpty {
                                    continuation.yield(.toolInputDelta(id: toolId, delta: initialArguments, providerMetadata: nil))
                                }

                            case .toolCallDelta:
                                guard var current = pendingToolCall else { continue }
                                let deltaArguments = event.delta?.message?.toolCalls?.function.arguments ?? ""
                                current.arguments += deltaArguments
                                pendingToolCall = current

                                if !deltaArguments.isEmpty {
                                    continuation.yield(.toolInputDelta(id: current.id, delta: deltaArguments, providerMetadata: nil))
                                }

                            case .toolCallEnd:
                                guard let current = pendingToolCall else { continue }
                                continuation.yield(.toolInputEnd(id: current.id, providerMetadata: nil))

                                let normalizedArguments = sanitizeToolArguments(current.arguments)
                                continuation.yield(.toolCall(LanguageModelV3ToolCall(toolCallId: current.id, toolName: current.name, input: normalizedArguments)))
                                pendingToolCall = nil

                            case .messageStart:
                                continuation.yield(.responseMetadata(id: event.id, modelId: nil, timestamp: nil))

                            case .messageEnd:
                                finishReason = mapCohereFinishReason(event.delta?.finishReason)
                                if let tokens = event.delta?.usage?.tokens {
                                    usage = LanguageModelV3Usage(
                                        inputTokens: tokens.inputTokens,
                                        outputTokens: tokens.outputTokens,
                                        totalTokens: tokens.inputTokens + tokens.outputTokens,
                                        reasoningTokens: nil,
                                        cachedInputTokens: nil
                                    )
                                }

                            case .toolPlanDelta, .citationStart, .citationEnd:
                                continue
                            }
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
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3StreamResponseInfo(headers: response.responseHeaders)
        )
    }

    private func prepareRequest(options: LanguageModelV3CallOptions, stream: Bool) async throws -> PreparedRequest {
        var warnings: [LanguageModelV3CallWarning] = []

        let cohereOptions = try await parseProviderOptions(
            provider: "cohere",
            providerOptions: options.providerOptions,
            schema: cohereChatOptionsSchema
        )

        let conversion = try convertToCohereChatPrompt(options.prompt)
        warnings.append(contentsOf: conversion.warnings)

        let preparedTools = prepareCohereTools(tools: options.tools, toolChoice: options.toolChoice)
        warnings.append(contentsOf: preparedTools.toolWarnings)

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(conversion.messages)
        ]

        if let frequencyPenalty = options.frequencyPenalty {
            body["frequency_penalty"] = .number(frequencyPenalty)
        }
        if let presencePenalty = options.presencePenalty {
            body["presence_penalty"] = .number(presencePenalty)
        }
        if let maxTokens = options.maxOutputTokens {
            body["max_tokens"] = .number(Double(maxTokens))
        }
        if let temperature = options.temperature {
            body["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            body["p"] = .number(topP)
        }
        if let topK = options.topK {
            body["k"] = .number(Double(topK))
        }
        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }
        if let stopSequences = options.stopSequences {
            body["stop_sequences"] = .array(stopSequences.map { .string($0) })
        }

        if case .json(let schema, _, _) = options.responseFormat {
            var responseFormat: [String: JSONValue] = ["type": .string("json_object")]
            if let schema {
                responseFormat["json_schema"] = schema
            }
            body["response_format"] = .object(responseFormat)
        }

        if !conversion.documents.isEmpty {
            body["documents"] = .array(conversion.documents)
        }

        if let tools = preparedTools.tools {
            body["tools"] = .array(tools)
        }

        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = .string(toolChoice.rawValue)
        }

        if let thinking = cohereOptions?.thinking {
            var thinkingObject: [String: JSONValue] = [
                "type": .string(thinking.type?.rawValue ?? "enabled")
            ]
            if let tokenBudget = thinking.tokenBudget {
                thinkingObject["token_budget"] = .number(Double(tokenBudget))
            }
            body["thinking"] = .object(thinkingObject)
        }

        if stream {
            body["stream"] = .bool(true)
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func sanitizeToolArguments(_ raw: String) -> String {
        let trimmed = raw.isEmpty ? "{}" : raw
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(json),
              let normalizedData = try? JSONSerialization.data(withJSONObject: json, options: [])
        else {
            return trimmed == "null" ? "{}" : trimmed
        }
        return String(data: normalizedData, encoding: .utf8) ?? (trimmed == "null" ? "{}" : trimmed)
    }

    private func buildCitationMetadata(_ citation: CohereChatResponse.Message.Citation) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
            "start": .number(Double(citation.start)),
            "end": .number(Double(citation.end)),
            "text": .string(citation.text),
            "sources": .array(citation.sources.map { source in
                var documentObject: [String: JSONValue] = [
                    "text": .string(source.document.text),
                    "title": .string(source.document.title)
                ]
                if let documentId = source.document.id {
                    documentObject["id"] = .string(documentId)
                }

                var object: [String: JSONValue] = [
                    "document": .object(documentObject)
                ]
                if let type = source.type {
                    object["type"] = .string(type)
                }
                if let id = source.id {
                    object["id"] = .string(id)
                }
                return .object(object)
            })
        ]

        if let citationType = citation.type {
            metadata["citationType"] = .string(citationType)
        }

        return metadata
    }

    private struct PendingToolCall {
        var id: String
        var name: String
        var arguments: String
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let cohereChatResponseSchema = FlexibleSchema(
    Schema<CohereChatResponse>.codable(
        CohereChatResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let cohereChatChunkSchema = FlexibleSchema(
    Schema<CohereChatStreamEvent>.codable(
        CohereChatStreamEvent.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private struct CohereChatResponse: Codable {
    struct Message: Codable {
        struct ContentText: Codable { let type: String; let text: String }
        struct ContentThinking: Codable { let type: String; let thinking: String }

        enum Content: Codable {
            case text(ContentText)
            case thinking(ContentThinking)

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(String.self, forKey: .type)
                switch type {
                case "text":
                    self = .text(try ContentText(from: decoder))
                case "thinking":
                    self = .thinking(try ContentThinking(from: decoder))
                default:
                    throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
                }
            }

            func encode(to encoder: Encoder) throws {
                switch self {
                case .text(let value):
                    try value.encode(to: encoder)
                case .thinking(let value):
                    try value.encode(to: encoder)
                }
            }

            private enum CodingKeys: String, CodingKey { case type }
        }

        struct ToolCall: Codable {
            struct Function: Codable { let name: String; let arguments: String }
            let id: String
            let type: String
            let function: Function

            private enum CodingKeys: String, CodingKey {
                case id
                case type
                case function
            }
        }

        struct CitationSource: Codable {
            struct Document: Codable {
                let id: String?
                let text: String
                let title: String
            }

            let type: String?
            let id: String?
            let document: Document

            private enum CodingKeys: String, CodingKey {
                case type
                case id
                case document
            }
        }

        struct Citation: Codable {
            let start: Int
            let end: Int
            let text: String
            let sources: [CitationSource]
            let type: String?
        }

        let role: String
        let content: [Content]?
        let toolPlan: String?
        let toolCalls: [ToolCall]?
        let citations: [Citation]?

        private enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolPlan = "tool_plan"
            case toolCalls = "tool_calls"
            case citations
        }
    }

    struct Usage: Codable {
        struct Tokens: Codable {
            let inputTokens: Int
            let outputTokens: Int

            private enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }

        let tokens: Tokens
    }

    let generationId: String?
    let message: Message
    let finishReason: String?
    let usage: Usage

    private enum CodingKeys: String, CodingKey {
        case generationId = "generation_id"
        case message
        case finishReason = "finish_reason"
        case usage
    }
}

private struct CohereChatStreamEvent: Codable {
    enum EventType: String, Codable {
        case contentStart = "content-start"
        case contentDelta = "content-delta"
        case contentEnd = "content-end"
        case messageStart = "message-start"
        case messageEnd = "message-end"
        case toolCallStart = "tool-call-start"
        case toolCallDelta = "tool-call-delta"
        case toolCallEnd = "tool-call-end"
        case toolPlanDelta = "tool-plan-delta"
        case citationStart = "citation-start"
        case citationEnd = "citation-end"
    }

    struct Delta: Codable {
        struct Message: Codable {
            struct Content: Codable {
                let type: String?
                let text: String?
                let thinking: String?

                private enum CodingKeys: String, CodingKey {
                    case type
                    case text
                    case thinking
                }
            }

            struct ToolCall: Codable {
                struct Function: Codable {
                    let name: String
                    let arguments: String
                }

                let id: String
                let type: String
                let function: Function

                private enum CodingKeys: String, CodingKey {
                    case id
                    case type
                    case function
                }
            }

            let content: Content?
            let toolCalls: ToolCall?

            private enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }

        struct Usage: Codable {
            struct Tokens: Codable {
                let inputTokens: Int
                let outputTokens: Int

                private enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                }
            }

            let tokens: Tokens
        }

        let message: Message?
        let finishReason: String?
        let usage: Usage?

        private enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
            case usage
        }
    }

    let type: EventType
    let index: Int?
    let id: String?
    let delta: Delta?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        guard let eventType = EventType(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown event type: \(rawType)")
        }
        type = eventType
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        delta = try container.decodeIfPresent(Delta.self, forKey: .delta)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case index
        case id
        case delta
    }
}

private extension LanguageModelV3Usage {
    init() {
        self.init(inputTokens: nil, outputTokens: nil, totalTokens: nil, reasoningTokens: nil, cachedInputTokens: nil)
    }
}

private extension ParseJSONResult where Output == CohereChatStreamEvent {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}
