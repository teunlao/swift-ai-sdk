import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/responses/huggingface-responses-language-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class HuggingFaceResponsesLanguageModel: LanguageModelV3 {
    private static let imageRegex = try! NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
    private static let supportedUrlMap: [String: [NSRegularExpression]] = [
        "image/*": [HuggingFaceResponsesLanguageModel.imageRegex]
    ]

    private let modelIdentifier: HuggingFaceResponsesModelId
    private let config: HuggingFaceConfig

    init(modelId: HuggingFaceResponsesModelId, config: HuggingFaceConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public let specificationVersion: String = "v3"
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { Self.supportedUrlMap }
    }

    // MARK: - Generation

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareArguments(options: options)

        var body = prepared.body
        body["stream"] = .bool(false)

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses")),
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: huggingfaceFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: huggingfaceResponsesResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        if let errorPayload = response.value.error {
            throw APICallError(
                message: errorPayload.message,
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses")),
                requestBodyValues: body,
                statusCode: 400,
                responseHeaders: response.responseHeaders,
                responseBody: response.rawValue as? String,
                isRetryable: false,
                data: errorPayload
            )
        }

        let generation = try buildGenerationResult(from: response.value)

        return LanguageModelV3GenerateResult(
            content: generation.content,
            finishReason: generation.finishReason,
            usage: generation.usage,
            providerMetadata: generation.providerMetadata,
            request: LanguageModelV3RequestInfo(body: body),
            response: LanguageModelV3ResponseInfo(
                id: response.value.id,
                timestamp: Date(timeIntervalSince1970: response.value.createdAt),
                modelId: response.value.model,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    // MARK: - Streaming

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareArguments(options: options)

        var body = prepared.body
        body["stream"] = .bool(true)

        let streamResponse = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses")),
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: huggingfaceFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: huggingfaceResponsesChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var responseId: String? = nil

                do {
                    for try await parseResult in streamResponse.value {
                        if options.includeRawChunks == true, let raw = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .error
                            continuation.yield(.error(error: .string(String(describing: error))))

                        case .success(let chunk, _):
                            try handleStreamChunk(
                                chunk,
                                continuation: continuation,
                                finishReason: &finishReason,
                                usage: &usage,
                                responseId: &responseId
                            )
                        }
                    }

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: usage,
                        providerMetadata: responseProviderMetadata(responseId: responseId)
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
            response: LanguageModelV3StreamResponseInfo(headers: streamResponse.responseHeaders)
        )
    }

    // MARK: - Argument Preparation

    private func prepareArguments(options: LanguageModelV3CallOptions) async throws -> (body: [String: JSONValue], warnings: [LanguageModelV3CallWarning]) {
        var warnings: [LanguageModelV3CallWarning] = []

        if options.topK != nil {
            warnings.append(.unsupportedSetting(setting: "topK", details: nil))
        }
        if options.seed != nil {
            warnings.append(.unsupportedSetting(setting: "seed", details: nil))
        }
        if options.presencePenalty != nil {
            warnings.append(.unsupportedSetting(setting: "presencePenalty", details: nil))
        }
        if options.frequencyPenalty != nil {
            warnings.append(.unsupportedSetting(setting: "frequencyPenalty", details: nil))
        }
        if options.stopSequences != nil {
            warnings.append(.unsupportedSetting(setting: "stopSequences", details: nil))
        }

        let converted = try convertToHuggingFaceResponsesMessages(prompt: options.prompt)
        warnings.append(contentsOf: converted.warnings)

        let providerOptions = try await parseProviderOptions(
            provider: "huggingface",
            providerOptions: options.providerOptions,
            schema: huggingfaceResponsesProviderOptionsSchema
        )

        let preparedTools = prepareHuggingFaceResponsesTools(
            tools: options.tools,
            toolChoice: options.toolChoice
        )
        warnings.append(contentsOf: preparedTools.warnings)

        var args: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "input": converted.input
        ]

        if let temperature = options.temperature {
            args["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            args["top_p"] = .number(topP)
        }
        if let maxOutputTokens = options.maxOutputTokens {
            args["max_output_tokens"] = .number(Double(maxOutputTokens))
        }

        if let metadata = providerOptions?.metadata {
            args["metadata"] = .object(metadata.reduce(into: [:]) { result, entry in
                result[entry.key] = .string(entry.value)
            })
        }
        if let instructions = providerOptions?.instructions {
            args["instructions"] = .string(instructions)
        }

        if let responseFormat = options.responseFormat {
            switch responseFormat {
            case .text:
                break
            case let .json(schema, name, description):
                if let schema {
                    var format: [String: JSONValue] = [
                        "type": .string("json_schema"),
                        "strict": .bool(providerOptions?.strictJsonSchema ?? false),
                        "name": .string(name ?? "response"),
                        "schema": schema
                    ]
                    if let description {
                        format["description"] = .string(description)
                    }
                    args["text"] = .object([
                        "format": .object(format)
                    ])
                }
            }
        }

        if let tools = preparedTools.tools {
            args["tools"] = tools
        }
        if let toolChoice = preparedTools.toolChoice {
            args["tool_choice"] = toolChoice
        }

        return (args, warnings)
    }

    // MARK: - Helpers

    private func buildGenerationResult(from response: HuggingFaceResponsesResponse) throws -> (content: [LanguageModelV3Content], finishReason: LanguageModelV3FinishReason, usage: LanguageModelV3Usage, providerMetadata: SharedV3ProviderMetadata?) {
        var content: [LanguageModelV3Content] = []

        for item in response.outputItems {
            switch item.type {
            case .message:
                guard let message = item.message else { continue }
                let providerMetadata = item.id.map { messageProviderMetadata(itemId: $0) }

                for part in message.content {
                    guard let partType = part.type else { continue }
                    switch partType {
                    case "output_text":
                        if let text = part.text {
                            content.append(.text(LanguageModelV3Text(text: text, providerMetadata: providerMetadata)))
                        }
                        if let annotations = part.annotations {
                            for annotation in annotations {
                                guard let url = annotation.url else { continue }
                                content.append(.source(.url(
                                    id: nextId(),
                                    url: url,
                                    title: annotation.title,
                                    providerMetadata: providerMetadata
                                )))
                            }
                        }
                    default:
                        continue
                    }
                }

            case .mcpCall:
                guard let call = item.mcpCall else { continue }
                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: call.id,
                    toolName: call.name,
                    input: call.arguments,
                    providerExecuted: true,
                    providerMetadata: nil
                )))
                if let output = call.output {
                    let resultValue = decodeJSONString(output) ?? .string(output)
                    content.append(.toolResult(LanguageModelV3ToolResult(
                        toolCallId: call.id,
                        toolName: call.name,
                        result: resultValue,
                        providerExecuted: true
                    )))
                }

            case .mcpListTools:
                guard let tools = item.mcpListTools else { continue }
                let inputJSON = encodeJSONString(.object(["server_label": .string(tools.serverLabel)])) ?? "{}"
                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: tools.id,
                    toolName: "list_tools",
                    input: inputJSON,
                    providerExecuted: true,
                    providerMetadata: nil
                )))
                let resultValue: JSONValue = .object([
                    "tools": .array(tools.tools ?? [])
                ])
                content.append(.toolResult(LanguageModelV3ToolResult(
                    toolCallId: tools.id,
                    toolName: "list_tools",
                    result: resultValue,
                    providerExecuted: true
                )))

            case .functionCall:
                guard let function = item.functionCall else { continue }
                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: function.callId,
                    toolName: function.name,
                    input: function.arguments,
                    providerExecuted: nil,
                    providerMetadata: nil
                )))
                if let output = function.output {
                    let resultValue = decodeJSONString(output) ?? .string(output)
                    content.append(.toolResult(LanguageModelV3ToolResult(
                        toolCallId: function.callId,
                        toolName: function.name,
                        result: resultValue,
                        providerExecuted: nil
                    )))
                }

            case .unknown:
                continue
            }
        }

        let usage = response.usage.map { usage in
            LanguageModelV3Usage(
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                totalTokens: usage.totalTokens,
                reasoningTokens: usage.outputTokensDetails?.reasoningTokens,
                cachedInputTokens: usage.inputTokensDetails?.cachedTokens
            )
        } ?? LanguageModelV3Usage()

        let finishReason = mapHuggingFaceResponsesFinishReason(response.incompleteDetails?.reason ?? "stop")
        let providerMetadata = responseProviderMetadata(responseId: response.id)

        return (content, finishReason, usage, providerMetadata)
    }

    private func handleStreamChunk(
        _ chunk: HuggingFaceResponsesChunk,
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation,
        finishReason: inout LanguageModelV3FinishReason,
        usage: inout LanguageModelV3Usage,
        responseId: inout String?
    ) throws {
        switch chunk {
        case .responseCreated(let created):
            responseId = created.response.id
            continuation.yield(.responseMetadata(
                id: created.response.id,
                modelId: created.response.model,
                timestamp: Date(timeIntervalSince1970: created.response.createdAt)
            ))

        case .responseOutputItemAdded(let added):
            switch added.item.type {
            case .message:
                if let id = added.item.id {
                    continuation.yield(.textStart(id: id, providerMetadata: messageProviderMetadata(itemId: id)))
                }
                if let message = added.item.message {
                    for part in message.content {
                        guard let annotations = part.annotations, let id = added.item.id else { continue }
                        for annotation in annotations {
                            guard let url = annotation.url else { continue }
                            continuation.yield(.source(.url(
                                id: nextId(),
                                url: url,
                                title: annotation.title,
                                providerMetadata: messageProviderMetadata(itemId: id)
                            )))
                        }
                    }
                }

            case .mcpCall:
                guard let call = added.item.mcpCall else { return }
                continuation.yield(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: call.id,
                    toolName: call.name,
                    input: call.arguments,
                    providerExecuted: true,
                    providerMetadata: nil
                )))
                if let output = call.output {
                    let resultValue = decodeJSONString(output) ?? .string(output)
                    continuation.yield(.toolResult(LanguageModelV3ToolResult(
                        toolCallId: call.id,
                        toolName: call.name,
                        result: resultValue,
                        providerExecuted: true
                    )))
                }

            case .mcpListTools:
                guard let tools = added.item.mcpListTools else { return }
                let inputJSON = encodeJSONString(.object(["server_label": .string(tools.serverLabel)])) ?? "{}"
                continuation.yield(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: tools.id,
                    toolName: "list_tools",
                    input: inputJSON,
                    providerExecuted: true,
                    providerMetadata: nil
                )))
                let resultValue: JSONValue = .object([
                    "tools": .array(tools.tools ?? [])
                ])
                continuation.yield(.toolResult(LanguageModelV3ToolResult(
                    toolCallId: tools.id,
                    toolName: "list_tools",
                    result: resultValue,
                    providerExecuted: true
                )))

            case .functionCall:
                guard let function = added.item.functionCall else { return }
                continuation.yield(.toolInputStart(
                    id: function.callId,
                    toolName: function.name,
                    providerMetadata: nil,
                    providerExecuted: nil,
                    dynamic: nil,
                    title: nil
                ))

            case .unknown:
                return
            }

        case .responseOutputItemDone(let done):
            switch done.item.type {
            case .message:
                if let id = done.item.id {
                    continuation.yield(.textEnd(id: id, providerMetadata: messageProviderMetadata(itemId: id)))
                }
            case .functionCall:
                guard let function = done.item.functionCall else { return }
                continuation.yield(.toolInputEnd(id: function.callId, providerMetadata: nil))
                continuation.yield(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: function.callId,
                    toolName: function.name,
                    input: function.arguments,
                    providerExecuted: nil,
                    providerMetadata: nil
                )))
                if let output = function.output {
                    let resultValue = decodeJSONString(output) ?? .string(output)
                    continuation.yield(.toolResult(LanguageModelV3ToolResult(
                        toolCallId: function.callId,
                        toolName: function.name,
                        result: resultValue,
                        providerExecuted: nil
                    )))
                }
            case .mcpCall, .mcpListTools, .unknown:
                return
            }

        case .textDelta(let delta):
            continuation.yield(.textDelta(id: delta.itemId, delta: delta.delta, providerMetadata: messageProviderMetadata(itemId: delta.itemId)))

        case .responseCompleted(let completed):
            responseId = completed.response.id
            finishReason = mapHuggingFaceResponsesFinishReason(completed.response.incompleteDetails?.reason ?? "stop")
            if let usagePayload = completed.response.usage {
                usage = LanguageModelV3Usage(
                    inputTokens: usagePayload.inputTokens,
                    outputTokens: usagePayload.outputTokens,
                    totalTokens: usagePayload.totalTokens,
                    reasoningTokens: usagePayload.outputTokensDetails?.reasoningTokens,
                    cachedInputTokens: usagePayload.inputTokensDetails?.cachedTokens
                )
            }

        case .other:
            return
        }
    }

    private func messageProviderMetadata(itemId: String) -> SharedV3ProviderMetadata {
        ["huggingface": ["itemId": .string(itemId)]]
    }

    private func responseProviderMetadata(responseId: String?) -> SharedV3ProviderMetadata? {
        guard let responseId else { return nil }
        return ["huggingface": ["responseId": .string(responseId)]]
    }

    private func nextId() -> String {
        config.generateId?() ?? generateID()
    }

    private func encodeJSONString(_ value: JSONValue) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeJSONString(_ string: String) -> JSONValue? {
        guard let data = string.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }
        return try? jsonValue(from: jsonObject)
    }
}

