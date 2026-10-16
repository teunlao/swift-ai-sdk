import Foundation
import AISDKProvider
import AISDKProviderUtils

/// xAI Responses language model implementation.
/// Mirrors `packages/xai/src/responses/xai-responses-language-model.ts`.
public final class XAIResponsesLanguageModel: LanguageModelV4 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let generateId: @Sendable () -> String
        let fetch: FetchFunction?
    }

    fileprivate struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
        let webSearchToolName: String?
        let xSearchToolName: String?
        let codeExecutionToolName: String?
        let mcpToolName: String?
        let fileSearchToolName: String?
        let imageGenerationToolName: String?
    }

    private let modelIdentifier: XAIResponsesModelId
    private let config: Config

    private let httpRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
    }()

    init(modelId: XAIResponsesModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public let specificationVersion: String = "v4"
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            ["image/*": [httpRegex], "application/pdf": [httpRegex], "text/*": [httpRegex]]
        }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options: options)

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/responses",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: xaiResponsesResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        var content: [LanguageModelV4Content] = []
        var hasFunctionCall = false

        let webSearchSubTools: Set<String> = ["web_search", "web_search_with_snippets", "browse_page"]
        let xSearchSubTools: Set<String> = ["x_user_search", "x_keyword_search", "x_semantic_search", "x_thread_fetch"]

        for item in response.value.output {
            switch item {
            case .toolCall(let part):
                if part.type == "image_generation_call" {
                    let toolName = prepared.imageGenerationToolName ?? "image_generation"
                    content.append(.toolCall(.init(toolCallId: part.id, toolName: toolName, input: "{}", providerExecuted: true)))
                    content.append(.toolResult(imageGenerationResult(part, toolName: toolName)))
                    continue
                }
                if part.type == "file_search_call" {
                    let toolName = prepared.fileSearchToolName ?? "file_search"

                    content.append(.toolCall(LanguageModelV4ToolCall(
                        toolCallId: part.id,
                        toolName: toolName,
                        input: "",
                        providerExecuted: true
                    )))

                    let queries = part.queries ?? []
                    let results: JSONValue
                    if let decoded = part.results {
                        results = .array(decoded.map { result in
                            .object([
                                "fileId": .string(result.fileId),
                                "filename": .string(result.filename),
                                "score": .number(result.score),
                                "text": .string(result.text)
                            ])
                        })
                    } else {
                        results = .null
                    }

                    content.append(.toolResult(LanguageModelV4ToolResult(
                        toolCallId: part.id,
                        toolName: toolName,
                        result: .object([
                            "queries": .array(queries.map(JSONValue.string)),
                            "results": results
                        ])
                    )))

                    continue
                }

                if [
                    "web_search_call",
                    "x_search_call",
                    "code_interpreter_call",
                    "code_execution_call",
                    "view_image_call",
                    "view_x_video_call",
                    "custom_tool_call"
                ].contains(part.type) {
                    let toolCallId = part.id

                    var toolName = part.name ?? ""
                    if webSearchSubTools.contains(part.name ?? "") || part.type == "web_search_call" {
                        toolName = prepared.webSearchToolName ?? "web_search"
                    } else if xSearchSubTools.contains(part.name ?? "") || part.type == "x_search_call" {
                        toolName = prepared.xSearchToolName ?? "x_search"
                    } else if part.name == "code_execution" || part.type == "code_interpreter_call" || part.type == "code_execution_call" {
                        toolName = prepared.codeExecutionToolName ?? "code_execution"
                    }

                    let toolInput: String
                    if part.type == "custom_tool_call" {
                        toolInput = part.input ?? ""
                    } else {
                        toolInput = part.arguments ?? ""
                    }

                    content.append(.toolCall(LanguageModelV4ToolCall(
                        toolCallId: toolCallId,
                        toolName: toolName,
                        input: toolInput,
                        providerExecuted: true
                    )))
                    if part.type == "web_search_call" {
                        content.append(.toolResult(.init(toolCallId: part.id, toolName: toolName, result: mapWebSearchAction(part.action))))
                    }

                    continue
                }

            case .mcpCall(let part):
                let toolCallId = part.id

                var toolName = part.name ?? ""
                toolName = prepared.mcpToolName ?? (part.name ?? "mcp")

                let toolInput = part.arguments ?? ""

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    input: toolInput,
                    providerExecuted: true
                )))

                continue

            case .message(let part):
                for contentPart in part.content {
                    if let text = contentPart.text, !text.isEmpty {
                        content.append(.text(LanguageModelV4Text(text: text)))
                    }

                    if let annotations = contentPart.annotations {
                        for annotation in annotations {
                            guard case .urlCitation(let url, let title) = annotation else { continue }
                            content.append(.source(.url(
                                id: config.generateId(),
                                url: url,
                                title: title ?? url,
                                providerMetadata: nil
                            )))
                        }
                    }
                }

            case .functionCall(let part):
                hasFunctionCall = true
                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: part.callId,
                    toolName: part.name,
                    input: part.arguments
                )))

            case .reasoning(let part):
                let texts = part.summary.isEmpty ? (part.content ?? []) : part.summary
                let reasoningText = texts.map(\.text).filter { !$0.isEmpty }.joined()
                guard !reasoningText.isEmpty || part.encryptedContent?.isEmpty == false else { break }

                var providerMetadata: SharedV4ProviderMetadata? = nil
                if !part.id.isEmpty || (part.encryptedContent?.isEmpty == false) {
                    var xai: [String: JSONValue] = [:]
                    if !part.id.isEmpty {
                        xai["itemId"] = .string(part.id)
                    }
                    if let encrypted = part.encryptedContent, !encrypted.isEmpty {
                        xai["reasoningEncryptedContent"] = .string(encrypted)
                    }
                    providerMetadata = ["xai": xai]
                }

                content.append(.reasoning(LanguageModelV4Reasoning(
                    text: reasoningText,
                    providerMetadata: providerMetadata
                )))
            }
        }

        let usage: LanguageModelV4Usage
        if let usageData = response.value.usage {
            usage = convertXaiResponsesUsage(usageData)
        } else {
            usage = LanguageModelV4Usage(
                inputTokens: .init(total: 0, noCache: 0, cacheRead: 0, cacheWrite: 0),
                outputTokens: .init(total: 0, text: 0, reasoning: 0)
            )
        }

        let finishReason = LanguageModelV4FinishReason(
            unified: hasFunctionCall ? .toolCalls : mapXaiResponsesFinishReason(response.value.status),
            raw: response.value.status
        )

        let metadata = xaiResponseMetadata(
            id: response.value.id,
            model: response.value.model,
            created: response.value.createdAt
        )

        return LanguageModelV4GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: responseProviderMetadata(cost: response.value.usage?.costInUsdTicks, tier: response.value.serviceTier, cacheKey: response.value.promptCacheKey, safety: response.value.safetyIdentifier),
            request: LanguageModelV4RequestInfo(body: prepared.body),
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

        var streamBody = prepared.body
        streamBody["stream"] = .bool(true)

        let streamResponse = try await postJsonToAPI(
            url: "\(config.baseURL)/responses",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(streamBody),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: xaiResponsesChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            let producer = Task {
                var hasFunctionCall = false
                var providerMetadata: SharedV4ProviderMetadata?
                var costInUsdTicks: Double?
                var finishReason = LanguageModelV4FinishReason(unified: .other, raw: nil)
                var usage: LanguageModelV4Usage? = nil
                var isFirstChunk = true
                var contentBlocks: [String] = []
                var seenToolCalls: Set<String> = []
                var ongoingToolCalls: [Int: (toolName: String, toolCallId: String)?] = [:]
                var activeReasoning: Set<String> = []

                let webSearchSubTools: Set<String> = ["web_search", "web_search_with_snippets", "browse_page"]
                let xSearchSubTools: Set<String> = ["x_user_search", "x_keyword_search", "x_semantic_search", "x_thread_fetch"]

                do {
                    for try await parseResult in streamResponse.value {
                        if options.includeRawChunks == true, let raw = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            continuation.yield(.error(error: .error(error)))
                            continue

                        case .success(let event, _):
                            switch event {
                            case .responseCreated(let response), .responseInProgress(let response):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let metadata = xaiResponseMetadata(id: response.id, model: response.model, created: response.createdAt)
                                    continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                                }

                            case .responseReasoningSummaryPartAdded(let itemId, _, _, _):
                                let blockId = "reasoning-\(itemId)"
                                if activeReasoning.insert(itemId).inserted {
                                    continuation.yield(.reasoningStart(id: blockId, providerMetadata: ["xai": ["itemId": .string(itemId)]]))
                                }

                            case .responseReasoningSummaryTextDelta(let itemId, _, _, let delta):
                                let blockId = "reasoning-\(itemId)"
                                continuation.yield(.reasoningDelta(
                                    id: blockId,
                                    delta: delta,
                                    providerMetadata: ["xai": ["itemId": .string(itemId)]]
                                ))

                            case .responseReasoningSummaryTextDone:
                                break

                            case .responseReasoningTextDelta(let itemId, _, _, let delta):
                                let blockId = "reasoning-\(itemId)"
                                if !activeReasoning.contains(itemId) {
                                    activeReasoning.insert(itemId)
                                    continuation.yield(.reasoningStart(
                                        id: blockId,
                                        providerMetadata: ["xai": ["itemId": .string(itemId)]]
                                    ))
                                }
                                continuation.yield(.reasoningDelta(
                                    id: blockId,
                                    delta: delta,
                                    providerMetadata: ["xai": ["itemId": .string(itemId)]]
                                ))

                            case .responseReasoningTextDone:
                                break

                            case .responseOutputTextDelta(let itemId, _, _, let delta):
                                let blockId = "text-\(itemId)"
                                if !contentBlocks.contains(blockId) {
                                    contentBlocks.append(blockId)
                                    continuation.yield(.textStart(id: blockId, providerMetadata: nil))
                                }
                                continuation.yield(.textDelta(id: blockId, delta: delta, providerMetadata: nil))

                            case .responseOutputTextDone(_, _, _, _, let annotations):
                                if let annotations {
                                    for annotation in annotations {
                                        guard case .urlCitation(let url, let title) = annotation else { continue }
                                        continuation.yield(.source(.url(
                                            id: config.generateId(),
                                            url: url,
                                            title: title ?? url,
                                            providerMetadata: nil
                                        )))
                                    }
                                }

                            case .responseOutputTextAnnotationAdded(_, _, _, _, let annotation):
                                guard case .urlCitation(let url, let title) = annotation else { break }
                                continuation.yield(.source(.url(
                                    id: config.generateId(),
                                    url: url,
                                    title: title ?? url,
                                    providerMetadata: nil
                                )))

                            case .responseDone(let response), .responseCompleted(let response):
                                if let usageInfo = response.usage {
                                    usage = convertXaiResponsesUsage(usageInfo)
                                    costInUsdTicks = usageInfo.costInUsdTicks
                                }
                                finishReason = .init(unified: hasFunctionCall ? .toolCalls : mapXaiResponsesFinishReason(response.status), raw: response.status)
                                providerMetadata = responseProviderMetadata(cost: costInUsdTicks, tier: response.serviceTier, cacheKey: response.promptCacheKey, safety: response.safetyIdentifier)

                            case .responseIncomplete(let response):
                                if let usageInfo = response.usage {
                                    usage = convertXaiResponsesUsage(usageInfo)
                                    costInUsdTicks = usageInfo.costInUsdTicks
                                }
                                let reason = response.incompleteDetails?.reason
                                finishReason = .init(unified: reason.map(mapXaiResponsesFinishReason) ?? .other, raw: reason ?? "incomplete")
                                providerMetadata = responseProviderMetadata(cost: costInUsdTicks, tier: response.serviceTier, cacheKey: response.promptCacheKey, safety: response.safetyIdentifier)

                            case .responseFailed(let response):
                                if let usageInfo = response.usage { usage = convertXaiResponsesUsage(usageInfo) }
                                let reason = response.incompleteDetails?.reason
                                finishReason = .init(unified: reason.map(mapXaiResponsesFinishReason) ?? .error, raw: reason ?? "error")
                                if let error = response.error {
                                    continuation.yield(.error(error: .providerStreamError(xaiStreamError(message: error.message, code: error.code, eventType: "response.failed", data: parseResult.rawJSONValue ?? .null))))
                                }

                            case .error(let code, let message):
                                continuation.yield(.error(error: .providerStreamError(xaiStreamError(message: message, code: code, eventType: "error", data: parseResult.rawJSONValue ?? .null))))

                            case .responseImageGenerationStatus(_, let itemId, _):
                                if seenToolCalls.insert(itemId).inserted {
                                    emitImageGenerationCall(id: itemId, toolName: prepared.imageGenerationToolName ?? "image_generation", continuation: continuation)
                                }

                            case .responseCustomToolCallInputDelta, .responseCustomToolCallInputDone:
                                break

                            case .responseFunctionCallArgumentsDelta(_, let outputIndex, let delta):
                                if let tracked = ongoingToolCalls[outputIndex] ?? nil {
                                    continuation.yield(.toolInputDelta(id: tracked.toolCallId, delta: delta, providerMetadata: nil))
                                }

                            case .responseFunctionCallArgumentsDone:
                                break

                            case .responseOutputItemAdded(let item, let outputIndex):
                                try await handleOutputItem(
                                    phase: OutputItemPhase.added,
                                    item: item,
                                    outputIndex: outputIndex,
                                    continuation: continuation,
                                    contentBlocks: &contentBlocks,
                                    seenToolCalls: &seenToolCalls,
                                    ongoingToolCalls: &ongoingToolCalls,
                                    activeReasoning: &activeReasoning,
                                    webSearchSubTools: webSearchSubTools,
                                    xSearchSubTools: xSearchSubTools,
                                    prepared: prepared,
                                    generateId: config.generateId
                                )

                            case .responseOutputItemDone(let item, let outputIndex):
                                if case .functionCall = item { hasFunctionCall = true }
                                try await handleOutputItem(
                                    phase: OutputItemPhase.done,
                                    item: item,
                                    outputIndex: outputIndex,
                                    continuation: continuation,
                                    contentBlocks: &contentBlocks,
                                    seenToolCalls: &seenToolCalls,
                                    ongoingToolCalls: &ongoingToolCalls,
                                    activeReasoning: &activeReasoning,
                                    webSearchSubTools: webSearchSubTools,
                                    xSearchSubTools: xSearchSubTools,
                                    prepared: prepared,
                                    generateId: config.generateId
                                )

                            default:
                                break
                            }
                        }
                    }

                    for blockId in contentBlocks {
                        continuation.yield(.textEnd(id: blockId, providerMetadata: nil))
                    }

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: usage ?? LanguageModelV4Usage(
                            inputTokens: .init(total: 0, noCache: 0, cacheRead: 0, cacheWrite: 0),
                            outputTokens: .init(total: 0, text: 0, reasoning: 0)
                        ),
                        providerMetadata: providerMetadata
                    ))

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }

        return LanguageModelV4StreamResult(
            stream: stream,
            request: LanguageModelV4RequestInfo(body: streamBody),
            response: LanguageModelV4StreamResponseInfo(headers: streamResponse.responseHeaders)
        )
    }

    // MARK: - Preparation

    private func prepareRequest(options: LanguageModelV4CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV4Warning] = []

        let providerOptions = try await parseProviderOptions(
            provider: "xai",
            providerOptions: options.providerOptions,
            schema: xaiLanguageModelResponsesOptionsSchema
        ) ?? XAILanguageModelResponsesOptions()

        if options.frequencyPenalty != nil { warnings.append(.unsupported(feature: "frequencyPenalty", details: nil)) }
        if options.presencePenalty != nil { warnings.append(.unsupported(feature: "presencePenalty", details: nil)) }
        if options.stopSequences != nil {
            warnings.append(.unsupported(feature: "stopSequences", details: nil))
        }

        let tools = options.tools
        let webSearchToolName = tools?.compactMap { tool -> String? in
            guard case .provider(let providerTool) = tool else { return nil }
            guard providerTool.id == "xai.web_search" else { return nil }
            return providerTool.name
        }.first

        let xSearchToolName = tools?.compactMap { tool -> String? in
            guard case .provider(let providerTool) = tool else { return nil }
            guard providerTool.id == "xai.x_search" else { return nil }
            return providerTool.name
        }.first

        let codeExecutionToolName = tools?.compactMap { tool -> String? in
            guard case .provider(let providerTool) = tool else { return nil }
            guard providerTool.id == "xai.code_execution" else { return nil }
            return providerTool.name
        }.first

        let mcpToolName = tools?.compactMap { tool -> String? in
            guard case .provider(let providerTool) = tool else { return nil }
            guard providerTool.id == "xai.mcp" else { return nil }
            return providerTool.name
        }.first

        let fileSearchToolName = tools?.compactMap { tool -> String? in
            guard case .provider(let providerTool) = tool else { return nil }
            guard providerTool.id == "xai.file_search" else { return nil }
            return providerTool.name
        }.first

        let imageGenerationToolName = tools?.compactMap { tool -> String? in
            guard case .provider(let tool) = tool, tool.id == "xai.image_generation" else { return nil }
            return tool.name
        }.first
        let inputConversion = try await convertToXAIResponsesInput(prompt: options.prompt, store: providerOptions.store ?? true)
        warnings.append(contentsOf: inputConversion.warnings)

        let preparedTools = try await prepareXAIResponsesTools(tools: options.tools, toolChoice: options.toolChoice)
        warnings.append(contentsOf: preparedTools.warnings)

        var includeValues = providerOptions.include

        if providerOptions.store == false {
            if includeValues == nil {
                includeValues = ["reasoning.encrypted_content"]
            } else {
                includeValues?.append("reasoning.encrypted_content")
            }
        }

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "input": .array(inputConversion.input)
        ]

        if let maxTokens = options.maxOutputTokens {
            body["max_output_tokens"] = .number(Double(maxTokens))
        }
        if let temperature = options.temperature {
            body["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            body["top_p"] = .number(topP)
        }
        if let seed = options.seed { body["seed"] = .number(Double(seed)) }
        if let topK = options.topK { body["top_k"] = .number(Double(topK)) }
        if providerOptions.logprobs == true || providerOptions.topLogprobs != nil { body["logprobs"] = .bool(true) }
        if let value = providerOptions.topLogprobs { body["top_logprobs"] = .number(Double(value)) }
        if let value = providerOptions.minP { body["min_p"] = .number(value) }
        if let value = providerOptions.maxTurns { body["max_turns"] = .number(Double(value)) }
        if let value = providerOptions.parallelToolCalls { body["parallel_tool_calls"] = .bool(value) }
        if let value = providerOptions.promptCacheKey { body["prompt_cache_key"] = .string(value) }
        if let value = providerOptions.safetyIdentifier { body["safety_identifier"] = .string(value) }
        if let value = providerOptions.serviceTier { body["service_tier"] = .string(value) }
        if let value = providerOptions.user { body["user"] = .string(value) }

        if let responseFormat = options.responseFormat {
            switch responseFormat {
            case .text:
                break
            case let .json(schema, name, description):
                if let schema {
                    var format: [String: JSONValue] = [
                        "type": .string("json_schema"),
                        "strict": .bool(true),
                        "name": .string(name ?? "response"),
                        "schema": schema
                    ]
                    if let description {
                        format["description"] = .string(description)
                    }
                    body["text"] = .object([
                        "format": .object(format)
                    ])
                } else {
                    body["text"] = .object([
                        "format": .object([
                            "type": .string("json_object")
                        ])
                    ])
                }
            }
        }

        var effort = providerOptions.reasoningEffort?.rawValue
        if effort == nil, let reasoning = options.reasoning, reasoning != .providerDefault {
            if !supportsReasoningEffort(modelId) {
                warnings.append(.unsupported(feature: "reasoning", details: "reasoning \"\(reasoning.rawValue)\" is not supported by this model."))
            } else {
                if reasoning == .none { effort = "none" }
                else {
                    effort = mapReasoningToProviderEffort(reasoning: reasoning, effortMap: [
                        .minimal: "low", .low: "low", .medium: "medium", .high: "high",
                        .xhigh: modelId == "grok-4.6" ? "xhigh" : "high", .max: modelId == "grok-4.6" ? "xhigh" : "high"
                    ], warnings: &warnings)
                }
            }
        }
        if let effort { body["reasoning"] = .object(["effort": .string(effort)]) }

        if providerOptions.store == false {
            body["store"] = .bool(false)
        }

        if let includeValues {
            body["include"] = .array(includeValues.map(JSONValue.string))
        }

        if let previousResponseId = providerOptions.previousResponseId {
            body["previous_response_id"] = .string(previousResponseId)
        }

        if let tools = preparedTools.tools {
            body["tools"] = .array(tools)
        }

        if let toolChoice = preparedTools.toolChoice {
            body["tool_choice"] = toolChoice
        }

        return PreparedRequest(
            body: body,
            warnings: warnings,
            webSearchToolName: webSearchToolName,
            xSearchToolName: xSearchToolName,
            codeExecutionToolName: codeExecutionToolName,
            mcpToolName: mcpToolName,
            fileSearchToolName: fileSearchToolName,
            imageGenerationToolName: imageGenerationToolName
        )
    }
}

