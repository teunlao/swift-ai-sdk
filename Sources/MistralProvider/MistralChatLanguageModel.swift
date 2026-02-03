import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-chat-language-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class MistralChatLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let generateId: @Sendable () -> String
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
    }

    private let modelIdentifier: MistralChatModelId
    private let config: Config

    private static let pdfRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^https://.*$", options: [.caseInsensitive])
    }()

    init(modelId: MistralChatModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            ["application/pdf": [Self.pdfRegex]]
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options, stream: false)

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: { try await mistralFailedResponseHandler($0) },
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mistralChatResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let choice = response.value.choices.first else {
            throw APICallError(
                message: "No choices returned from Mistral",
                url: "\(config.baseURL)/chat/completions",
                requestBodyValues: prepared.body
            )
        }

        var content: [LanguageModelV3Content] = []

        if let parts = choice.message.content?.parts {
            for part in parts {
                switch part {
                case .text(let text):
                    if !text.text.isEmpty {
                        content.append(.text(LanguageModelV3Text(text: text.text)))
                    }
                case .thinking(let segments):
                    let reasoningText = extractReasoningText(segments)
                    if !reasoningText.isEmpty {
                        content.append(.reasoning(LanguageModelV3Reasoning(text: reasoningText)))
                    }
                case .imageURL, .reference:
                    // Ignored per upstream implementation
                    continue
                }
            }
        } else if let text = choice.message.content?.text, !text.isEmpty {
            content.append(.text(LanguageModelV3Text(text: text)))
        }

        if let toolCalls = choice.message.toolCalls {
            for call in toolCalls {
                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: call.id,
                    toolName: call.function.name,
                    input: call.function.arguments ?? ""
                )))
            }
        }

        let usage = LanguageModelV3Usage(
            inputTokens: response.value.usage?.promptTokens,
            outputTokens: response.value.usage?.completionTokens,
            totalTokens: response.value.usage?.totalTokens
        )

        let metadata = mistralResponseMetadata(id: response.value.id, model: response.value.model, created: response.value.created)

        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: mapMistralFinishReason(choice.finishReason),
            usage: usage,
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

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/chat/completions",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: { try await mistralFailedResponseHandler($0) },
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: mistralChatChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var isFirstChunk = true
                var activeText = false
                var activeReasoningId: String?
                let generateId = config.generateId

                do {
                    for try await parseResult in response.value {
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
                                let metadata = mistralResponseMetadata(id: chunk.id, model: chunk.model, created: chunk.created)
                                continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                            }

                            if let usageMeta = chunk.usage {
                                usage = LanguageModelV3Usage(
                                    inputTokens: usageMeta.promptTokens,
                                    outputTokens: usageMeta.completionTokens,
                                    totalTokens: usageMeta.totalTokens
                                )
                            }

                            guard let choice = chunk.choices.first else { continue }

                            if let finish = choice.finishReason {
                                finishReason = mapMistralFinishReason(finish)
                            }

                            if let delta = choice.delta {
                                if let parts = delta.content?.parts {
                                    for part in parts {
                                        if case .thinking(let segments) = part {
                                            let reasoningDelta = extractReasoningText(segments)
                                            guard !reasoningDelta.isEmpty else { continue }

                                            if activeReasoningId == nil {
                                                if activeText {
                                                    continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                                                    activeText = false
                                                }

                                                let newId = generateId()
                                                activeReasoningId = newId
                                                continuation.yield(.reasoningStart(id: newId, providerMetadata: nil))
                                            }

                                            continuation.yield(.reasoningDelta(id: activeReasoningId!, delta: reasoningDelta, providerMetadata: nil))
                                        }
                                    }
                                }

                                if let textDelta = delta.content?.text, !textDelta.isEmpty {
                                    if !activeText {
                                        if let reasoningId = activeReasoningId {
                                            continuation.yield(.reasoningEnd(id: reasoningId, providerMetadata: nil))
                                            activeReasoningId = nil
                                        }
                                        activeText = true
                                        continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                    }

                                    continuation.yield(.textDelta(id: "0", delta: textDelta, providerMetadata: nil))
                                }

                                if let toolCalls = delta.toolCalls {
                                    for call in toolCalls {
                                        let callId = call.id ?? generateId()
                                        let arguments = call.function.arguments ?? ""

                                        continuation.yield(.toolInputStart(
                                            id: callId,
                                            toolName: call.function.name,
                                            providerMetadata: nil,
                                            providerExecuted: nil,
                                            dynamic: nil,
                                            title: nil
                                        ))
                                        if !arguments.isEmpty {
                                            continuation.yield(.toolInputDelta(id: callId, delta: arguments, providerMetadata: nil))
                                        }
                                        continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
                                        continuation.yield(.toolCall(LanguageModelV3ToolCall(toolCallId: callId, toolName: call.function.name, input: arguments)))
                                    }
                                }
                            }
                        }
                    }

                    if let reasoningId = activeReasoningId {
                        continuation.yield(.reasoningEnd(id: reasoningId, providerMetadata: nil))
                    }
                    if activeText {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
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

    // MARK: - Request Preparation

    private func prepareRequest(options: LanguageModelV3CallOptions, stream: Bool) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        let mistralOptions = try await parseProviderOptions(
            provider: "mistral",
            providerOptions: options.providerOptions,
            schema: mistralProviderOptionsSchema
        )

        var prompt = options.prompt

        if case .json(let schema, _, _) = options.responseFormat, schema == nil {
            prompt = injectJSONInstructionIntoMessages(messages: prompt, schema: schema)
        }

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

        let preparedTools = prepareMistralTools(
            tools: options.tools,
            toolChoice: options.toolChoice
        )
        warnings.append(contentsOf: preparedTools.toolWarnings)

        let messages = try convertToMistralChatMessages(prompt: prompt)
        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(messages)
        ]

        if let value = options.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if let value = options.temperature { body["temperature"] = .number(value) }
        if let value = options.topP { body["top_p"] = .number(value) }
        if let value = options.seed { body["random_seed"] = .number(Double(value)) }

        if let safePrompt = mistralOptions?.safePrompt {
            body["safe_prompt"] = .bool(safePrompt)
        }
        if let imageLimit = mistralOptions?.documentImageLimit {
            body["document_image_limit"] = .number(Double(imageLimit))
        }
        if let pageLimit = mistralOptions?.documentPageLimit {
            body["document_page_limit"] = .number(Double(pageLimit))
        }

        let structuredOutputs = mistralOptions?.structuredOutputs ?? true
        let strictJsonSchema = mistralOptions?.strictJsonSchema ?? false

        if let responseFormat = options.responseFormat {
            switch responseFormat {
            case .text:
                break
            case .json(let schema, let name, let description):
                if structuredOutputs, let schema {
                    var schemaObject: [String: JSONValue] = [
                        "schema": schema,
                        "strict": .bool(strictJsonSchema),
                        "name": .string(name ?? "response")
                    ]
                    if let description {
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

        if let parallelToolCalls = mistralOptions?.parallelToolCalls, preparedTools.tools != nil {
            body["parallel_tool_calls"] = .bool(parallelToolCalls)
        }

        if stream {
            body["stream"] = .bool(true)
        }

        return PreparedRequest(body: body, warnings: warnings)
    }
}

// MARK: - Response Schemas

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

private let mistralChatResponseSchema = FlexibleSchema(
    Schema<MistralChatResponse>.codable(
        MistralChatResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let mistralChatChunkSchema = FlexibleSchema(
    Schema<MistralChatChunk>.codable(
        MistralChatChunk.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private extension ParseJSONResult where Output == MistralChatChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}

// MARK: - Models

private struct MistralChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String?
            let content: MistralMessageContent?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case role
                case content
                case toolCalls = "tool_calls"
            }
        }

        struct ToolCall: Codable {
            struct Function: Codable {
                let name: String
                let arguments: String?
            }

            let id: String
            let function: Function
        }

        let index: Int
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: Usage?
}

private struct MistralChatChunk: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let content: MistralMessageContent?
            let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }

        struct ToolCall: Codable {
            struct Function: Codable {
                let name: String
                let arguments: String?
            }

            let id: String?
            let function: Function
        }

        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Codable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: Usage?
}