// MARK: - Schemas

private let huggingfaceResponsesResponseSchema = FlexibleSchema(
    Schema<HuggingFaceResponsesResponse>.codable(
        HuggingFaceResponsesResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let huggingfaceResponsesChunkSchema = FlexibleSchema(
    Schema<HuggingFaceResponsesChunk>.codable(
        HuggingFaceResponsesChunk.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

// MARK: - Response Types

private struct HuggingFaceResponsesResponse: Decodable {
    struct ErrorPayload: Decodable {
        let message: String
        let type: String?
        let code: String?
    }

    struct Usage: Decodable {
        struct OutputTokensDetails: Decodable {
            let reasoningTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        struct InputTokensDetails: Decodable {
            let cachedTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }

        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?
        let outputTokensDetails: OutputTokensDetails?
        let inputTokensDetails: InputTokensDetails?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
            case outputTokensDetails = "output_tokens_details"
            case inputTokensDetails = "input_tokens_details"
        }
    }

    struct IncompleteDetails: Decodable {
        let reason: String?

        private enum CodingKeys: String, CodingKey {
            case reason
        }
    }

    let id: String
    let model: String
    let object: String
    let createdAt: Double
    let status: String
    let error: ErrorPayload?
    let usage: Usage?
    let incompleteDetails: IncompleteDetails?
    let output: [HuggingFaceResponsesOutputItem]

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case object
        case createdAt = "created_at"
        case status
        case error
        case usage
        case incompleteDetails = "incomplete_details"
        case output
    }

    var outputItems: [HuggingFaceResponsesOutputItem] { output }
}

private struct HuggingFaceResponsesMessageContent: Decodable {
    let type: String?
    let text: String?
    let annotations: [Annotation]?

    struct Annotation: Decodable {
        let url: String?
        let title: String?
    }
}

private enum HuggingFaceResponsesOutputItemType: String, Decodable {
    case message
    case mcpListTools = "mcp_list_tools"
    case mcpCall = "mcp_call"
    case functionCall = "function_call"
    case unknown
}

private struct HuggingFaceResponsesOutputItem: Decodable {
    struct Message: Decodable {
        let content: [HuggingFaceResponsesMessageContent]
    }

    struct MCPCall: Decodable {
        let id: String
        let serverLabel: String
        let name: String
        let arguments: String
        let output: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case serverLabel = "server_label"
            case name
            case arguments
            case output
        }
    }

    struct MCPListTools: Decodable {
        let id: String
        let serverLabel: String
        let tools: [JSONValue]?

        private enum CodingKeys: String, CodingKey {
            case id
            case serverLabel = "server_label"
            case tools
        }
    }

    struct FunctionCall: Decodable {
        let id: String
        let callId: String
        let name: String
        let arguments: String
        let output: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case callId = "call_id"
            case name
            case arguments
            case output
        }
    }

    let type: HuggingFaceResponsesOutputItemType
    let id: String?
    let message: Message?
    let mcpCall: MCPCall?
    let mcpListTools: MCPListTools?
    let functionCall: FunctionCall?

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case content
        case serverLabel = "server_label"
        case name
        case arguments
        case output
        case tools
        case callId = "call_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(HuggingFaceResponsesOutputItemType.self, forKey: .type) ?? .unknown
        id = try container.decodeIfPresent(String.self, forKey: .id)

        switch type {
        case .message:
            let content = try container.decodeIfPresent([HuggingFaceResponsesMessageContent].self, forKey: .content) ?? []
            message = Message(content: content)
            mcpCall = nil
            mcpListTools = nil
            functionCall = nil
        case .mcpCall:
            mcpCall = try MCPCall(from: decoder)
            message = nil
            mcpListTools = nil
            functionCall = nil
        case .mcpListTools:
            mcpListTools = try MCPListTools(from: decoder)
            message = nil
            mcpCall = nil
            functionCall = nil
        case .functionCall:
            functionCall = try FunctionCall(from: decoder)
            message = nil
            mcpCall = nil
            mcpListTools = nil
        case .unknown:
            message = nil
            mcpCall = nil
            mcpListTools = nil
            functionCall = nil
        }
    }
}

