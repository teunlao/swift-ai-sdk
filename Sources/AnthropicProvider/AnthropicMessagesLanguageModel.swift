import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicMessagesConfig: @unchecked Sendable {
    public struct RequestTransform: Sendable {
        public let buildURL: (@Sendable (_ baseURL: String, _ isStreaming: Bool) -> String)?
        public let transformBody: (@Sendable (_ body: [String: JSONValue]) -> [String: JSONValue])?

        public init(
            buildURL: (@Sendable (_ baseURL: String, _ isStreaming: Bool) -> String)? = nil,
            transformBody: (@Sendable (_ body: [String: JSONValue]) -> [String: JSONValue])? = nil
        ) {
            self.buildURL = buildURL
            self.transformBody = transformBody
        }
    }

    public let provider: String
    public let baseURL: String
    public let headers: @Sendable () -> [String: String?]
    public let fetch: FetchFunction?
    public let supportedUrls: @Sendable () -> [String: [NSRegularExpression]]
    public let generateId: @Sendable () -> String
    public let requestTransform: RequestTransform

    public init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction? = nil,
        supportedUrls: @escaping @Sendable () -> [String: [NSRegularExpression]] = { [:] },
        generateId: @escaping @Sendable () -> String = defaultAnthropicId,
        requestTransform: RequestTransform = .init()
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.supportedUrls = supportedUrls
        self.generateId = generateId
        self.requestTransform = requestTransform
    }
}

private struct AnthropicRequestArguments {
    let body: [String: JSONValue]
    let warnings: [LanguageModelV3CallWarning]
    let betas: Set<String>
    let usesJsonResponseTool: Bool
}