private enum OutputItemPhase {
    case added
    case done
}

private func handleOutputItem(
    phase: OutputItemPhase,
    item: XAIResponsesOutputItem,
    outputIndex: Int,
    continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation,
    contentBlocks: inout [String],
    seenToolCalls: inout Set<String>,
    ongoingToolCalls: inout [Int: (toolName: String, toolCallId: String)?],
    activeReasoning: inout Set<String>,
    webSearchSubTools: Set<String>,
    xSearchSubTools: Set<String>,
    prepared: XAIResponsesLanguageModel.PreparedRequest,
    generateId: @Sendable () -> String
) async throws {
    switch item {
    case .reasoning(let part):
        guard phase == .done else { return }

        let blockId = "reasoning-\(part.id)"
        if !activeReasoning.contains(part.id) {
            activeReasoning.insert(part.id)
            continuation.yield(.reasoningStart(
                id: blockId,
                providerMetadata: ["xai": ["itemId": .string(part.id)]]
            ))
        }

        var xaiMetadata: [String: JSONValue] = ["itemId": .string(part.id)]
        if let encrypted = part.encryptedContent, !encrypted.isEmpty {
            xaiMetadata["reasoningEncryptedContent"] = .string(encrypted)
        }

        continuation.yield(.reasoningEnd(
            id: blockId,
            providerMetadata: ["xai": xaiMetadata]
        ))
        activeReasoning.remove(part.id)

    case .toolCall(let part):
        if part.type == "image_generation_call" {
            let name = prepared.imageGenerationToolName ?? "image_generation"
            if seenToolCalls.insert(part.id).inserted { emitImageGenerationCall(id: part.id, toolName: name, continuation: continuation) }
            if phase == .done { continuation.yield(.toolResult(imageGenerationResult(part, toolName: name))) }
            return
        }
        if part.type == "file_search_call" {
            let toolName = prepared.fileSearchToolName ?? "file_search"

            if !seenToolCalls.contains(part.id) {
                seenToolCalls.insert(part.id)

                continuation.yield(.toolInputStart(
                    id: part.id,
                    toolName: toolName,
                    providerMetadata: nil,
                    providerExecuted: nil,
                    dynamic: nil,
                    title: nil
                ))
                continuation.yield(.toolInputDelta(id: part.id, delta: "", providerMetadata: nil))
                continuation.yield(.toolInputEnd(id: part.id, providerMetadata: nil))
                continuation.yield(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: part.id,
                    toolName: toolName,
                    input: "",
                    providerExecuted: true
                )))
            }

            if phase == .done {
                let queries = part.queries ?? []
                let results: JSONValue
                if let decoded = part.results {
                    results = .array(decoded.map { result in
                        .object([
                            "fileId": .string(result.fileId),
                            "filename": .string(result.filename),
                            "score": .number(result.score),
                            "text": .string(result.text)
                        ])
                    })
                } else {
                    results = .null
                }

                continuation.yield(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: part.id,
                    toolName: toolName,
                    result: .object([
                        "queries": .array(queries.map(JSONValue.string)),
                        "results": results
                    ])
                )))
            }

            return
        }

        if [
            "web_search_call",
            "x_search_call",
            "code_interpreter_call",
            "code_execution_call",
            "view_image_call",
            "view_x_video_call",
            "custom_tool_call"
        ].contains(part.type) {
            var toolName = part.name ?? ""
            if webSearchSubTools.contains(part.name ?? "") || part.type == "web_search_call" {
                toolName = prepared.webSearchToolName ?? "web_search"
            } else if xSearchSubTools.contains(part.name ?? "") || part.type == "x_search_call" {
                toolName = prepared.xSearchToolName ?? "x_search"
            } else if part.name == "code_execution" || part.type == "code_interpreter_call" || part.type == "code_execution_call" {
                toolName = prepared.codeExecutionToolName ?? "code_execution"
            }

            let toolInput = part.type == "custom_tool_call" ? (part.input ?? "") : (part.arguments ?? "")

            let shouldEmit = part.type == "custom_tool_call" ? (phase == .done) : !seenToolCalls.contains(part.id)

            if shouldEmit && !seenToolCalls.contains(part.id) {
                seenToolCalls.insert(part.id)

                continuation.yield(.toolInputStart(
                    id: part.id,
                    toolName: toolName,
                    providerMetadata: nil,
                    providerExecuted: nil,
                    dynamic: nil,
                    title: nil
                ))
                continuation.yield(.toolInputDelta(id: part.id, delta: toolInput, providerMetadata: nil))
                continuation.yield(.toolInputEnd(id: part.id, providerMetadata: nil))
                continuation.yield(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: part.id,
                    toolName: toolName,
                    input: toolInput,
                    providerExecuted: true
                )))
            }

            if phase == .done {
                continuation.yield(.toolResult(.init(toolCallId: part.id, toolName: toolName, result: part.type == "web_search_call" ? mapWebSearchAction(part.action) : .object([:]))))
            }
            return
        }

    case .mcpCall(let part):
        var toolName = part.name ?? ""
        toolName = prepared.mcpToolName ?? (part.name ?? "mcp")

        let toolInput = part.arguments ?? ""

        let shouldEmit = !seenToolCalls.contains(part.id)
        if shouldEmit && !seenToolCalls.contains(part.id) {
            seenToolCalls.insert(part.id)

            continuation.yield(.toolInputStart(
                id: part.id,
                toolName: toolName,
                providerMetadata: nil,
                providerExecuted: nil,
                dynamic: nil,
                title: nil
            ))
            continuation.yield(.toolInputDelta(id: part.id, delta: toolInput, providerMetadata: nil))
            continuation.yield(.toolInputEnd(id: part.id, providerMetadata: nil))
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: part.id,
                toolName: toolName,
                input: toolInput,
                providerExecuted: true
            )))
        }
        if phase == .done { continuation.yield(.toolResult(.init(toolCallId: part.id, toolName: toolName, result: .object([:])))) }

    case .message(let part):
        for contentPart in part.content {
            if let text = contentPart.text, !text.isEmpty {
                let blockId = "text-\(part.id)"
                if !contentBlocks.contains(blockId) {
                    contentBlocks.append(blockId)
                    continuation.yield(.textStart(id: blockId, providerMetadata: nil))
                    continuation.yield(.textDelta(id: blockId, delta: text, providerMetadata: nil))
                }
            }

            if let annotations = contentPart.annotations {
                for annotation in annotations {
                    guard case .urlCitation(let url, let title) = annotation else { continue }
                    continuation.yield(.source(.url(
                        id: generateId(),
                        url: url,
                        title: title ?? url,
                        providerMetadata: nil
                    )))
                }
            }
        }

    case .functionCall(let part):
        if phase == .added {
            ongoingToolCalls[outputIndex] = (toolName: part.name, toolCallId: part.callId)
            continuation.yield(.toolInputStart(
                id: part.callId,
                toolName: part.name,
                providerMetadata: nil,
                providerExecuted: nil,
                dynamic: nil,
                title: nil
            ))
        } else {
            ongoingToolCalls[outputIndex] = nil
            continuation.yield(.toolInputEnd(id: part.callId, providerMetadata: nil))
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: part.callId,
                toolName: part.name,
                input: part.arguments
            )))
        }
    }
}

