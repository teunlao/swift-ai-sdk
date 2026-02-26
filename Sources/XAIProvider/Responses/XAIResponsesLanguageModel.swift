import Foundation
import AISDKProvider
import AISDKProviderUtils

/// xAI Responses language model implementation.
/// Mirrors `packages/xai/src/responses/xai-responses-language-model.ts`.
public final class XAIResponsesLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let generateId: @Sendable () -> String
        let fetch: FetchFunction?
    }

    fileprivate struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
        let webSearchToolName: String?
        let xSearchToolName: String?
        let codeExecutionToolName: String?
        let mcpToolName: String?
        let fileSearchToolName: String?
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
            url: "\(config.baseURL)/responses",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: xaiResponsesResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        var content: [LanguageModelV3Content] = []

        let webSearchSubTools: Set<String> = ["web_search", "web_search_with_snippets", "browse_page"]
        let xSearchSubTools: Set<String> = ["x_user_search", "x_keyword_search", "x_semantic_search", "x_thread_fetch"]

        for item in response.value.output {
            switch item {
            case .toolCall(let part):
                if part.type == "file_search_call" {
                    let toolName = prepared.fileSearchToolName ?? "file_search"

                    content.append(.toolCall(LanguageModelV3ToolCall(
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

                    content.append(.toolResult(LanguageModelV3ToolResult(
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

                    content.append(.toolCall(LanguageModelV3ToolCall(
                        toolCallId: toolCallId,
                        toolName: toolName,
                        input: toolInput,
                        providerExecuted: true
                    )))

                    continue
                }

            case .mcpCall(let part):
                let toolCallId = part.id

                var toolName = part.name ?? ""
                toolName = prepared.mcpToolName ?? (part.name ?? "mcp")

                let toolInput = part.arguments ?? ""

                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    input: toolInput,
                    providerExecuted: true
                )))

                continue

            case .message(let part):
                for contentPart in part.content {
                    if let text = contentPart.text, !text.isEmpty {
                        content.append(.text(LanguageModelV3Text(text: text)))
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
                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: part.callId,
                    toolName: part.name,
                    input: part.arguments
                )))

            case .reasoning(let part):
                let summaryTexts = part.summary.map(\.text).filter { !$0.isEmpty }
                guard !summaryTexts.isEmpty else { break }

                let reasoningText = summaryTexts.joined()

                var providerMetadata: SharedV3ProviderMetadata? = nil
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

                content.append(.reasoning(LanguageModelV3Reasoning(
                    text: reasoningText,
                    providerMetadata: providerMetadata
                )))
            }
        }

        let usage: LanguageModelV3Usage
        if let usageData = response.value.usage {
            usage = convertXaiResponsesUsage(usageData)
        } else {
            usage = LanguageModelV3Usage(
                inputTokens: .init(total: 0, noCache: 0, cacheRead: 0, cacheWrite: 0),
                outputTokens: .init(total: 0, text: 0, reasoning: 0)
            )
        }

        let finishReason = LanguageModelV3FinishReason(
            unified: mapXaiResponsesFinishReason(response.value.status),
            raw: response.value.status
        )

        let metadata = xaiResponseMetadata(
            id: response.value.id,
            model: response.value.model,
            created: response.value.createdAt
        )

        return LanguageModelV3GenerateResult(
            content: content,
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

        let streamResponse = try await postJsonToAPI(
            url: "\(config.baseURL)/responses",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(streamBody),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: xaiResponsesChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason = LanguageModelV3FinishReason(unified: .other, raw: nil)
                var usage: LanguageModelV3Usage? = nil
                var isFirstChunk = true
                var contentBlocks: Set<String> = []
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
                            continuation.yield(.error(error: .string(String(describing: error))))
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
                                activeReasoning.insert(itemId)
                                continuation.yield(.reasoningStart(
                                    id: blockId,
                                    providerMetadata: ["xai": ["itemId": .string(itemId)]]
                                ))

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
                                    contentBlocks.insert(blockId)
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
                                }
                                finishReason = .init(
                                    unified: mapXaiResponsesFinishReason(response.status),
                                    raw: response.status
                                )

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
                        usage: usage ?? LanguageModelV3Usage(
                            inputTokens: .init(total: 0, noCache: 0, cacheRead: 0, cacheWrite: 0),
                            outputTokens: .init(total: 0, text: 0, reasoning: 0)
                        ),
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
            request: LanguageModelV3RequestInfo(body: streamBody),
            response: LanguageModelV3StreamResponseInfo(headers: streamResponse.responseHeaders)
        )
    }

    // MARK: - Preparation

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        let providerOptions = try await parseProviderOptions(
            provider: "xai",
            providerOptions: options.providerOptions,
            schema: xaiLanguageModelResponsesOptionsSchema
        ) ?? XAILanguageModelResponsesOptions()

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

        let inputConversion = try await convertToXAIResponsesInput(
            prompt: options.prompt,
            store: true
        )
        warnings.append(contentsOf: inputConversion.warnings)

        let preparedTools = try await prepareXAIResponsesTools(tools: options.tools, toolChoice: options.toolChoice)
        warnings.append(contentsOf: preparedTools.warnings)

        var includeValues: [String]? = nil
        if let include = providerOptions.include, !include.isEmpty {
            includeValues = include
        }

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
        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }

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

        if let reasoningEffort = providerOptions.reasoningEffort {
            body["reasoning"] = .object([
                "effort": .string(reasoningEffort.rawValue)
            ])
        }

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
            fileSearchToolName: fileSearchToolName
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
    continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation,
    contentBlocks: inout Set<String>,
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
                continuation.yield(.toolCall(LanguageModelV3ToolCall(
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

                continuation.yield(.toolResult(LanguageModelV3ToolResult(
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
                continuation.yield(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: part.id,
                    toolName: toolName,
                    input: toolInput,
                    providerExecuted: true
                )))
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
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: part.id,
                toolName: toolName,
                input: toolInput,
                providerExecuted: true
            )))
        }

    case .message(let part):
        for contentPart in part.content {
            if let text = contentPart.text, !text.isEmpty {
                let blockId = "text-\(part.id)"
                if !contentBlocks.contains(blockId) {
                    contentBlocks.insert(blockId)
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
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: part.callId,
                toolName: part.name,
                input: part.arguments
            )))
        }
    }
}