private enum MistralMessageContent: Codable {
    case text(String)
    case parts([MistralContentPart])
    case none

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .none
            return
        }

        if let string = try? container.decode(String.self) {
            self = .text(string)
            return
        }

        if let parts = try? container.decode([MistralContentPart].self) {
            self = .parts(parts)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported content value"
        )
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .none:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .text(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case .parts(let parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }

    var text: String? {
        switch self {
        case .text(let string):
            return string
        case .parts(let parts):
            return parts.compactMap { part -> String? in
                if case .text(let textPart) = part { return textPart.text }
                return nil
            }.joined()
        case .none:
            return nil
        }
    }

    var parts: [MistralContentPart]? {
        switch self {
        case .parts(let parts):
            return parts
        default:
            return nil
        }
    }
}

private enum MistralContentPart: Codable {
    case text(TextPart)
    case imageURL(ImagePart)
    case reference(ReferencePart)
    case thinking([ThinkingSegment])

    struct TextPart: Codable {
        let type: String
        let text: String
    }

    struct ImagePart: Codable {
        let type: String
        let imageURL: MistralImageURL

        enum CodingKeys: String, CodingKey {
            case type
            case imageURL = "image_url"
        }
    }

    struct ReferencePart: Codable {
        let type: String
        let referenceIds: [Int]

