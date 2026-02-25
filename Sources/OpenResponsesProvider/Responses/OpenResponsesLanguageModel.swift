import AISDKProvider
import AISDKProviderUtils
import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/open-responses/src/responses/open-responses-language-model.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

private let openResponsesAnyJSONValueSchema = FlexibleSchema(
    Schema<JSONValue>(
        jsonSchemaResolver: { .bool(true) },
        validator: nil
    )
)

private let openResponsesHTTPSURLRegex: NSRegularExpression = {
    // Safe to use try! for a static, well-formed pattern
    try! NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
}()

public final class OpenResponsesLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"

    public let modelId: String
    private let config: OpenResponsesConfig

    public init(modelId: String, config: OpenResponsesConfig) {
        self.modelId = modelId
        self.config = config
    }

    public var provider: String { config.provider }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            [
                "image/*": [openResponsesHTTPSURLRegex]
            ]
        }
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
    }

    private func getArgs(_ options: LanguageModelV3CallOptions) async -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        if options.stopSequences != nil {
            warnings.append(.unsupported(feature: "stopSequences", details: nil))
        }
        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }
        if options.seed != nil {
            warnings.append(.unsupported(feature: "seed", details: nil))
        }

        let inputResult = await convertToOpenResponsesInput(prompt: options.prompt)
        warnings.append(contentsOf: inputResult.warnings)

        // Convert function tools to the Open Responses format.
        let functionTools: [JSONValue] = options.tools?
            .compactMap { tool in
                guard case .function(let functionTool) = tool else { return nil }

                var payload: [String: JSONValue] = [
                    "type": .string("function"),
                    "name": .string(functionTool.name),
                    "parameters": functionTool.inputSchema
                ]

                if let description = functionTool.description {
                    payload["description"] = .string(description)
                }

                if let strict = functionTool.strict {
                    payload["strict"] = .bool(strict)
                }

                return .object(payload)
            } ?? []

        // Convert tool choice to the Open Responses format.
        let convertedToolChoice: JSONValue? = {
            guard let toolChoice = options.toolChoice else { return nil }

            switch toolChoice {
            case .tool(let toolName):
                return .object([
                    "type": .string("function"),
                    "name": .string(toolName)
                ])
            case .auto:
                return .string("auto")
            case .none:
                return .string("none")
            case .required:
                return .string("required")
            }
        }()

        let textFormat: JSONValue? = {
            guard case let .json(schema, name, description) = options.responseFormat else { return nil }

            var payload: [String: JSONValue] = [
                "type": .string("json_schema")
            ]

            if let schema {
                payload["name"] = .string(name ?? "response")
                if let description {
                    payload["description"] = .string(description)
                }
                payload["schema"] = schema
                payload["strict"] = .bool(true)
            }

            return .object(payload)
        }()

        var body: [String: JSONValue] = [
            "model": .string(modelId),
            "input": .array(inputResult.input)
        ]

        if let instructions = inputResult.instructions {
            body["instructions"] = .string(instructions)
        }

        if let maxOutputTokens = options.maxOutputTokens {
            body["max_output_tokens"] = .number(Double(maxOutputTokens))
        }

        if let temperature = options.temperature {
            body["temperature"] = .number(temperature)
        }

        if let topP = options.topP {
            body["top_p"] = .number(topP)
        }

        if let presencePenalty = options.presencePenalty {
            body["presence_penalty"] = .number(presencePenalty)
        }

        if let frequencyPenalty = options.frequencyPenalty {
            body["frequency_penalty"] = .number(frequencyPenalty)
        }

        if !functionTools.isEmpty {
            body["tools"] = .array(functionTools)
        }

        if let convertedToolChoice {
            body["tool_choice"] = convertedToolChoice
        }

        if let textFormat {
            body["text"] = .object([
                "format": textFormat
            ])
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = await getArgs(options)

        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url,
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: openResponsesFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openResponsesAnyJSONValueSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let json = response.value
        let dict = json.objectValue ?? [:]

        let content = parseContent(from: dict)
        let hasToolCalls = content.contains { if case .toolCall = $0 { return true } else { return false } }

        let reason = dict["incomplete_details"]?.objectValue?["reason"]?.stringValue
        let finishReason = LanguageModelV3FinishReason(
            unified: mapOpenResponsesFinishReason(finishReason: reason, hasToolCalls: hasToolCalls),
            raw: reason
        )

        let usage = mapGenerateUsage(from: dict["usage"])

        let responseId = dict["id"]?.stringValue
        let responseModel = dict["model"]?.stringValue
        let createdAt = dict["created_at"]?.doubleValue
        let timestamp = createdAt.map { Date(timeIntervalSince1970: $0) }

        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: nil,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3ResponseInfo(
                id: responseId,
                timestamp: timestamp,
                modelId: responseModel,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = await getArgs(options)

        var streamBody = prepared.body
        streamBody["stream"] = .bool(true)

        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let eventStream = try await postJsonToAPI(
            url: config.url,
            headers: headers,
            body: JSONValue.object(streamBody),
            failedResponseHandler: openResponsesFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openResponsesAnyJSONValueSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var usage = LanguageModelV3Usage()
                var isActiveReasoning = false
                var hasToolCalls = false
                var finishReason = LanguageModelV3FinishReason(unified: .other, raw: nil)
                var toolCallsByItemId: [String: ToolCallState] = [:]

                func updateUsage(_ responseUsage: JSONValue?) {
                    guard let responseUsage, responseUsage != .null else { return }
                    usage = mapGenerateUsage(from: responseUsage)
                }

                do {
                    for try await parseResult in eventStream.value {
                        if options.includeRawChunks == true, let raw = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .string(String(describing: error))))

                        case .success(let chunk, _):
                            guard let chunkObject = chunk.objectValue,
                                  let type = chunkObject["type"]?.stringValue else {
                                continue
                            }

                            // Tool call events (single-shot tool-call when complete)
                            if type == "response.output_item.added",
                               let item = chunkObject["item"]?.objectValue,
                               item["type"]?.stringValue == "function_call",
                               let itemId = item["id"]?.stringValue {
                                toolCallsByItemId[itemId] = ToolCallState(
                                    toolName: item["name"]?.stringValue,
                                    toolCallId: item["call_id"]?.stringValue,
                                    arguments: item["arguments"]?.stringValue
                                )
                            } else if type == "response.function_call_arguments.delta" {
                                let itemId = chunkObject["item_id"]?.stringValue
                                let delta = chunkObject["delta"]?.stringValue
                                guard let itemId, let delta else { continue }
                                var state = toolCallsByItemId[itemId] ?? ToolCallState()
                                state.arguments = (state.arguments ?? "") + delta
                                toolCallsByItemId[itemId] = state
                            } else if type == "response.function_call_arguments.done" {
                                let itemId = chunkObject["item_id"]?.stringValue
                                let arguments = chunkObject["arguments"]?.stringValue
                                guard let itemId, let arguments else { continue }
                                var state = toolCallsByItemId[itemId] ?? ToolCallState()
                                state.arguments = arguments
                                toolCallsByItemId[itemId] = state
                            } else if type == "response.output_item.done",
                                      let item = chunkObject["item"]?.objectValue,
                                      item["type"]?.stringValue == "function_call",
                                      let itemId = item["id"]?.stringValue {
                                let state = toolCallsByItemId[itemId]
                                let toolName = state?.toolName ?? item["name"]?.stringValue
                                let toolCallId = state?.toolCallId ?? item["call_id"]?.stringValue
                                let input = state?.arguments ?? item["arguments"]?.stringValue ?? ""

                                if let toolName, let toolCallId {
                                    continuation.yield(.toolCall(LanguageModelV3ToolCall(
                                        toolCallId: toolCallId,
                                        toolName: toolName,
                                        input: input,
                                        providerExecuted: nil,
                                        dynamic: nil,
                                        providerMetadata: nil
                                    )))
                                    hasToolCalls = true
                                }

                                toolCallsByItemId.removeValue(forKey: itemId)
                            }

                            // Reasoning events (note: response.reasoning_text.delta is an LM Studio extension, not in official spec)
                            else if type == "response.output_item.added",
                                    let item = chunkObject["item"]?.objectValue,
                                    item["type"]?.stringValue == "reasoning",
                                    let itemId = item["id"]?.stringValue {
                                continuation.yield(.reasoningStart(id: itemId, providerMetadata: nil))
                                isActiveReasoning = true
                            } else if type == "response.reasoning_text.delta" {
                                let itemId = chunkObject["item_id"]?.stringValue
                                let delta = chunkObject["delta"]?.stringValue
                                guard let itemId, let delta else { continue }
                                continuation.yield(.reasoningDelta(id: itemId, delta: delta, providerMetadata: nil))
                            } else if type == "response.output_item.done",
                                      let item = chunkObject["item"]?.objectValue,
                                      item["type"]?.stringValue == "reasoning",
                                      let itemId = item["id"]?.stringValue {
                                continuation.yield(.reasoningEnd(id: itemId, providerMetadata: nil))
                                isActiveReasoning = false
                            }

                            // Text events
                            else if type == "response.output_item.added",
                                    let item = chunkObject["item"]?.objectValue,
                                    item["type"]?.stringValue == "message",
                                    let itemId = item["id"]?.stringValue {
                                continuation.yield(.textStart(id: itemId, providerMetadata: nil))
                            } else if type == "response.output_text.delta" {
                                let itemId = chunkObject["item_id"]?.stringValue
                                let delta = chunkObject["delta"]?.stringValue
                                guard let itemId, let delta else { continue }
                                continuation.yield(.textDelta(id: itemId, delta: delta, providerMetadata: nil))
                            } else if type == "response.output_item.done",
                                      let item = chunkObject["item"]?.objectValue,
                                      item["type"]?.stringValue == "message",
                                      let itemId = item["id"]?.stringValue {
                                continuation.yield(.textEnd(id: itemId, providerMetadata: nil))
                            }

                            // Completion / failure
                            else if type == "response.completed" || type == "response.incomplete" {
                                let responseObject = chunkObject["response"]?.objectValue ?? [:]
                                let reason = responseObject["incomplete_details"]?.objectValue?["reason"]?.stringValue
                                finishReason = .init(
                                    unified: mapOpenResponsesFinishReason(finishReason: reason, hasToolCalls: hasToolCalls),
                                    raw: reason
                                )
                                updateUsage(responseObject["usage"])
                            } else if type == "response.failed" {
                                let responseObject = chunkObject["response"]?.objectValue ?? [:]
                                let status = responseObject["status"]?.stringValue
                                let errorCode = responseObject["error"]?.objectValue?["code"]?.stringValue
                                finishReason = .init(unified: .error, raw: errorCode ?? status)
                                updateUsage(responseObject["usage"])
                            }
                        }
                    }

                    if isActiveReasoning {
                        continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil))
                    }

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: usage,
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
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3StreamResponseInfo(headers: eventStream.responseHeaders)
        )
    }

    private func parseContent(from response: [String: JSONValue]) -> [LanguageModelV3Content] {
        guard case .array(let output)? = response["output"] else { return [] }

        var content: [LanguageModelV3Content] = []

        for part in output {
            guard case .object(let dict) = part else { continue }
            guard let type = dict["type"]?.stringValue else { continue }

            switch type {
            case "reasoning":
                if case .array(let parts)? = dict["content"] {
                    for item in parts {
                        guard let text = item.objectValue?["text"]?.stringValue else { continue }
                        content.append(.reasoning(LanguageModelV3Reasoning(text: text)))
                    }
                }

            case "message":
                if case .array(let parts)? = dict["content"] {
                    for item in parts {
                        guard let text = item.objectValue?["text"]?.stringValue else { continue }
                        content.append(.text(LanguageModelV3Text(text: text)))
                    }
                }

            case "function_call":
                let toolCallId = dict["call_id"]?.stringValue
                let toolName = dict["name"]?.stringValue
                let arguments = dict["arguments"]?.stringValue

                if let toolCallId, let toolName, let arguments {
                    content.append(.toolCall(LanguageModelV3ToolCall(
                        toolCallId: toolCallId,
                        toolName: toolName,
                        input: arguments,
                        providerExecuted: nil,
                        dynamic: nil,
                        providerMetadata: nil
                    )))
                }

            default:
                continue
            }
        }

        return content
    }

    private func mapGenerateUsage(from responseUsage: JSONValue?) -> LanguageModelV3Usage {
        guard let responseUsage, responseUsage != .null else {
            // Match upstream: totals undefined but derived token buckets computed with ?? 0.
            return LanguageModelV3Usage(
                inputTokens: .init(total: nil, noCache: 0, cacheRead: nil, cacheWrite: nil),
                outputTokens: .init(total: nil, text: 0, reasoning: nil),
                raw: nil
            )
        }

        guard let dict = responseUsage.objectValue else {
            return LanguageModelV3Usage(raw: responseUsage)
        }

        let inputTokens = dict["input_tokens"]?.intValue
        let cachedInputTokens = dict["input_tokens_details"]?.objectValue?["cached_tokens"]?.intValue
        let outputTokens = dict["output_tokens"]?.intValue
        let reasoningTokens = dict["output_tokens_details"]?.objectValue?["reasoning_tokens"]?.intValue

        return LanguageModelV3Usage(
            inputTokens: .init(
                total: inputTokens,
                noCache: (inputTokens ?? 0) - (cachedInputTokens ?? 0),
                cacheRead: cachedInputTokens,
                cacheWrite: nil
            ),
            outputTokens: .init(
                total: outputTokens,
                text: (outputTokens ?? 0) - (reasoningTokens ?? 0),
                reasoning: reasoningTokens
            ),
            raw: responseUsage
        )
    }

    private struct ToolCallState {
        var toolName: String?
        var toolCallId: String?
        var arguments: String?
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let dict) = self else { return nil }
        return dict
    }

    var stringValue: String? {
        guard case .string(let s) = self else { return nil }
        return s
    }

    var doubleValue: Double? {
        guard case .number(let d) = self else { return nil }
        return d
    }

    var intValue: Int? {
        guard case .number(let d) = self else { return nil }
        return Int(d)
    }
}

private extension ParseJSONResult {
    var rawJSONValue: JSONValue? {
        let raw: Any?
        switch self {
        case .success(_, let rawValue):
            raw = rawValue
        case .failure(_, let rawValue):
            raw = rawValue
        }

        guard let raw else { return nil }
        return try? jsonValue(from: raw)
    }
}