private func responseProviderMetadata(cost: Double?, tier: String?, cacheKey: String?, safety: String?) -> SharedV4ProviderMetadata? {
    var data: [String: JSONValue] = [:]
    if let cost { data["costInUsdTicks"] = .number(cost) }
    if let tier { data["serviceTier"] = .string(tier) }
    if let cacheKey { data["promptCacheKey"] = .string(cacheKey) }
    if let safety { data["safetyIdentifier"] = .string(safety) }
    return data.isEmpty ? nil : ["xai": data]
}

private func imageGenerationResult(_ part: XAIResponsesToolCall, toolName: String) -> LanguageModelV4ToolResult {
    if let result = part.result {
        var data: [String: JSONValue] = ["result": .string(result)]
        if let prompt = part.prompt { data["prompt"] = .string(prompt) }
        return .init(toolCallId: part.id, toolName: toolName, result: .object(data))
    }
    return .init(toolCallId: part.id, toolName: toolName, result: .string("Image generation failed (status: \(part.status))."), isError: true)
}

private func emitImageGenerationCall(id: String, toolName: String, continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation) {
    continuation.yield(.toolInputStart(id: id, toolName: toolName, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil))
    continuation.yield(.toolInputDelta(id: id, delta: "{}", providerMetadata: nil))
    continuation.yield(.toolInputEnd(id: id, providerMetadata: nil))
    continuation.yield(.toolCall(.init(toolCallId: id, toolName: toolName, input: "{}", providerExecuted: true)))
}