// MARK: - Streaming Chunk Types

private enum HuggingFaceResponsesChunk: Decodable {
    struct ResponseCreated: Decodable {
        struct ResponseMetadata: Decodable {
            let id: String
            let object: String
            let createdAt: Double
            let status: String
            let model: String

            private enum CodingKeys: String, CodingKey {
                case id
                case object
                case createdAt = "created_at"
                case status
                case model
            }
        }

        let response: ResponseMetadata
    }

    struct ResponseOutputItemAdded: Decodable {
        let outputIndex: Int
        let item: HuggingFaceResponsesOutputItem

        private enum CodingKeys: String, CodingKey {
            case outputIndex = "output_index"
            case item
        }
    }

    struct ResponseOutputItemDone: Decodable {
        let outputIndex: Int
        let item: HuggingFaceResponsesOutputItem

        private enum CodingKeys: String, CodingKey {
            case outputIndex = "output_index"
            case item
        }
    }

    struct TextDelta: Decodable {
        let itemId: String
        let outputIndex: Int
        let contentIndex: Int
        let delta: String

        private enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case outputIndex = "output_index"
            case contentIndex = "content_index"
            case delta
        }
    }

    struct ResponseCompleted: Decodable {
        let response: HuggingFaceResponsesResponse
    }

    case responseCreated(ResponseCreated)
    case responseOutputItemAdded(ResponseOutputItemAdded)
    case responseOutputItemDone(ResponseOutputItemDone)
    case textDelta(TextDelta)
    case responseCompleted(ResponseCompleted)
    case other

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "response.created":
            self = .responseCreated(try ResponseCreated(from: decoder))
        case "response.output_item.added":
            self = .responseOutputItemAdded(try ResponseOutputItemAdded(from: decoder))
        case "response.output_item.done":
            self = .responseOutputItemDone(try ResponseOutputItemDone(from: decoder))
        case "response.output_text.delta":
            self = .textDelta(try TextDelta(from: decoder))
        case "response.completed":
            self = .responseCompleted(try ResponseCompleted(from: decoder))
        default:
            self = .other
        }
    }
}

private extension ParseJSONResult where Output == HuggingFaceResponsesChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}