public final class AnthropicMessagesLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"

    private let modelIdentifier: AnthropicMessagesModelId
    private let config: AnthropicMessagesConfig
    private let generateIdentifier: @Sendable () -> String

    public init(modelId: AnthropicMessagesModelId, config: AnthropicMessagesConfig) {
        self.modelIdentifier = modelId
        self.config = config
        self.generateIdentifier = config.generateId
    }

    public var modelId: String { modelIdentifier.rawValue }

    public func supportsUrl(_ url: URL) -> Bool {
        url.scheme == "https"
    }

    public var provider: String { config.provider }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { config.supportedUrls() }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let requestURL = buildRequestURL(isStreaming: false)
        let headers = getHeaders(betas: prepared.betas, additional: options.headers)

        let body = config.requestTransform.transformBody?(prepared.body) ?? prepared.body

        let response = try await postJsonToAPI(
            url: requestURL,
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: anthropicFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: anthropicMessagesResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let usageAndContent = try mapResponseContent(
            response: response.value,
            prompt: options.prompt,
            usesJsonResponseTool: prepared.usesJsonResponseTool
        )

        let providerMetadata = makeProviderMetadata(
            response: response.value,
            usage: usageAndContent.usage,
            betas: prepared.betas
        )

        return LanguageModelV3GenerateResult(
            content: usageAndContent.content,
            finishReason: mapAnthropicStopReason(
                finishReason: response.value.stopReason,
                isJsonResponseFromTool: prepared.usesJsonResponseTool
            ),
            usage: usageAndContent.usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3ResponseInfo(
                id: response.value.id,
                timestamp: nil,
                modelId: response.value.model,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options)

        var requestBody = prepared.body
        requestBody["stream"] = .bool(true)
        let transformedBody = config.requestTransform.transformBody?(requestBody) ?? requestBody

        let response = try await postJsonToAPI(
            url: buildRequestURL(isStreaming: true),
            headers: getHeaders(betas: prepared.betas, additional: options.headers),
            body: JSONValue.object(transformedBody),
            failedResponseHandler: anthropicFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: anthropicMessagesChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let citationDocuments = extractCitationDocuments(from: options.prompt)

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var contentBlocks: [Int: ContentBlockState] = [:]
                var blockType: String?
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var rawUsage: [String: JSONValue]? = nil
                var cacheCreationInputTokens: Int? = nil
                var stopSequence: String? = nil

                do {
                    for try await chunk in response.value {
                        switch chunk {
                        case .success(let event, let rawValue):
                            if options.includeRawChunks == true,
                               let rawJSON = try? jsonValue(from: rawValue) {
                                continuation.yield(.raw(rawValue: rawJSON))
                            }

                            switch event {
                            case .ping:
                                continue

                            case .contentBlockStart(let value):
                                blockType = contentBlockType(for: value.contentBlock)
                                handleContentBlockStart(
                                    value,
                                    usesJsonResponseTool: prepared.usesJsonResponseTool,
                                    citationDocuments: citationDocuments,
                                    contentBlocks: &contentBlocks,
                                    continuation: continuation
                                )

                            case .contentBlockDelta(let value):
                                handleContentBlockDelta(
                                    value,
                                    blockType: blockType,
                                    usesJsonResponseTool: prepared.usesJsonResponseTool,
                                    citationDocuments: citationDocuments,
                                    contentBlocks: &contentBlocks,
                                    continuation: continuation
                                )

                            case .contentBlockStop(let value):
                                handleContentBlockStop(
                                    index: value.index,
                                    usesJsonResponseTool: prepared.usesJsonResponseTool,
                                    contentBlocks: &contentBlocks,
                                    continuation: continuation
                                )
                                blockType = nil

                            case .messageStart(let value):
                                if let usageInfo = value.message.usage {
                                    usage = LanguageModelV3Usage(
                                        inputTokens: usageInfo.inputTokens,
                                        outputTokens: usage.outputTokens,
                                        totalTokens: usage.totalTokens,
                                        reasoningTokens: usage.reasoningTokens,
                                        cachedInputTokens: usageInfo.cacheReadInputTokens
                                    )
                                    cacheCreationInputTokens = usageInfo.cacheCreationInputTokens
                                    rawUsage = anthropicUsageMetadata(usageInfo)
                                }
                                continuation.yield(.responseMetadata(
                                    id: value.message.id,
                                    modelId: value.message.model,
                                    timestamp: nil
                                ))

                            case .messageDelta(let value):
                                if let usageInfo = value.usage {
                                    let currentInput = usage.inputTokens ?? usageInfo.inputTokens
                                    let cachedInput = usageInfo.cacheReadInputTokens ?? usage.cachedInputTokens
                                    usage = LanguageModelV3Usage(
                                        inputTokens: currentInput,
                                        outputTokens: usageInfo.outputTokens,
                                        totalTokens: currentInput + usageInfo.outputTokens,
                                        reasoningTokens: usage.reasoningTokens,
                                        cachedInputTokens: cachedInput
                                    )

                                    let metadata = anthropicUsageMetadata(usageInfo)
                                    if var existing = rawUsage {
                                        for (key, value) in metadata {
                                            existing[key] = value
                                        }
                                        rawUsage = existing
                                    } else {
                                        rawUsage = metadata
                                    }
                                }

                                finishReason = mapAnthropicStopReason(
                                    finishReason: value.delta.stopReason,
                                    isJsonResponseFromTool: prepared.usesJsonResponseTool
                                )
                                stopSequence = value.delta.stopSequence

                            case .messageStop:
                                var metadata: [String: JSONValue] = [:]
                                metadata["usage"] = rawUsage.map(JSONValue.object) ?? .null
                                metadata["cacheCreationInputTokens"] = cacheCreationInputTokens.map { .number(Double($0)) } ?? .null
                                metadata["stopSequence"] = stopSequence.map(JSONValue.string) ?? .null

                                continuation.yield(
                                    .finish(
                                        finishReason: finishReason,
                                        usage: usage,
                                        providerMetadata: ["anthropic": metadata]
                                    )
                                )

                            case .error(let value):
                                if let errorJSON = encodeToJSONValue(value) {
                                    continuation.yield(.error(error: errorJSON))
                                } else {
                                    continuation.yield(.error(error: .string("Anthropic stream error")))
                                }

                            }

                        case .failure(let error, let rawValue):
                            let errorJSON = rawValue.flatMap({ try? jsonValue(from: $0) }) ?? .string(String(describing: error))
                            continuation.yield(.error(error: errorJSON))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        let requestInfo = LanguageModelV3RequestInfo(body: requestBody)
        let responseInfo = LanguageModelV3StreamResponseInfo(headers: response.responseHeaders)
        return LanguageModelV3StreamResult(stream: stream, request: requestInfo, response: responseInfo)
    }

    // MARK: - Helpers

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> AnthropicRequestArguments {
        var warnings: [LanguageModelV3CallWarning] = []

        if options.frequencyPenalty != nil {
            warnings.append(.unsupportedSetting(setting: "frequencyPenalty", details: nil))
        }
        if options.presencePenalty != nil {
            warnings.append(.unsupportedSetting(setting: "presencePenalty", details: nil))
        }
        if options.seed != nil {
            warnings.append(.unsupportedSetting(setting: "seed", details: nil))
        }

        var jsonResponseTool: LanguageModelV3FunctionTool?
        var usesJsonResponseTool = false

        if case let .json(schema, _, _) = options.responseFormat {
            if schema == nil {
                warnings.append(
                    .unsupportedSetting(
                        setting: "responseFormat",
                        details: "JSON response format requires a schema. The response format is ignored."
                    )
                )
            } else if options.tools != nil {
                warnings.append(
                    .unsupportedSetting(
                        setting: "tools",
                        details: "JSON response format does not support tools. The provided tools are ignored."
                    )
                )
            }

            if let schema {
                jsonResponseTool = LanguageModelV3FunctionTool(
                    name: "json",
                    inputSchema: schema,
                    description: "Respond with a JSON object."
                )
                usesJsonResponseTool = true
            }
        }

        let anthropicOptions = try await parseProviderOptions(
            provider: "anthropic",
            providerOptions: options.providerOptions,
            schema: anthropicProviderOptionsSchema
        )

        var conversionWarnings = warnings
        let conversion = try await convertToAnthropicMessagesPrompt(
            prompt: options.prompt,
            sendReasoning: anthropicOptions?.sendReasoning ?? true,
            warnings: &conversionWarnings
        )
        warnings = conversionWarnings

        var betas = conversion.betas

        var args: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(conversion.prompt.messages.map { $0.toJSONValue() })
        ]

        if let system = conversion.prompt.system, !system.isEmpty {
            args["system"] = .array(system)
        }

        let baseMaxTokens = options.maxOutputTokens ?? 4096
        args["max_tokens"] = .number(Double(baseMaxTokens))

        if let temperature = options.temperature {
            args["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            args["top_p"] = .number(topP)
        }
        if let topK = options.topK {
            args["top_k"] = .number(Double(topK))
        }
        if let stopSequences = options.stopSequences, !stopSequences.isEmpty {
            args["stop_sequences"] = .array(stopSequences.map(JSONValue.string))
        }

        if anthropicOptions?.thinking?.type == .enabled {
            guard let budget = anthropicOptions?.thinking?.budgetTokens else {
                throw UnsupportedFunctionalityError(functionality: "thinking requires a budget")
            }

            if options.temperature != nil {
                warnings.append(
                    .unsupportedSetting(
                        setting: "temperature",
                        details: "temperature is not supported when thinking is enabled"
                    )
                )
                args.removeValue(forKey: "temperature")
            }
            if options.topK != nil {
                warnings.append(
                    .unsupportedSetting(
                        setting: "topK",
                        details: "topK is not supported when thinking is enabled"
                    )
                )
                args.removeValue(forKey: "top_k")
            }
            if options.topP != nil {
                warnings.append(
                    .unsupportedSetting(
                        setting: "topP",
                        details: "topP is not supported when thinking is enabled"
                    )
                )
                args.removeValue(forKey: "top_p")
            }

            args["thinking"] = .object([
                "type": .string("enabled"),
                "budget_tokens": .number(Double(budget))
            ])
            args["max_tokens"] = .number(Double(baseMaxTokens + budget))
        }

        let preparedTools = try await prepareAnthropicTools(
            tools: jsonResponseTool != nil ? [.function(jsonResponseTool!)] : options.tools,
            toolChoice: jsonResponseTool != nil ? .tool(toolName: jsonResponseTool!.name) : options.toolChoice,
            disableParallelToolUse: jsonResponseTool != nil ? true : anthropicOptions?.disableParallelToolUse
        )

        warnings.append(contentsOf: preparedTools.warnings)
        betas.formUnion(preparedTools.betas)

        if let tools = preparedTools.tools {
            args["tools"] = .array(tools)
        }
        if let toolChoice = preparedTools.toolChoice {
            args["tool_choice"] = toolChoice
        }

        return AnthropicRequestArguments(
            body: args,
            warnings: warnings,
            betas: betas,
            usesJsonResponseTool: usesJsonResponseTool
        )
    }

    private func buildRequestURL(isStreaming: Bool) -> String {
        if let builder = config.requestTransform.buildURL {
            return builder(config.baseURL, isStreaming)
        }
        return "\(config.baseURL)/messages"
    }

    private func getHeaders(betas: Set<String>, additional: [String: String]?) -> [String: String] {
        var combined: [String: String?] = config.headers()
        if !betas.isEmpty {
            combined = combineHeaders(combined, ["anthropic-beta": betas.sorted().joined(separator: ",")])
        }
        if let additional {
            combined = combineHeaders(combined, additional.mapValues { Optional($0) })
        }
        return combined.compactMapValues { $0 }
    }

    private func mapResponseContent(
        response: AnthropicMessagesResponse,
        prompt: LanguageModelV3Prompt,
        usesJsonResponseTool: Bool
    ) throws -> (content: [LanguageModelV3Content], usage: LanguageModelV3Usage) {
        var content: [LanguageModelV3Content] = []
        let citationDocuments = extractCitationDocuments(from: prompt)

        for part in response.content {
            switch part {
            case .text(let value):
                if usesJsonResponseTool {
                    continue
                }

                content.append(.text(LanguageModelV3Text(text: value.text)))

                if let citations = value.citations {
                    for citation in citations {
                        if let source = createCitationSource(from: citation, documents: citationDocuments) {
                            content.append(.source(source))
                        }
                    }
                }

            case .thinking(let value):
                let metadata: SharedV3ProviderMetadata = [
                    "anthropic": ["signature": .string(value.signature)]
                ]
                content.append(.reasoning(LanguageModelV3Reasoning(text: value.thinking, providerMetadata: metadata)))

            case .redactedThinking(let value):
                let metadata: SharedV3ProviderMetadata = [
                    "anthropic": ["redactedData": .string(value.data)]
                ]
                content.append(.reasoning(LanguageModelV3Reasoning(text: "", providerMetadata: metadata)))

            case .toolUse(let value):
                if usesJsonResponseTool {
                    content.append(.text(LanguageModelV3Text(text: stringifyJSON(value.input))))
                } else {
                    let toolCall = LanguageModelV3ToolCall(
                        toolCallId: value.id,
                        toolName: value.name,
                        input: stringifyJSON(value.input)
                    )
                    content.append(.toolCall(toolCall))
                }

            case .serverToolUse(let value):
                guard value.name == "web_search" || value.name == "code_execution" || value.name == "web_fetch" else { continue }
                let toolCall = LanguageModelV3ToolCall(
                    toolCallId: value.id,
                    toolName: value.name,
                    input: stringifyJSON(value.input),
                    providerExecuted: true
                )
                content.append(.toolCall(toolCall))

            case .webFetchResult(let value):
                if case .object(let payload) = value.content,
                   let type = payload["type"], case .string(let typeString) = type {
                    switch typeString {
                    case "web_fetch_result":
                        guard
                            let urlValue = payload["url"], case .string(let url) = urlValue,
                            let retrievedAtValue = payload["retrieved_at"],
                            let contentValue = payload["content"], case .object(let resultContent) = contentValue,
                            let sourceValue = resultContent["source"], case .object(let sourceObject) = sourceValue,
                            let sourceTypeValue = sourceObject["type"], case .string(let sourceType) = sourceTypeValue,
                            let mediaTypeValue = sourceObject["media_type"], case .string(let mediaType) = mediaTypeValue,
                            let dataValue = sourceObject["data"], case .string(let data) = dataValue
                        else {
                            continue
                        }

                        var resultObject: [String: JSONValue] = [
                            "type": .string("web_fetch_result"),
                            "url": .string(url),
                            "retrievedAt": retrievedAtValue
                        ]

                        var contentObject: [String: JSONValue] = [
                            "type": resultContent["type"] ?? .string("document"),
                            "title": resultContent["title"] ?? .string(""),
                            "source": .object([
                                "type": .string(sourceType),
                                "mediaType": .string(mediaType),
                                "data": .string(data)
                            ])
                        ]
                        if let citations = resultContent["citations"] {
                            contentObject["citations"] = citations
                        }
                        resultObject["content"] = .object(contentObject)

                        let toolResult = LanguageModelV3ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: "web_fetch",
                            result: .object(resultObject),
                            providerExecuted: true
                        )
                        content.append(.toolResult(toolResult))

                    case "web_fetch_tool_result_error":
                        let errorCode = payload["error_code"] ?? .null
                        let toolResult = LanguageModelV3ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: "web_fetch",
                            result: .object([
                                "type": .string("web_fetch_tool_result_error"),
                                "errorCode": errorCode
                            ]),
                            isError: true,
                            providerExecuted: true
                        )
                        content.append(.toolResult(toolResult))

                    default:
                        break
                    }
                }

            case .webSearchResult(let value):
                switch value.content {
                case .array(let results):
                    var array: [JSONValue] = []
                    for item in results {
                        guard case .object(let object) = item else { continue }
                        guard
                            let urlValue = object["url"], case .string(let url) = urlValue,
                            let titleValue = object["title"], case .string(let title) = titleValue,
                            let encryptedValue = object["encrypted_content"], case .string(let encrypted) = encryptedValue
                        else { continue }

                        let pageAge = object["page_age"]
                        array.append(.object([
                            "url": .string(url),
                            "title": .string(title),
                            "pageAge": pageAge ?? .null,
                            "encryptedContent": .string(encrypted),
                            "type": object["type"] ?? .string("web_search_result")
                        ]))

                        let metadata: SharedV3ProviderMetadata = [
                            "anthropic": ["pageAge": pageAge ?? .null]
                        ]
                        content.append(.source(.url(
                            id: generateIdentifier(),
                            url: url,
                            title: title,
                            providerMetadata: metadata
                        )))
                    }

                    let toolResult = LanguageModelV3ToolResult(
                        toolCallId: value.toolUseId,
                        toolName: "web_search",
                        result: .array(array),
                        providerExecuted: true
                    )
                    content.append(.toolResult(toolResult))

                case .object(let object):
                    let errorCode = object["error_code"] ?? .null
                    let toolResult = LanguageModelV3ToolResult(
                        toolCallId: value.toolUseId,
                        toolName: "web_search",
                        result: .object([
                            "type": .string("web_search_tool_result_error"),
                            "errorCode": errorCode
                        ]),
                        isError: true,
                        providerExecuted: true
                    )
                    content.append(.toolResult(toolResult))

                default:
                    break
                }

            case .codeExecutionResult(let value):
                if case .object(let payload) = value.content,
                   let type = payload["type"], case .string(let typeString) = type {
                    switch typeString {
                    case "code_execution_result":
                        let stdout = payload["stdout"] ?? .string("")
                        let stderr = payload["stderr"] ?? .string("")
                        let returnCode = payload["return_code"] ?? .number(0)
                        let toolResult = LanguageModelV3ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: "code_execution",
                            result: .object([
                                "type": .string("code_execution_result"),
                                "stdout": stdout,
                                "stderr": stderr,
                                "return_code": returnCode
                            ]),
                            providerExecuted: true
                        )
                        content.append(.toolResult(toolResult))

                    case "code_execution_tool_result_error":
                        let errorCode = payload["error_code"] ?? .null
                        let toolResult = LanguageModelV3ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: "code_execution",
                            result: .object([
                                "type": .string("code_execution_tool_result_error"),
                                "errorCode": errorCode
                            ]),
                            isError: true,
                            providerExecuted: true
                        )
                        content.append(.toolResult(toolResult))

                    default:
                        break
                    }
                }
            }
        }

        let usage = LanguageModelV3Usage(
            inputTokens: response.usage.inputTokens,
            outputTokens: response.usage.outputTokens,
            totalTokens: response.usage.inputTokens + response.usage.outputTokens,
            reasoningTokens: nil,
            cachedInputTokens: response.usage.cacheReadInputTokens
        )

        return (content, usage)
    }

    private struct CitationDocument {
        let title: String
        let filename: String?
        let mediaType: String
    }

    private struct ToolCallState {
        var toolCallId: String
        var toolName: String
        var input: String
        var providerExecuted: Bool
    }

    private enum ContentBlockState {
        case text
        case reasoning
        case toolCall(ToolCallState)
    }


    private func extractCitationDocuments(from prompt: LanguageModelV3Prompt) -> [CitationDocument] {
        var documents: [CitationDocument] = []
        for message in prompt {
            guard case let .user(parts, _) = message else { continue }
            for part in parts {
                guard case let .file(filePart) = part else { continue }
                guard filePart.mediaType == "application/pdf" || filePart.mediaType == "text/plain" else { continue }
                guard let anthropicOptions = filePart.providerOptions?["anthropic"],
                      let citationsValue = anthropicOptions["citations"],
                      case .object(let citationsObject) = citationsValue,
                      let enabledValue = citationsObject["enabled"],
                      case .bool(let enabled) = enabledValue,
                      enabled
                else { continue }

                documents.append(
                    CitationDocument(
                        title: filePart.filename ?? "Untitled Document",
                        filename: filePart.filename,
                        mediaType: filePart.mediaType
                    )
                )
            }
        }
        return documents
    }

    private func createCitationSource(from citation: AnthropicCitation, documents: [CitationDocument]) -> LanguageModelV3Source? {
        switch citation {
        case .webSearchResultLocation:
            return nil
        case .pageLocation(let info):
            let document = documents[safe: info.documentIndex]
            guard let document else { return nil }
            let metadata: SharedV3ProviderMetadata = [
                "anthropic": [
                    "citedText": .string(info.citedText),
                    "startPageNumber": .number(Double(info.startPageNumber)),
                    "endPageNumber": .number(Double(info.endPageNumber))
                ]
            ]
            return .document(
                id: generateIdentifier(),
                mediaType: document.mediaType,
                title: info.documentTitle ?? document.title,
                filename: document.filename,
                providerMetadata: metadata
            )
        case .charLocation(let info):
            let document = documents[safe: info.documentIndex]
            guard let document else { return nil }
            let metadata: SharedV3ProviderMetadata = [
                "anthropic": [
                    "citedText": .string(info.citedText),
                    "startCharIndex": .number(Double(info.startCharIndex)),
                    "endCharIndex": .number(Double(info.endCharIndex))
                ]
            ]
            return .document(
                id: generateIdentifier(),
                mediaType: document.mediaType,
                title: info.documentTitle ?? document.title,
                filename: document.filename,
                providerMetadata: metadata
            )
        }
    }

    private func contentBlockType(for content: AnthropicMessageContent) -> String {
        switch content {
        case .text: return "text"
        case .thinking: return "thinking"
        case .redactedThinking: return "redacted_thinking"
        case .toolUse: return "tool_use"
        case .serverToolUse: return "server_tool_use"
        case .webFetchResult: return "web_fetch_tool_result"
        case .webSearchResult: return "web_search_tool_result"
        case .codeExecutionResult: return "code_execution_tool_result"
        }
    }

    private func handleContentBlockStart(
        _ value: ContentBlockStart,
        usesJsonResponseTool: Bool,
        citationDocuments: [CitationDocument],
        contentBlocks: inout [Int: ContentBlockState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        switch value.contentBlock {
        case .text:
            contentBlocks[value.index] = .text
            continuation.yield(.textStart(id: String(value.index), providerMetadata: nil))

        case .thinking:
            contentBlocks[value.index] = .reasoning
            continuation.yield(.reasoningStart(id: String(value.index), providerMetadata: nil))

        case .redactedThinking(let redacted):
            contentBlocks[value.index] = .reasoning
            let metadata: SharedV3ProviderMetadata = [
                "anthropic": ["redactedData": .string(redacted.data)]
            ]
            continuation.yield(.reasoningStart(id: String(value.index), providerMetadata: metadata))

        case .toolUse(let tool):
            if usesJsonResponseTool {
                contentBlocks[value.index] = .text
                continuation.yield(.textStart(id: String(value.index), providerMetadata: nil))
            } else {
                let state = ToolCallState(toolCallId: tool.id, toolName: tool.name, input: "", providerExecuted: false)
                contentBlocks[value.index] = .toolCall(state)
                continuation.yield(.toolInputStart(id: tool.id, toolName: tool.name, providerMetadata: nil, providerExecuted: false))
            }

        case .serverToolUse(let tool):
            guard tool.name == "web_fetch" || tool.name == "web_search" || tool.name == "code_execution" else { return }
            let state = ToolCallState(toolCallId: tool.id, toolName: tool.name, input: "", providerExecuted: true)
            contentBlocks[value.index] = .toolCall(state)
            continuation.yield(.toolInputStart(id: tool.id, toolName: tool.name, providerMetadata: nil, providerExecuted: true))

        case .webFetchResult(let result):
            if let toolResult = convertWebFetchToolResult(result) {
                continuation.yield(.toolResult(toolResult))
            }

        case .webSearchResult(let result):
            let (toolResult, sources) = convertWebSearchToolResult(result, generateSourceId: generateIdentifier)
            if let toolResult {
                continuation.yield(.toolResult(toolResult))
            }
            for source in sources {
                continuation.yield(.source(source))
            }

        case .codeExecutionResult(let result):
            if let toolResult = convertCodeExecutionToolResult(result) {
                continuation.yield(.toolResult(toolResult))
            }
        }
    }

    private func handleContentBlockDelta(
        _ value: ContentBlockDelta,
        blockType: String?,
        usesJsonResponseTool: Bool,
        citationDocuments: [CitationDocument],
        contentBlocks: inout [Int: ContentBlockState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        switch value.delta {
        case .textDelta(let text):
            guard usesJsonResponseTool == false else { return }
            continuation.yield(.textDelta(id: String(value.index), delta: text, providerMetadata: nil))

        case .thinkingDelta(let thinking):
            continuation.yield(.reasoningDelta(id: String(value.index), delta: thinking, providerMetadata: nil))

        case .signatureDelta(let signature):
            guard blockType == "thinking" else { return }
            let metadata: SharedV3ProviderMetadata = [
                "anthropic": ["signature": .string(signature)]
            ]
            continuation.yield(.reasoningDelta(id: String(value.index), delta: "", providerMetadata: metadata))

        case .inputJSONDelta(let partialJSON):
            if usesJsonResponseTool {
                continuation.yield(.textDelta(id: String(value.index), delta: partialJSON, providerMetadata: nil))
            } else if case .toolCall(var toolState) = contentBlocks[value.index] {
                continuation.yield(.toolInputDelta(id: toolState.toolCallId, delta: partialJSON, providerMetadata: nil))
                toolState.input += partialJSON
                contentBlocks[value.index] = .toolCall(toolState)
            }

        case .citationsDelta(let citation):
            if let source = createCitationSource(from: citation, documents: citationDocuments) {
                continuation.yield(.source(source))
            }
        }
    }

    private func handleContentBlockStop(
        index: Int,
        usesJsonResponseTool: Bool,
        contentBlocks: inout [Int: ContentBlockState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        guard let state = contentBlocks.removeValue(forKey: index) else { return }

        switch state {
        case .text:
            continuation.yield(.textEnd(id: String(index), providerMetadata: nil))

        case .reasoning:
            continuation.yield(.reasoningEnd(id: String(index), providerMetadata: nil))

        case .toolCall(let toolState):
            if usesJsonResponseTool {
                continuation.yield(.textEnd(id: String(index), providerMetadata: nil))
            } else {
                continuation.yield(.toolInputEnd(id: toolState.toolCallId, providerMetadata: nil))
                let toolCall = LanguageModelV3ToolCall(
                    toolCallId: toolState.toolCallId,
                    toolName: toolState.toolName,
                    input: toolState.input,
                    providerExecuted: toolState.providerExecuted
                )
                continuation.yield(.toolCall(toolCall))
            }
        }
    }

    private func anthropicUsageMetadata(_ usage: AnthropicUsage) -> [String: JSONValue] {
        var metadata: [String: JSONValue] = [
            "input_tokens": .number(Double(usage.inputTokens)),
            "output_tokens": .number(Double(usage.outputTokens))
        ]
        if let cacheCreation = usage.cacheCreationInputTokens {
            metadata["cache_creation_input_tokens"] = .number(Double(cacheCreation))
        }
        if let cacheRead = usage.cacheReadInputTokens {
            metadata["cache_read_input_tokens"] = .number(Double(cacheRead))
        }
        return metadata
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func convertWebFetchToolResult(_ content: WebFetchToolResultContent) -> LanguageModelV3ToolResult? {
        guard case .object(let payload) = content.content else { return nil }
        guard let typeValue = payload["type"], case .string(let type) = typeValue else { return nil }

        if type == "web_fetch_result" {
            let url = payload["url"] ?? .string("")
            let retrievedAt = payload["retrieved_at"] ?? .null
            var resultObject: [String: JSONValue] = [
                "type": .string("web_fetch_result"),
                "url": url,
                "retrievedAt": retrievedAt
            ]

            if let contentValue = payload["content"], case .object(let inner) = contentValue,
               let sourceValue = inner["source"], case .object(let sourceObject) = sourceValue {
                var mappedContent: [String: JSONValue] = [
                    "type": inner["type"] ?? .string("document"),
                    "title": inner["title"] ?? .string("")
                ]
                mappedContent["source"] = .object([
                    "type": sourceObject["type"] ?? .string("base64"),
                    "mediaType": sourceObject["media_type"] ?? .string(""),
                    "data": sourceObject["data"] ?? .string("")
                ])
                if let citations = inner["citations"] {
                    mappedContent["citations"] = citations
                }
                resultObject["content"] = .object(mappedContent)
            }

            return LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: "web_fetch",
                result: .object(resultObject),
                providerExecuted: true
            )
        }

        if type == "web_fetch_tool_result_error" {
            return LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: "web_fetch",
                result: .object([
                    "type": .string("web_fetch_tool_result_error"),
                    "errorCode": payload["error_code"] ?? .null
                ]),
                isError: true,
                providerExecuted: true
            )
        }

        return nil
    }

    private func convertWebSearchToolResult(
        _ content: WebSearchToolResultContent,
        generateSourceId: @Sendable () -> String
    ) -> (LanguageModelV3ToolResult?, [LanguageModelV3Source]) {
        switch content.content {
        case .array(let items):
            var resultsJSON: [JSONValue] = []
            var sources: [LanguageModelV3Source] = []

            for item in items {
                guard case .object(let object) = item else { continue }
                let urlValue = object["url"] ?? .string("")
                let titleValue = object["title"] ?? .string("")
                let pageAge = object["page_age"] ?? .null
                resultsJSON.append(.object([
                    "url": urlValue,
                    "title": titleValue,
                    "pageAge": pageAge,
                    "encryptedContent": object["encrypted_content"] ?? .string("")
                ]))

                if case .string(let url) = urlValue,
                   case .string(let title) = titleValue {
                    let metadata: SharedV3ProviderMetadata = [
                        "anthropic": ["pageAge": pageAge]
                    ]
                    sources.append(.url(id: generateSourceId(), url: url, title: title, providerMetadata: metadata))
                }
            }

            let toolResult = LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: "web_search",
                result: .array(resultsJSON),
                providerExecuted: true
            )
            return (toolResult, sources)

        case .object(let object):
            let toolResult = LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: "web_search",
                result: .object([
                    "type": .string("web_search_tool_result_error"),
                    "errorCode": object["error_code"] ?? .null
                ]),
                isError: true,
                providerExecuted: true
            )
            return (toolResult, [])

        default:
            return (nil, [])
        }
    }

    private func convertCodeExecutionToolResult(_ content: CodeExecutionToolResultContent) -> LanguageModelV3ToolResult? {
        guard case .object(let payload) = content.content else { return nil }
        guard let typeValue = payload["type"], case .string(let type) = typeValue else { return nil }

        if type == "code_execution_result" {
            return LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: "code_execution",
                result: .object([
                    "type": .string("code_execution_result"),
                    "stdout": payload["stdout"] ?? .string("") ,
                    "stderr": payload["stderr"] ?? .string("") ,
                    "return_code": payload["return_code"] ?? .number(0)
                ]),
                providerExecuted: true
            )
        }

        if type == "code_execution_tool_result_error" {
            return LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: "code_execution",
                result: .object([
                    "type": .string("code_execution_tool_result_error"),
                    "errorCode": payload["error_code"] ?? .null
                ]),
                isError: true,
                providerExecuted: true
            )
        }

        return nil
    }
    private func stringifyJSON(_ value: JSONValue?) -> String {
        guard let value else { return "null" }
        if let data = try? JSONEncoder().encode(value), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "null"
    }


    private func makeProviderMetadata(
        response: AnthropicMessagesResponse,
        usage: LanguageModelV3Usage,
        betas: Set<String>
    ) -> SharedV3ProviderMetadata? {
        var anthropicMetadata: [String: JSONValue] = [:]

        anthropicMetadata["usage"] = .object([
            "input_tokens": .number(Double(response.usage.inputTokens)),
            "output_tokens": .number(Double(response.usage.outputTokens)),
            "cache_creation_input_tokens": response.usage.cacheCreationInputTokens.map { .number(Double($0)) } ?? .null,
            "cache_read_input_tokens": response.usage.cacheReadInputTokens.map { .number(Double($0)) } ?? .null
        ])
        anthropicMetadata["stopReason"] = response.stopReason.map(JSONValue.string) ?? .null
        anthropicMetadata["stopSequence"] = response.stopSequence.map(JSONValue.string) ?? .null
        if !betas.isEmpty {
            anthropicMetadata["betas"] = .array(betas.sorted().map(JSONValue.string))
        }

        return ["anthropic": anthropicMetadata]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