private func mapWebSearchAction(_ action: JSONValue?) -> JSONValue {
    guard case .object(let data) = action, case .string(let type) = data["type"], ["search", "open_page", "find_in_page"].contains(type) else { return .object([:]) }
    let stringKeys = type == "search" ? ["query"] : type == "open_page" ? ["url"] : ["url", "pattern"]
    for key in stringKeys {
        if let value = data[key], value != .null, case .string = value {} else if data[key] != nil && data[key] != .null { return .object([:]) }
    }
    if type == "search", let queries = data["queries"], queries != .null {
        guard case .array(let values) = queries, values.allSatisfy({ if case .string = $0 { true } else { false } }) else { return .object([:]) }
    }
    if let sources = data["sources"], sources != .null, case .array = sources {} else if data["sources"] != nil && data["sources"] != .null { return .object([:]) }
    var resultAction: [String: JSONValue] = ["type": .string(type == "open_page" ? "openPage" : type == "find_in_page" ? "findInPage" : "search")]
    for key in stringKeys where data[key] != nil && (type != "search" || data[key] != .null) { resultAction[key] = data[key] }
    if type == "search", let queries = data["queries"], queries != .null { resultAction["queries"] = queries }
    var result: [String: JSONValue] = ["action": .object(resultAction)]
    if case .array(let sources) = data["sources"] {
        let valid = sources.compactMap { source -> JSONValue? in
            guard case .object(let data) = source, data["type"] == .string("url"), case .string(let url) = data["url"] else { return nil }
            return .object(["type": .string("url"), "url": .string(url)])
        }
        if !valid.isEmpty { result["sources"] = .array(valid) }
    }
    return .object(result)
}

private func xaiStreamError(message: String, code: String?, eventType: String, data: JSONValue) -> ProviderStreamError {
    var status: Int?
    var retryable: Bool?
    if let code, code.count == 3, let value = Int(code), (400...599).contains(value) {
        status = value
        retryable = [408, 409, 429].contains(value) || value >= 500
    } else {
        switch code {
        case "rate_limit_exceeded", "rate_limit_error": status = 429; retryable = true
        case "insufficient_quota": status = 429; retryable = false
        case "api_error", "internal_server_error", "server_error": status = 500; retryable = true
        case "overloaded_error", "service_unavailable": status = 503; retryable = true
        case "timeout", "timeout_error": status = 504; retryable = true
        case "authentication_error", "invalid_api_key": status = 401; retryable = false
        case "permission_error": status = 403; retryable = false
        case "not_found_error", "model_not_found": status = 404; retryable = false
        case "bad_request", "context_length_exceeded", "invalid_request_error": status = 400; retryable = false
        default: break
        }
    }
    return createProviderStreamError(message: message, type: eventType, code: code.map(ProviderStreamError.Code.string), statusCode: status, isRetryable: retryable, data: data)
}