        enum CodingKeys: String, CodingKey {
            case type
            case referenceIds = "reference_ids"
        }
    }

    struct ThinkingSegment: Codable {
        let type: String
        let text: String
    }

    struct ThinkingPart: Codable {
        let type: String
        let thinking: [ThinkingSegment]
    }

    struct MistralImageURL: Codable {
        let url: String?
        let detail: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let urlString = try? container.decode(String.self) {
                self.url = urlString
                self.detail = nil
            } else {
                let keyed = try decoder.container(keyedBy: CodingKeys.self)
                url = try keyed.decodeIfPresent(String.self, forKey: .url)
                detail = try keyed.decodeIfPresent(String.self, forKey: .detail)
            }
        }

        func encode(to encoder: Encoder) throws {
            if let url, detail == nil {
                var container = encoder.singleValueContainer()
                try container.encode(url)
            } else {
                var keyed = encoder.container(keyedBy: CodingKeys.self)
                try keyed.encodeIfPresent(url, forKey: .url)
                try keyed.encodeIfPresent(detail, forKey: .detail)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case url
            case detail
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try TextPart(from: decoder)
            self = .text(text)
        case "image_url":
            let image = try ImagePart(from: decoder)
            self = .imageURL(image)
        case "reference":
            let reference = try ReferencePart(from: decoder)
            self = .reference(reference)
        case "thinking":
            let thinkingPart = try ThinkingPart(from: decoder)
            self = .thinking(thinkingPart.thinking)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported content type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            try text.encode(to: encoder)
        case .imageURL(let image):
            try image.encode(to: encoder)
        case .reference(let reference):
            try reference.encode(to: encoder)
        case .thinking(let segments):
            let part = ThinkingPart(type: "thinking", thinking: segments)
            try part.encode(to: encoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }
}

// MARK: - Helpers

private func extractReasoningText(_ segments: [MistralContentPart.ThinkingSegment]) -> String {
    segments.filter { $0.type == "text" }.map { $0.text }.joined()
}
