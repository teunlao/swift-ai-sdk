import AISDKProvider
import AISDKProviderUtils
import Foundation

public struct AnthropicMessagesConfig: @unchecked Sendable {
    public struct RequestTransform: Sendable {
        public let buildURL: (@Sendable (_ baseURL: String, _ isStreaming: Bool) throws -> String)?
        public let transformHeaders: (@Sendable (_ headers: [String: String?], _ providerOptions: SharedV4ProviderOptions?) async throws -> [String: String?])?
        public let transformBody: (@Sendable (_ body: [String: JSONValue], _ betas: Set<String>) -> [String: JSONValue])?

        public init(
            buildURL: (@Sendable (_ baseURL: String, _ isStreaming: Bool) throws -> String)? = nil,
            transformBody: (@Sendable (_ body: [String: JSONValue], _ betas: Set<String>) -> [String: JSONValue])? = nil,
            transformHeaders: (@Sendable (_ headers: [String: String?], _ providerOptions: SharedV4ProviderOptions?) async throws -> [String: String?])? = nil
        ) {
            self.buildURL = buildURL
            self.transformBody = transformBody
            self.transformHeaders = transformHeaders
        }
    }

    public let provider: String
    public let baseURL: String
    public let headers: @Sendable () async throws -> [String: String?]
    public let fetch: FetchFunction?
    public let supportedUrls: @Sendable () -> [String: [NSRegularExpression]]
    public let generateId: @Sendable () -> String
    public let requestTransform: RequestTransform
    public let supportsNativeStructuredOutput: Bool?
    public let supportsStrictTools: Bool?

    public init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () async throws -> [String: String?] = { [:] },
        fetch: FetchFunction? = nil,
        supportedUrls: @escaping @Sendable () -> [String: [NSRegularExpression]] = { [:] },
        generateId: @escaping @Sendable () -> String = defaultAnthropicId,
        requestTransform: RequestTransform = .init(),
        supportsNativeStructuredOutput: Bool? = nil,
        supportsStrictTools: Bool? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.supportedUrls = supportedUrls
        self.generateId = generateId
        self.requestTransform = requestTransform
        self.supportsNativeStructuredOutput = supportsNativeStructuredOutput
        self.supportsStrictTools = supportsStrictTools
    }
}

private struct AnthropicRequestArguments {
    let body: [String: JSONValue]
    let warnings: [SharedV4Warning]
    let betas: Set<String>
    let usesJsonResponseTool: Bool
    let toolNameMapping: AnthropicToolNameMapping
    let providerOptionsName: String
    let usedCustomProviderKey: Bool
}

public final class AnthropicMessagesLanguageModel: LanguageModelV4 {
    public let specificationVersion: String = "v4"

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

    private var providerOptionsName: String {
        let provider = config.provider
        if let dotIndex = provider.firstIndex(of: ".") {
            return String(provider[..<dotIndex])
        }
        return provider
    }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { config.supportedUrls() }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws
        -> LanguageModelV4GenerateResult
    {
        let prepared = try await prepareRequest(options: options)
        let requestURL = try buildRequestURL(isStreaming: false)
        let headers = try await getHeaders(betas: prepared.betas, additional: options.headers, providerOptions: options.providerOptions)

        let body = config.requestTransform.transformBody?(prepared.body, prepared.betas) ?? prepared.body

        let response = try await postJsonToAPI(
            url: requestURL,
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: anthropicFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(
                responseSchema: anthropicMessagesResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let usageAndContent = try mapResponseContent(
            response: response.value,
            citationDocuments: extractCitationDocuments(from: options.prompt),
            usesJsonResponseTool: prepared.usesJsonResponseTool,
            toolNameMapping: prepared.toolNameMapping,
            markCodeExecutionDynamic: hasDynamicFilteringWebToolWithoutCodeExecution(prepared.body)
        )

        let isJsonResponseFromTool = usageAndContent.isJsonResponseFromTool
        let providerMetadata = makeProviderMetadata(
            response: response.value,
            providerOptionsName: prepared.providerOptionsName,
            usedCustomProviderKey: prepared.usedCustomProviderKey
        )

        return LanguageModelV4GenerateResult(
            content: usageAndContent.content,
            finishReason: LanguageModelV4FinishReason(
                unified: mapAnthropicStopReason(
                    finishReason: response.value.stopReason,
                    isJsonResponseFromTool: isJsonResponseFromTool
                ),
                raw: response.value.stopReason
            ),
            usage: usageAndContent.usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV4RequestInfo(body: prepared.body),
            response: LanguageModelV4ResponseInfo(
                id: response.value.id,
                timestamp: nil,
                modelId: response.value.model,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws
        -> LanguageModelV4StreamResult
    {
        let prepared = try await prepareRequest(options: options, stream: true)

        let betas = prepared.betas

        var requestBody = prepared.body
        requestBody["stream"] = .bool(true)
        let transformedBody = config.requestTransform.transformBody?(requestBody, betas) ?? requestBody
        let headers = try await getHeaders(betas: betas, additional: options.headers, providerOptions: options.providerOptions)

        let requestURL = try buildRequestURL(isStreaming: true)
        let response = try await postJsonToAPI(
            url: requestURL,
            headers: headers,
            body: JSONValue.object(transformedBody),
            failedResponseHandler: anthropicFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(
                chunkSchema: anthropicMessagesChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let initialCitationDocuments = extractCitationDocuments(from: options.prompt)

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            let task = Task {
                var citationDocuments = initialCitationDocuments
                var contentBlocks: [Int: ContentBlockState] = [:]
                var blockType: String?
                var serverToolCalls: [String: String] = [:]
                var mcpToolCalls: [String: (toolName: String, providerMetadata: SharedV4ProviderMetadata)] = [:]
                var finishReason: LanguageModelV4FinishReason = .init(unified: .other, raw: nil)
                var usage = LanguageModelV4Usage()
                var usageState = AnthropicUsageState()
                var rawUsage: [String: JSONValue]? = nil
                var stopSequence: String? = nil
                var stopDetails: JSONValue? = nil
                var container: JSONValue = .null
                var contextManagement: JSONValue = .null
                var inputTransformations: [AnthropicInputTransformation]?
                var safeguardResults: [AnthropicSafeguardResult]?
                var isMessageOpen = false
                var activeMessageId: String?
                var invalidMessageSequence = false
                var isJsonResponseFromTool = false
                var hasWebSearchResults = false
                var fallbackWebCitations: [AnthropicCitation] = []

                do {
                    for try await chunk in response.value {
                        if invalidMessageSequence { continue }
                        switch chunk {
                        case .success(let event, let rawValue):
                            if options.includeRawChunks == true,
                                let rawJSON = try? jsonValue(from: rawValue)
                            {
                                continuation.yield(.raw(rawValue: rawJSON))
                            }

                            switch event {
                            case .ping:
                                continue

                            case .contentBlockStart(let value):
                                if case .toolUse(let tool) = value.contentBlock, prepared.usesJsonResponseTool && tool.name == "json" {
                                    isJsonResponseFromTool = true
                                }
                                if case .webSearchResult(let result) = value.contentBlock,
                                   case .array(let results) = result.content, !results.isEmpty { hasWebSearchResults = true }
                                if case .fallback = value.contentBlock {} else { blockType = contentBlockType(for: value.contentBlock) }
                                handleContentBlockStart(
                                    value,
                                    usesJsonResponseTool: prepared.usesJsonResponseTool,
                                    toolNameMapping: prepared.toolNameMapping,
                                    markCodeExecutionDynamic: hasDynamicFilteringWebToolWithoutCodeExecution(prepared.body),
                                    citationDocuments: &citationDocuments,
                                    contentBlocks: &contentBlocks,
                                    serverToolCalls: &serverToolCalls,
                                    mcpToolCalls: &mcpToolCalls,
                                    continuation: continuation
                                )

                            case .contentBlockDelta(let value):
                                handleContentBlockDelta(
                                    value,
                                    blockType: blockType,
                                    usesJsonResponseTool: prepared.usesJsonResponseTool,
                                    citationDocuments: citationDocuments,
                                    fallbackWebCitations: &fallbackWebCitations,
                                    contentBlocks: &contentBlocks,
                                    continuation: continuation
                                )

                            case .contentBlockStop(let value):
                                handleContentBlockStop(
                                    index: value.index,
                                    usesJsonResponseTool: prepared.usesJsonResponseTool,
                                    citationDocuments: citationDocuments,
                                    contentBlocks: &contentBlocks,
                                    continuation: continuation
                                )
                                blockType = nil

                            case .messageStart(let value):
                                if isMessageOpen {
                                    if activeMessageId == value.message.id { continue }
                                    invalidMessageSequence = true
                                    continuation.yield(.error(error: .error(InvalidResponseDataError(
                                        data: encodeToJSONValue(value),
                                        message: "Received message_start for message \(stringifyJSON(value.message.id.map(JSONValue.string))) while message \(stringifyJSON(activeMessageId.map(JSONValue.string))) is still open."
                                    ))))
                                    continue
                                }
                                isMessageOpen = true
                                activeMessageId = value.message.id
                                if let transformations = value.message.inputTransformations { inputTransformations = transformations }
                                if let usageInfo = value.message.usage {
                                    let usageMetadata = anthropicUsageMetadata(usageInfo)
                                    usageState.merge(.init(inputTokens: usageInfo.inputTokens, cacheCreationInputTokens: usageInfo.cacheCreationInputTokens ?? 0, cacheReadInputTokens: usageInfo.cacheReadInputTokens ?? 0))
                                    rawUsage = usageMetadata
                                    usage = convertAnthropicUsage(
                                        usageState.value,
                                        rawUsage: usageMetadata
                                    )
                                }

                                if let value = value.message.container { container = anthropicContainerMetadata(value) }

                                if let stopReason = value.message.stopReason {
                                    finishReason = LanguageModelV4FinishReason(
                                        unified: mapAnthropicStopReason(
                                            finishReason: stopReason,
                                            isJsonResponseFromTool: isJsonResponseFromTool
                                        ),
                                        raw: stopReason
                                    )
                                }
                                continuation.yield(
                                    .responseMetadata(
                                        id: value.message.id,
                                        modelId: value.message.model,
                                        timestamp: nil
                                    ))

                                continuation.yield(.custom(.init(kind: "anthropic.message_start", providerMetadata: [
                                    "anthropic": [
                                        "id": value.message.id.map(JSONValue.string) ?? .null,
                                        "model": value.message.model.map(JSONValue.string) ?? .null,
                                        "usage": .object(rawUsage ?? [:]),
                                    ]
                                ])))

                                if let content = value.message.content {
                                    for part in content {
                                        guard case .toolUse(let tool) = part else { continue }

                                        var providerMetadata: SharedV4ProviderMetadata? = nil
                                        if let caller = tool.caller {
                                            var callerObject: [String: JSONValue] = [
                                                "type": .string(caller.type)
                                            ]
                                            if let toolId = caller.toolId {
                                                callerObject["toolId"] = .string(toolId)
                                            }
                                            providerMetadata = [
                                                "anthropic": [
                                                    "caller": .object(callerObject)
                                                ]
                                            ]
                                        }

                                        continuation.yield(
                                            .toolInputStart(
                                                id: tool.id,
                                                toolName: tool.name,
                                                providerMetadata: nil,
                                                providerExecuted: nil,
                                                dynamic: nil,
                                                title: nil
                                            )
                                        )

                                        let inputStr = stringifyJSON(tool.input ?? .object([:]))
                                        continuation.yield(
                                            .toolInputDelta(
                                                id: tool.id,
                                                delta: inputStr,
                                                providerMetadata: nil
                                            )
                                        )

                                        continuation.yield(
                                            .toolInputEnd(
                                                id: tool.id,
                                                providerMetadata: nil
                                            )
                                        )

                                        let toolCall = LanguageModelV4ToolCall(
                                            toolCallId: tool.id,
                                            toolName: tool.name,
                                            input: inputStr,
                                            providerExecuted: nil,
                                            providerMetadata: providerMetadata
                                        )
                                        continuation.yield(.toolCall(toolCall))
                                    }
                                }

                            case .messageDelta(let value):
                                if let usageInfo = value.usage {
                                    let metadata = anthropicUsageMetadata(usageInfo)
                                    if var existing = rawUsage {
                                        for (key, value) in metadata {
                                            existing[key] = value
                                        }
                                        rawUsage = existing
                                    } else {
                                        rawUsage = metadata
                                    }
                                    usageState.merge(usageInfo)
                                    usage = convertAnthropicUsage(
                                        usageState.value,
                                        rawUsage: rawUsage
                                    )
                                }

                                let rawFinishReason = value.delta.stopReason
                                finishReason = LanguageModelV4FinishReason(
                                    unified: mapAnthropicStopReason(
                                        finishReason: rawFinishReason,
                                        isJsonResponseFromTool: isJsonResponseFromTool
                                    ),
                                    raw: rawFinishReason
                                )
                                stopSequence = value.delta.stopSequence
                                stopDetails = anthropicStopDetailsMetadata(value.delta.stopDetails)
                                container = anthropicContainerMetadata(value.delta.container)

                                if let transformations = value.inputTransformations { inputTransformations = transformations }
                                if let results = value.delta.safeguardResults { safeguardResults = results }
                                if let newContextManagement = value.contextManagement {
                                    contextManagement = anthropicContextManagementMetadata(newContextManagement)
                                }

                            case .messageStop:
                                isMessageOpen = false
                                activeMessageId = nil
                                var metadata: [String: JSONValue] = [:]
                                metadata["usage"] = rawUsage.map(JSONValue.object) ?? .null
                                metadata["stopSequence"] =
                                    stopSequence.map(JSONValue.string) ?? .null
                                if let stopDetails {
                                    metadata["stopDetails"] = stopDetails
                                }
                                metadata["iterations"] = anthropicIterationsMetadata(
                                    usageState.iterations
                                )
                                metadata["container"] = container
                                metadata["contextManagement"] = contextManagement
                                if let inputTransformations { metadata["inputTransformations"] = encodeToJSONValue(inputTransformations) }
                                if let safeguardResults { metadata["safeguardResults"] = encodeToJSONValue(safeguardResults) }
                                if !hasWebSearchResults {
                                    for citation in fallbackWebCitations {
                                        if let source = createCitationSource(from: citation, documents: citationDocuments) {
                                            continuation.yield(.source(source))
                                        }
                                    }
                                }
                                fallbackWebCitations.removeAll()

                                continuation.yield(
                                    .finish(
                                        finishReason: finishReason,
                                        usage: usage,
                                        providerMetadata: mergeProviderMetadata(
                                            metadata,
                                            providerOptionsName: prepared.providerOptionsName,
                                            usedCustomProviderKey: prepared.usedCustomProviderKey
                                        )
                                    )
                                )

                            case .error(let value):
                                continuation.yield(.error(error: .providerStreamError(createAnthropicStreamError(value.error))))

                            }

                        case .failure(let error, let rawValue):
                            if options.includeRawChunks == true, let rawValue,
                               let raw = try? jsonValue(from: rawValue) { continuation.yield(.raw(rawValue: raw)) }
                            continuation.yield(.error(error: .error(error)))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }

        let reader = AnthropicStreamReader(stream)
        var prefix: [LanguageModelV4StreamPart] = []
        if let start = try await reader.next() { prefix.append(start) }
        var first = try await reader.next()
        if let part = first, case .raw = part {
            prefix.append(part)
            first = try await reader.next()
        }
        if case .error(let error)? = first {
            if case .providerStreamError(let payload) = error {
                throw APICallError(message: payload.message, url: requestURL, requestBodyValues: requestBody,
                                   statusCode: payload.statusCode ?? 500, responseHeaders: response.responseHeaders,
                                   responseBody: stringifyJSON(payload.data), isRetryable: payload.isRetryable ?? false)
            }
            if case .error(let cause) = error { throw cause }
            throw InvalidResponseDataError(data: error.jsonValue, message: "Expected a normalized Anthropic stream error")
        }
        if let first { prefix.append(first) }
        reader.prepend(prefix)
        let consumerStream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(unfolding: { try await reader.next() })
        let requestInfo = LanguageModelV4RequestInfo(body: requestBody)
        let responseInfo = LanguageModelV4StreamResponseInfo(headers: response.responseHeaders)
        return LanguageModelV4StreamResult(
            stream: consumerStream, request: requestInfo, response: responseInfo)
    }

    // MARK: - Helpers

    private func mergeProviderOptions(
        canonical: AnthropicProviderOptions?,
        custom: AnthropicProviderOptions?
    ) -> AnthropicProviderOptions? {
        guard canonical != nil || custom != nil else { return nil }

        var merged = canonical ?? AnthropicProviderOptions()
        guard let custom else { return merged }

        if let sendReasoning = custom.sendReasoning {
            merged.sendReasoning = sendReasoning
        }
        if let structuredOutputMode = custom.structuredOutputMode {
            merged.structuredOutputMode = structuredOutputMode
        }
        if let thinking = custom.thinking {
            merged.thinking = thinking
        }
        if let disableParallelToolUse = custom.disableParallelToolUse {
            merged.disableParallelToolUse = disableParallelToolUse
        }
        if let cacheControl = custom.cacheControl {
            merged.cacheControl = cacheControl
        }
        if let metadata = custom.metadata {
            merged.metadata = metadata
        }
        if let mcpServers = custom.mcpServers {
            merged.mcpServers = mcpServers
        }
        if let container = custom.container {
            merged.container = container
        }
        if let toolStreaming = custom.toolStreaming {
            merged.toolStreaming = toolStreaming
        }
        if let effort = custom.effort {
            merged.effort = effort
        }
        if let taskBudget = custom.taskBudget {
            merged.taskBudget = taskBudget
        }
        if let speed = custom.speed { merged.speed = speed }
        if let serviceTier = custom.serviceTier { merged.serviceTier = serviceTier }
        if let safeguards = custom.safeguards { merged.safeguards = safeguards }
        if let compaction = custom.compaction { merged.compaction = compaction }
        if let inferenceGeo = custom.inferenceGeo {
            merged.inferenceGeo = inferenceGeo
        }
        if let fallbacks = custom.fallbacks {
            merged.fallbacks = fallbacks
        }
        if let contextManagement = custom.contextManagement {
            merged.contextManagement = contextManagement
        }
        if let anthropicBeta = custom.anthropicBeta {
            merged.anthropicBeta = anthropicBeta
        }

        return merged
    }

    private func prepareRequest(options: LanguageModelV4CallOptions, stream: Bool = false) async throws
        -> AnthropicRequestArguments
    {
        let userSuppliedBetas = try await getBetasFromHeaders(options.headers)
        var warnings: [SharedV4Warning] = []

        if options.frequencyPenalty != nil {
            warnings.append(.unsupported(feature: "frequencyPenalty", details: nil))
        }
        if options.presencePenalty != nil {
            warnings.append(.unsupported(feature: "presencePenalty", details: nil))
        }
        if options.seed != nil {
            warnings.append(.unsupported(feature: "seed", details: nil))
        }

        var temperature = options.temperature
        if let value = temperature, value > 1 {
            warnings.append(
                .unsupported(
                    feature: "temperature",
                    details: "\(value) exceeds anthropic maximum of 1.0. clamped to 1.0"
                ))
            temperature = 1
        } else if let value = temperature, value < 0 {
            warnings.append(
                .unsupported(
                    feature: "temperature",
                    details: "\(value) is below anthropic minimum of 0. clamped to 0"
                ))
            temperature = 0
        }

        if case let .json(schema, _, _) = options.responseFormat, schema == nil {
            warnings.append(
                .unsupported(
                    feature: "responseFormat",
                    details: "JSON response format requires a schema. The response format is ignored."
                )
            )
        }

        let providerOptionsName = self.providerOptionsName

        let canonicalOptions = try await parseProviderOptions(
            provider: "anthropic",
            providerOptions: options.providerOptions,
            schema: anthropicProviderOptionsSchema
        )

        let customOptions: AnthropicProviderOptions? =
            providerOptionsName != "anthropic"
            ? try await parseProviderOptions(
                provider: providerOptionsName,
                providerOptions: options.providerOptions,
                schema: anthropicProviderOptionsSchema
            )
            : nil

        let usedCustomProviderKey = customOptions != nil

        var anthropicOptions = mergeProviderOptions(
            canonical: canonicalOptions,
            custom: customOptions
        )

        let capabilities = getAnthropicModelCapabilities(modelId: modelIdentifier.rawValue)
        if !capabilities.isKnownModel && options.maxOutputTokens == nil {
            warnings.append(.compatibility(
                feature: "maxOutputTokens",
                details: "The model \"\(modelId)\" is unknown. The max output tokens have been limited to \(capabilities.maxOutputTokens). Set maxOutputTokens explicitly to override this limit."
            ))
        }
        var topK = options.topK
        var topP = options.topP

        if capabilities.rejectsSamplingParameters {
            if temperature != nil {
                warnings.append(.unsupported(
                    feature: "temperature",
                    details: "temperature is not supported by \(modelIdentifier.rawValue) and will be ignored"
                ))
                temperature = nil
            }
            if topK != nil {
                warnings.append(.unsupported(
                    feature: "topK",
                    details: "topK is not supported by \(modelIdentifier.rawValue) and will be ignored"
                ))
                topK = nil
            }
            if topP != nil {
                warnings.append(.unsupported(
                    feature: "topP",
                    details: "topP is not supported by \(modelIdentifier.rawValue) and will be ignored"
                ))
                topP = nil
            }
        }

        let isAnthropicModel = capabilities.isKnownModel || modelIdentifier.rawValue.contains("claude-")
        let supportsStructuredOutput =
            (config.supportsNativeStructuredOutput ?? true) && capabilities.supportsStructuredOutput

        let structuredOutputMode = anthropicOptions?.structuredOutputMode ?? .auto
        var useStructuredOutput =
            structuredOutputMode == .outputFormat
            || (structuredOutputMode == .auto && supportsStructuredOutput)

        let responseFormatSchema: JSONValue? =
            if case let .json(schema, _, _) = options.responseFormat { schema } else { nil }

        if !useStructuredOutput, capabilities.rejectsForcedToolUse, supportsStructuredOutput, responseFormatSchema != nil {
            warnings.append(.unsupported(
                feature: "providerOptions.anthropic.structuredOutputMode",
                details: "structuredOutputMode 'jsonTool' is not supported by \(modelId) because it rejects forced tool use. Using 'outputFormat' instead."
            ))
            useStructuredOutput = true
        }

        let jsonResponseTool: LanguageModelV4FunctionTool? =
            (options.responseFormat != nil
             && responseFormatSchema != nil
             && useStructuredOutput == false)
            ? LanguageModelV4FunctionTool(
                name: "json",
                inputSchema: responseFormatSchema!,
                description: "Respond with a JSON object."
            )
            : nil

        let usesJsonResponseTool = jsonResponseTool != nil
        if usesJsonResponseTool && anthropicOptions?.disableParallelToolUse == false {
            warnings.append(.unsupported(
                feature: "providerOptions.anthropic.disableParallelToolUse",
                details: "`disableParallelToolUse: false` is ignored when using the JSON response tool. Parallel tool use is disabled to ensure a single coherent JSON tool call."
            ))
        }
        let contextManagement = anthropicOptions?.contextManagement
        if contextManagement != nil && anthropicOptions?.compaction != nil {
            throw InvalidArgumentError(argument: "providerOptions", message: "Anthropic provider options `compaction` and `contextManagement` cannot be used together.")
        }
        let defaultEagerInputStreaming = stream && (anthropicOptions?.toolStreaming ?? true)
        let cacheControlValidator = CacheControlValidator()

        let toolNameMapping = AnthropicToolNameMapping.create(
            tools: options.tools,
            providerToolNames: [
                "anthropic.advisor_20260301": "advisor",
                "anthropic.code_execution_20250522": "code_execution",
                "anthropic.code_execution_20250825": "code_execution",
                "anthropic.code_execution_20260120": "code_execution",
                "anthropic.computer_20241022": "computer",
                "anthropic.computer_20250124": "computer",
                "anthropic.computer_20251124": "computer",
                "anthropic.computer_toolset_20260801": "computer",
                "anthropic.text_editor_20241022": "str_replace_editor",
                "anthropic.text_editor_20250124": "str_replace_editor",
                "anthropic.text_editor_20250429": "str_replace_based_edit_tool",
                "anthropic.text_editor_20250728": "str_replace_based_edit_tool",
                "anthropic.bash_20241022": "bash",
                "anthropic.bash_20250124": "bash",
                "anthropic.memory_20250818": "memory",
                "anthropic.web_search_20250305": "web_search",
                "anthropic.web_search_20260209": "web_search",
                "anthropic.web_fetch_20250910": "web_fetch",
                "anthropic.web_fetch_20260209": "web_fetch",
                "anthropic.web_fetch_20260318": "web_fetch",
                "anthropic.web_search_20260318": "web_search",
                "anthropic.tool_search_regex_20251119": "tool_search_tool_regex",
                "anthropic.tool_search_bm25_20251119": "tool_search_tool_bm25",
            ]
        )

        let toolsetNames = (options.tools ?? []).reduce(into: [String: String]()) { names, tool in
            if case .provider(let tool) = tool, tool.id == "anthropic.computer_toolset_20260801" { names[tool.name] = "computer" }
        }
        var conversionWarnings = warnings
        let conversion = try await convertToAnthropicMessagesPrompt(
            prompt: options.prompt,
            sendReasoning: anthropicOptions?.sendReasoning ?? true,
            toolNameMapping: toolNameMapping,
            warnings: &conversionWarnings,
            cacheControlValidator: cacheControlValidator,
            toolsetNames: toolsetNames
        )
        warnings = conversionWarnings

        if let reasoning = options.reasoning,
           isCustomReasoning(reasoning),
           anthropicOptions?.effort == nil
        {
            var reasoningWarnings: [SharedV4Warning] = []
            if let reasoningConfig = resolveAnthropicReasoningConfig(
                reasoning: reasoning,
                capabilities: capabilities,
                warnings: &reasoningWarnings
            ) {
                if anthropicOptions == nil {
                    anthropicOptions = AnthropicProviderOptions()
                }
                if anthropicOptions?.thinking == nil {
                    anthropicOptions?.thinking = reasoningConfig.thinking
                }
                if let effort = reasoningConfig.effort,
                   anthropicOptions?.thinking?.type != .disabled
                {
                    anthropicOptions?.effort = effort
                }
            }
            warnings.append(contentsOf: reasoningWarnings)
        }

        if capabilities.rejectsThinkingDisabled && anthropicOptions?.thinking?.type == .disabled {
            if capabilities.supportsBetweenToolsThinking {
                warnings.append(.unsupported(feature: "providerOptions.anthropic.thinking", details: "thinking cannot be disabled for \(modelId). Using 'between_tools' thinking, the lowest thinking setting, instead."))
                anthropicOptions?.thinking = .init(type: .betweenTools)
            } else {
                warnings.append(.unsupported(feature: "providerOptions.anthropic.thinking", details: "thinking cannot be disabled for \(modelId); it always uses adaptive thinking. The thinking setting has been removed. Lower 'effort' to reduce thinking."))
                anthropicOptions?.thinking = nil
            }
        }
        if capabilities.rejectsBudgetThinking && anthropicOptions?.thinking?.type == .enabled {
            let detail = capabilities.rejectsThinkingDisabled ? "; it always uses adaptive thinking" : ""
            warnings.append(.unsupported(feature: "providerOptions.anthropic.thinking", details: "budget-based thinking is not supported by \(modelId)\(detail). Using adaptive thinking instead. Use 'effort' to control how much the model thinks."))
            anthropicOptions?.thinking = .init(type: .adaptive)
        }
        if capabilities.rejectsThinkingDisabledAboveHighEffort,
           anthropicOptions?.thinking?.type == .disabled,
           let effort = anthropicOptions?.effort, effort == .xhigh || effort == .max {
            warnings.append(.unsupported(feature: "providerOptions.anthropic.effort", details: "effort '\(effort.rawValue)' is not supported by \(modelId) when thinking is disabled. The effort has been lowered to 'high'."))
            anthropicOptions?.effort = .high
        }
        if anthropicOptions?.thinking?.type == .betweenTools,
           let effort = anthropicOptions?.effort, effort == .xhigh || effort == .max {
            warnings.append(.unsupported(feature: "providerOptions.anthropic.effort", details: "effort '\(effort.rawValue)' is not supported with 'between_tools' thinking. The effort has been lowered to 'high'."))
            anthropicOptions?.effort = .high
        }

        var betas = conversion.betas

        var args: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(conversion.prompt.messages.map { $0.toJSONValue() }),
        ]

        if let system = conversion.prompt.system {
            args["system"] = .array(system)
        }

        let inputMaxOutputTokens = options.maxOutputTokens
        let maxTokens = inputMaxOutputTokens ?? capabilities.maxOutputTokens

        args["max_tokens"] = .number(Double(maxTokens))

        // Standard sampling settings
        if let temperature {
            args["temperature"] = .number(temperature)
        }

        if let topK {
            args["top_k"] = .number(Double(topK))
        }

        let thinkingMode = anthropicOptions?.thinking?.type
        let isThinking = thinkingMode == .enabled || thinkingMode == .adaptive || thinkingMode == .betweenTools
        var thinkingBudget = thinkingMode == .enabled ? anthropicOptions?.thinking?.budgetTokens : nil

        if !isThinking, isAnthropicModel, topP != nil, temperature != nil {
            warnings.append(
                .unsupported(
                    feature: "topP",
                    details: "topP is not supported when temperature is set. topP is ignored."
                )
            )
            topP = nil
        }

        if let topP {
            args["top_p"] = .number(topP)
        }

        if let stopSequences = options.stopSequences {
            args["stop_sequences"] = .array(stopSequences.map(JSONValue.string))
        }

        // Thinking (both manual and adaptive modes suppress sampling params)
        if isThinking {
            if thinkingMode == .enabled, thinkingBudget == nil {
                warnings.append(
                    .compatibility(
                        feature: "extended thinking",
                        details:
                            "thinking budget is required when thinking is enabled. using default budget of 1024 tokens."
                    )
                )
                thinkingBudget = 1024
            }

            if temperature != nil {
                warnings.append(
                    .unsupported(
                        feature: "temperature",
                        details: "temperature is not supported when thinking is enabled"
                    )
                )
                args.removeValue(forKey: "temperature")
            }
            if topK != nil {
                warnings.append(
                    .unsupported(
                        feature: "topK",
                        details: "topK is not supported when thinking is enabled"
                    )
                )
                args.removeValue(forKey: "top_k")
            }
            if topP != nil {
                warnings.append(
                    .unsupported(
                        feature: "topP",
                        details: "topP is not supported when thinking is enabled"
                    )
                )
                args.removeValue(forKey: "top_p")
            }

            args["max_tokens"] = .number(Double(maxTokens) + (thinkingBudget ?? 0))
        }

        let binding = anthropicOptions?.thinking?.blockBinding
        if isThinking || thinkingMode == .disabled || binding != nil {
            var thinking: [String: JSONValue] = [:]
            if let thinkingMode { thinking["type"] = .string(thinkingMode.rawValue) }
            if let thinkingBudget { thinking["budget_tokens"] = .number(thinkingBudget) }
            if thinkingMode == .adaptive, let display = anthropicOptions?.thinking?.display {
                thinking["display"] = .string(display.rawValue)
                if display == .updates { betas.insert("thinking-display-updates-2026-08-18") }
            }
            if let binding {
                thinking["block_binding"] = .object(["prefix_mismatch_behavior": .string(binding.prefixMismatchBehavior.rawValue)])
                betas.insert("thinking-binding-controls-2026-08-01")
            }
            args["thinking"] = .object(thinking)
        }

        // limit max output tokens for known models (including thinking budget)
        if capabilities.isKnownModel,
            case .number(let rawMaxTokensValue) = args["max_tokens"],
            rawMaxTokensValue > Double(capabilities.maxOutputTokens)
        {
            if inputMaxOutputTokens != nil {
                warnings.append(
                    .unsupported(
                        feature: "maxOutputTokens",
                        details:
                            "\(Int(rawMaxTokensValue)) (maxOutputTokens + thinkingBudget) is greater than \(modelIdentifier.rawValue) \(capabilities.maxOutputTokens) max output tokens. The max output tokens have been limited to \(capabilities.maxOutputTokens)."
                    )
                )
            }
            args["max_tokens"] = .number(Double(capabilities.maxOutputTokens))
        }

        // Top-level cache control (automatic caching)
        if let cacheControl = anthropicOptions?.cacheControl {
            var payload = cacheControl.additionalFields
            if let type = cacheControl.type {
                payload["type"] = .string(type)
            }
            if let ttl = cacheControl.ttl {
                payload["ttl"] = .string(ttl.rawValue)
            }
            if !payload.isEmpty {
                args["cache_control"] = .object(payload)
            }
        }

        var outputConfig: [String: JSONValue] = [:]
        if let effort = anthropicOptions?.effort {
            outputConfig["effort"] = .string(effort.rawValue)
        }

        if let taskBudget = anthropicOptions?.taskBudget {
            var payload: [String: JSONValue] = [
                "type": .string(taskBudget.type.rawValue),
                "total": .number(Double(taskBudget.total)),
            ]
            if let remaining = taskBudget.remaining {
                payload["remaining"] = .number(Double(remaining))
            }
            outputConfig["task_budget"] = .object(payload)
            betas.insert("task-budgets-2026-03-13")
        }

        // Speed (fast mode, Opus 4.6 only)
        if let speed = anthropicOptions?.speed {
            args["speed"] = .string(speed.rawValue)
            if speed == .fast {
                betas.insert("fast-mode-2026-02-01")
            }
        }

        if let tier = anthropicOptions?.serviceTier { args["service_tier"] = .string(tier.rawValue) }
        if let compaction = anthropicOptions?.compaction {
            var payload: [String: JSONValue] = ["type": .string(compaction.type)]
            if let instructions = compaction.instructions { payload["instructions"] = .string(instructions) }
            args["compaction"] = .object(payload)
            betas.insert("compact-2026-09-04")
        }
        if let safeguards = anthropicOptions?.safeguards, !safeguards.isEmpty {
            args["safeguards"] = .array(safeguards.map { safeguard in
                var payload: [String: JSONValue] = ["type": .string(safeguard.type)]
                if let context = safeguard.classifierContext { payload["classifier_context"] = .object(context) }
                return .object(payload)
            })
            betas.insert("dangerous-tool-use-2026-09-03")
        }

        if let inferenceGeo = anthropicOptions?.inferenceGeo {
            args["inference_geo"] = .string(inferenceGeo.rawValue)
        }

        if let fallbacks = anthropicOptions?.fallbacks {
            switch fallbacks {
            case .default:
                args["fallbacks"] = .string("default")
                betas.insert("server-side-fallback-2026-07-01")
            case .models(let fallbacks) where !fallbacks.isEmpty:
                args["fallbacks"] = .array(fallbacks.map { fallback in
                var payload: [String: JSONValue] = ["model": .string(fallback.model)]
                if let maxTokens = fallback.maxTokens {
                    payload["max_tokens"] = .number(Double(maxTokens))
                }
                if let thinking = fallback.thinking {
                    payload["thinking"] = .object(thinking)
                }
                if let outputConfig = fallback.outputConfig {
                    payload["output_config"] = .object(outputConfig)
                }
                if let speed = fallback.speed {
                    payload["speed"] = .string(speed.rawValue)
                }
                return .object(payload)
            })
                betas.insert("server-side-fallback-2026-06-01")
            case .models:
                break
            }
        }

        if let userId = anthropicOptions?.metadata?.userId {
            args["metadata"] = .object(["user_id": .string(userId)])
        }

        // Native structured outputs
        let usingNativeOutputFormat =
            useStructuredOutput && responseFormatSchema != nil
        if usingNativeOutputFormat, let schema = responseFormatSchema {
            outputConfig["format"] = .object([
                "type": .string("json_schema"),
                "schema": sanitizeAnthropicJSONSchema(schema),
            ])
        }

        if !outputConfig.isEmpty {
            args["output_config"] = .object(outputConfig)
        }

        // MCP servers
        if let servers = anthropicOptions?.mcpServers, !servers.isEmpty {
            betas.insert("mcp-client-2025-04-04")
            args["mcp_servers"] = .array(
                servers.map { server in
                    var payload: [String: JSONValue] = [
                        "type": .string(server.type.rawValue),
                        "name": .string(server.name),
                        "url": .string(server.url),
                    ]
                    if let authorizationToken = server.authorizationToken {
                        payload["authorization_token"] = .string(authorizationToken)
                    }
                    if let config = server.toolConfiguration {
                        var toolConfig: [String: JSONValue] = [:]
                        if let allowedTools = config.allowedTools {
                            toolConfig["allowed_tools"] = .array(allowedTools.map(JSONValue.string))
                        }
                        if let enabled = config.enabled {
                            toolConfig["enabled"] = .bool(enabled)
                        }
                        payload["tool_configuration"] = .object(toolConfig)
                    }
                    return .object(payload)
                }
            )
        }

        // Container: ID-only (string) or ID+skills (object)
        if let container = anthropicOptions?.container {
            if let skills = container.skills, !skills.isEmpty {
                betas.insert("code-execution-2025-08-25")
                betas.insert("skills-2025-10-02")
                betas.insert("files-api-2025-04-14")

                if options.tools?.contains(where: { tool in
                    guard case .provider(let providerTool) = tool else { return false }
                    return providerTool.id == "anthropic.code_execution_20250825"
                        || providerTool.id == "anthropic.code_execution_20260120"
                }) != true {
                    warnings.append(.other(message: "code execution tool is required when using skills"))
                }

                let payloads: [JSONValue] = try skills.map { skill in
                    let skillId: String
                    if skill.type == .custom {
                        skillId = try resolveProviderReference(reference: skill.providerReference ?? [:], provider: "anthropic")
                    } else {
                        skillId = skill.skillId ?? ""
                    }
                    var payload: [String: JSONValue] = ["type": .string(skill.type.rawValue), "skill_id": .string(skillId)]
                    if let version = skill.version { payload["version"] = .string(version) }
                    return .object(payload)
                }
                var payload: [String: JSONValue] = ["skills": .array(payloads)]
                if let id = container.id { payload["id"] = .string(id) }
                args["container"] = .object(payload)
            } else if let id = container.id {
                args["container"] = .string(id)
            }
        }

        // Context management
        if let contextManagement {
            betas.insert("context-management-2025-06-27")
            let edits: [JSONValue] = contextManagement.edits.compactMap { edit in
                switch edit {
                case .clearToolUses20250919(let settings):
                    var payload: [String: JSONValue] = [
                        "type": .string("clear_tool_uses_20250919")
                    ]
                    if let trigger = settings.trigger {
                        payload["trigger"] = .object([
                            "type": .string(trigger.type.rawValue),
                            "value": .number(trigger.value),
                        ])
                    }
                    if let keep = settings.keep {
                        payload["keep"] = .object([
                            "type": .string(keep.type),
                            "value": .number(keep.value),
                        ])
                    }
                    if let clearAtLeast = settings.clearAtLeast {
                        payload["clear_at_least"] = .object([
                            "type": .string(clearAtLeast.type),
                            "value": .number(clearAtLeast.value),
                        ])
                    }
                    if let clearToolInputs = settings.clearToolInputs {
                        payload["clear_tool_inputs"] = .bool(clearToolInputs)
                    }
                    if let excludeTools = settings.excludeTools {
                        payload["exclude_tools"] = .array(excludeTools.map(JSONValue.string))
                    }
                    return .object(payload)

                case .clearThinking20251015(let settings):
                    var payload: [String: JSONValue] = [
                        "type": .string("clear_thinking_20251015")
                    ]
                    if let keep = settings.keep {
                        switch keep {
                        case .all:
                            payload["keep"] = .string("all")
                        case .thinkingTurns(let value):
                            payload["keep"] = .object([
                                "type": .string("thinking_turns"),
                                "value": .number(value),
                            ])
                        }
                    }
                    return .object(payload)

                case .compact20260112(let settings):
                    var payload: [String: JSONValue] = [
                        "type": .string("compact_20260112")
                    ]
                    if let trigger = settings.trigger {
                        payload["trigger"] = .object([
                            "type": .string(trigger.type),
                            "value": .number(trigger.value),
                        ])
                    }
                    if let pause = settings.pauseAfterCompaction {
                        payload["pause_after_compaction"] = .bool(pause)
                    }
                    if let instructions = settings.instructions {
                        payload["instructions"] = .string(instructions)
                    }
                    return .object(payload)
                }
            }

            if contextManagement.edits.contains(where: { $0.type == "compact_20260112" }) {
                betas.insert("compact-2026-01-12")
            }

            args["context_management"] = .object(["edits": .array(edits)])
        }

        let preparedTools = try await prepareAnthropicTools(
            tools: jsonResponseTool != nil
                ? (options.tools ?? []) + [.function(jsonResponseTool!)]
                : options.tools,
            toolChoice: jsonResponseTool != nil ? .required : options.toolChoice,
            disableParallelToolUse: jsonResponseTool != nil ? true : anthropicOptions?.disableParallelToolUse,
            supportsStructuredOutput: jsonResponseTool == nil ? supportsStructuredOutput : false,
            supportsStrictTools: (config.supportsStrictTools ?? true) && capabilities.supportsStructuredOutput,
            rejectsForcedToolUse: capabilities.rejectsForcedToolUse || thinkingMode == .enabled,
            cacheControlValidator: cacheControlValidator,
            defaultEagerInputStreaming: defaultEagerInputStreaming
        )

        warnings.append(contentsOf: preparedTools.warnings)
        warnings.append(contentsOf: cacheControlValidator.getWarnings())
        betas.formUnion(preparedTools.betas)

        // Union user-supplied betas (header sources + typed providerOption)
        // into the SDK's auto-collected set. Trim/lowercase the typed array
        // for CRLF defense; `getBetasFromHeaders` already normalizes headers.
        betas.formUnion(userSuppliedBetas)
        for raw in anthropicOptions?.anthropicBeta ?? [] {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !value.isEmpty {
                betas.insert(value)
            }
        }

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
            usesJsonResponseTool: usesJsonResponseTool,
            toolNameMapping: toolNameMapping,
            providerOptionsName: providerOptionsName,
            usedCustomProviderKey: usedCustomProviderKey
        )
    }

    private func buildRequestURL(isStreaming: Bool) throws -> String {
        if let builder = config.requestTransform.buildURL {
            return try builder(config.baseURL, isStreaming)
        }
        return "\(config.baseURL)/messages"
    }

    private func getHeaders(betas: Set<String>, additional: [String: String]?, providerOptions: SharedV4ProviderOptions?) async throws -> [String: String] {
        var combined: [String: String?] = try await config.headers()
        if let additional {
            combined = combineHeaders(combined, additional.mapValues { Optional($0) })
        }
        if !betas.isEmpty {
            // Written last to overwrite any raw `anthropic-beta` header
            // in `additional`; user values were already harvested into
            // `betas` via `getBetasFromHeaders`. Matches upstream order.
            combined = combineHeaders(
                combined, ["anthropic-beta": betas.sorted().joined(separator: ",")])
        }
        if let transform = config.requestTransform.transformHeaders {
            combined = try await transform(combined, providerOptions)
        }
        return combined.compactMapValues { $0 }
    }

    /// Harvests `anthropic-beta` from `config.headers` and `requestHeaders`,
    /// splitting on `,` and lower-casing each entry. Mirrors the upstream
    /// TypeScript `getBetasFromHeaders`.
    private func getBetasFromHeaders(
        _ requestHeaders: [String: String]?
    ) async throws -> Set<String> {
        let configHeaders = try await config.headers()
        let configBetaHeader = configHeaders["anthropic-beta"].flatMap { $0 } ?? ""
        let requestBetaHeader = requestHeaders?["anthropic-beta"] ?? ""

        var betas: Set<String> = []
        for source in [configBetaHeader, requestBetaHeader] {
            for raw in source.split(separator: ",", omittingEmptySubsequences: true) {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !value.isEmpty {
                    betas.insert(value)
                }
            }
        }
        return betas
    }

    private struct AnthropicReasoningConfig {
        let thinking: AnthropicThinkingOptions?
        let effort: AnthropicEffort?
    }

    private func resolveAnthropicReasoningConfig(
        reasoning: LanguageModelV4ReasoningEffort,
        capabilities: AnthropicModelCapabilities,
        warnings: inout [SharedV4Warning]
    ) -> AnthropicReasoningConfig? {
        guard isCustomReasoning(reasoning) else {
            return nil
        }

        if reasoning == .none {
            if capabilities.supportsBetweenToolsThinking {
                return .init(thinking: .init(type: .betweenTools), effort: nil)
            }
            if capabilities.rejectsThinkingDisabled {
                warnings.append(.compatibility(
                    feature: "reasoning",
                    details: "reasoning 'none' is not supported by \(modelId); it always uses adaptive thinking. Using effort 'low' to minimize thinking instead."
                ))
                return .init(thinking: nil, effort: .low)
            }
            return AnthropicReasoningConfig(
                thinking: AnthropicThinkingOptions(type: .disabled),
                effort: nil
            )
        }

        if capabilities.supportsAdaptiveThinking {
            let effort = mapReasoningToProviderEffort(
                reasoning: reasoning,
                effortMap: [
                    .minimal: AnthropicEffort.low.rawValue,
                    .low: AnthropicEffort.low.rawValue,
                    .medium: AnthropicEffort.medium.rawValue,
                    .high: AnthropicEffort.high.rawValue,
                    .xhigh: capabilities.supportsXhighEffort
                        ? AnthropicEffort.xhigh.rawValue
                        : AnthropicEffort.max.rawValue,
                    .max: AnthropicEffort.max.rawValue,
                ],
                warnings: &warnings
            )

            return AnthropicReasoningConfig(
                thinking: AnthropicThinkingOptions(type: .adaptive, display: .summarized),
                effort: effort.flatMap(AnthropicEffort.init(rawValue:))
            )
        }

        guard let budgetTokens = mapReasoningToProviderBudget(
            reasoning: reasoning,
            maxOutputTokens: capabilities.maxOutputTokens,
            maxReasoningBudget: capabilities.maxOutputTokens,
            warnings: &warnings
        ) else {
            return nil
        }

        return AnthropicReasoningConfig(
            thinking: AnthropicThinkingOptions(type: .enabled, budgetTokens: Double(budgetTokens)),
            effort: nil
        )
    }

    private func mapResponseContent(
        response: AnthropicMessagesResponse,
        citationDocuments: [CitationDocument],
        usesJsonResponseTool: Bool,
        toolNameMapping: AnthropicToolNameMapping,
        markCodeExecutionDynamic: Bool
    ) throws -> (content: [LanguageModelV4Content], usage: LanguageModelV4Usage, isJsonResponseFromTool: Bool) {
        var isJsonResponseFromTool = false
        let hasWebSearchResults = response.content.contains { part in
            if case .webSearchResult(let value) = part, case .array(let results) = value.content { return !results.isEmpty }
            return false
        }
        var content: [LanguageModelV4Content] = []
        var serverToolCalls: [String: String] = [:]
        var mcpToolCalls: [String: (toolName: String, providerMetadata: SharedV4ProviderMetadata)] = [:]
        var citationDocuments = citationDocuments

        for part in response.content {
            switch part {
            case .text(let value):
                if usesJsonResponseTool {
                    continue
                }

                let citations = value.citations ?? []
                content.append(.text(LanguageModelV4Text(
                    text: value.text,
                    citations: citations.isEmpty ? nil : citations.map { mapCitation($0, documents: citationDocuments) },
                    providerMetadata: citations.isEmpty ? nil : ["anthropic": ["citations": encodeToJSONValue(citations) ?? .array([])]]
                )))

                if let citations = value.citations {
                    for citation in citations {
                        if case .webSearchResultLocation = citation, hasWebSearchResults { continue }
                        if let source = createCitationSource(
                            from: citation, documents: citationDocuments)
                        {
                            content.append(.source(source))
                        }
                    }
                }

            case .thinking(let value):
                var metadata: SharedV4ProviderMetadata? = nil
                if let signature = value.signature {
                    metadata = [
                        "anthropic": ["signature": .string(signature)]
                    ]
                }
                content.append(
                    .reasoning(
                        LanguageModelV4Reasoning(text: value.thinking, providerMetadata: metadata)))

            case .redactedThinking(let value):
                let metadata: SharedV4ProviderMetadata = [
                    "anthropic": ["redactedData": .string(value.data)]
                ]
                content.append(
                    .reasoning(LanguageModelV4Reasoning(text: "", providerMetadata: metadata)))

            case .compaction(let value):
                guard let compaction = value.content, !compaction.isEmpty else { continue }
                var metadata: [String: JSONValue] = ["type": .string("compaction")]
                if let signature = value.signature { metadata["signature"] = .string(signature) }
                content.append(.text(.init(text: compaction, providerMetadata: ["anthropic": metadata])))

            case .fallback(let value):
                if case .object(let metadata) = encodeToJSONValue(value) {
                    content.append(.custom(.init(kind: "anthropic.fallback", providerMetadata: ["anthropic": metadata])))
                }
            case .containerUpload(let value):
                content.append(.custom(.init(kind: "anthropic.container_upload", providerMetadata: ["anthropic": ["fileId": .string(value.fileId)]])))

            case .toolUse(let value):
                let isJsonResponseTool = usesJsonResponseTool && value.name == "json"
                if isJsonResponseTool {
                    isJsonResponseFromTool = true
                    content.append(.text(LanguageModelV4Text(text: stringifyJSON(value.input))))
                } else {
                    var providerMetadata: SharedV4ProviderMetadata? = nil
                    if let caller = value.caller {
                        var callerObject: [String: JSONValue] = [
                            "type": .string(caller.type)
                        ]
                        if let toolId = caller.toolId {
                            callerObject["toolId"] = .string(toolId)
                        }
                        providerMetadata = [
                            "anthropic": [
                                "caller": .object(callerObject)
                            ]
                        ]
                    }

                    let input: JSONValue?
                    let toolName: String
                    if let toolset = value.toolsetName {
                        input = toolsetInput(member: value.name, input: value.input ?? .object([:]))
                        toolName = toolNameMapping.toCustomToolName(toolset)
                        var metadata = providerMetadata ?? [:]
                        var anthropic = metadata["anthropic"] ?? [:]
                        anthropic["toolsetName"] = .string(toolset)
                        metadata["anthropic"] = anthropic
                        providerMetadata = metadata
                    } else {
                        input = value.input
                        toolName = value.name
                    }
                    let toolCall = LanguageModelV4ToolCall(
                        toolCallId: value.id, toolName: toolName,
                        input: stringifyJSON(input), providerMetadata: providerMetadata
                    )
                    content.append(.toolCall(toolCall))
                }

            case .serverToolUse(let value):
                if value.name == "text_editor_code_execution" || value.name == "bash_code_execution" {
                    var inputToSerialize: JSONValue?
                    if case .object(let inputObject) = value.input {
                        var merged = inputObject
                        merged["type"] = .string(value.name)
                        inputToSerialize = .object(merged)
                    } else {
                        inputToSerialize = .object(["type": .string(value.name)])
                    }

                    let toolCall = LanguageModelV4ToolCall(
                        toolCallId: value.id,
                        toolName: toolNameMapping.toCustomToolName("code_execution"),
                        input: stringifyJSON(inputToSerialize),
                        providerExecuted: true,
                        dynamic: markCodeExecutionDynamic && (value.name == "code_execution" || value.name == "bash_code_execution" || value.name == "text_editor_code_execution") ? true : nil,
                        providerMetadata: callerMetadata(value.caller)
                    )
                    content.append(.toolCall(toolCall))
                } else if value.name == "web_search" || value.name == "code_execution"
                            || value.name == "web_fetch" {
                    var inputToSerialize = value.input
                    if value.name == "code_execution",
                       case .object(let inputObject) = value.input,
                       inputObject["code"] != nil,
                       inputObject["type"] == nil {
                        var injected = inputObject
                        injected["type"] = .string("programmatic-tool-call")
                        inputToSerialize = .object(injected)
                    }

                    let toolCall = LanguageModelV4ToolCall(
                        toolCallId: value.id,
                        toolName: toolNameMapping.toCustomToolName(value.name),
                        input: stringifyJSON(inputToSerialize),
                        providerExecuted: true,
                        dynamic: markCodeExecutionDynamic && (value.name == "code_execution" || value.name == "bash_code_execution" || value.name == "text_editor_code_execution") ? true : nil,
                        providerMetadata: callerMetadata(value.caller)
                    )
                    content.append(.toolCall(toolCall))
                } else if value.name == "tool_search_tool_regex"
                            || value.name == "tool_search_tool_bm25" {
                    serverToolCalls[value.id] = value.name
                    let toolCall = LanguageModelV4ToolCall(
                        toolCallId: value.id,
                        toolName: toolNameMapping.toCustomToolName(value.name),
                        input: stringifyJSON(value.input),
                        providerExecuted: true,
                        providerMetadata: callerMetadata(value.caller)
                    )
                    content.append(.toolCall(toolCall))
                } else if value.name == "advisor" {
                    let toolCall = LanguageModelV4ToolCall(
                        toolCallId: value.id,
                        toolName: toolNameMapping.toCustomToolName("advisor"),
                        input: stringifyJSON(value.input),
                        providerExecuted: true,
                        providerMetadata: callerMetadata(value.caller)
                    )
                    content.append(.toolCall(toolCall))
                } else {
                    continue
                }

            case .mcpToolUse(let value):
                let providerMetadata: SharedV4ProviderMetadata = [
                    "anthropic": [
                        "type": .string("mcp-tool-use"),
                        "serverName": .string(value.serverName),
                    ]
                ]
                mcpToolCalls[value.id] = (toolName: value.name, providerMetadata: providerMetadata)
                let toolCall = LanguageModelV4ToolCall(
                    toolCallId: value.id,
                    toolName: value.name,
                    input: stringifyJSON(value.input),
                    providerExecuted: true,
                    dynamic: true,
                    providerMetadata: providerMetadata
                )
                content.append(.toolCall(toolCall))

            case .mcpToolResult(let value):
                guard let toolInfo = mcpToolCalls[value.toolUseId] else {
                    continue
                }
                let toolResult = LanguageModelV4ToolResult(
                    toolCallId: value.toolUseId,
                    toolName: toolInfo.toolName,
                    result: value.content,
                    isError: value.isError,
                    dynamic: true,
                    providerMetadata: toolInfo.providerMetadata
                )
                content.append(.toolResult(toolResult))

            case .advisorToolResult(let value):
                let toolName = toolNameMapping.toCustomToolName("advisor")
                if let toolResult = convertAdvisorToolResult(value, toolName: toolName) {
                    content.append(.toolResult(toolResult))
                }

            case .toolSearchToolResult(let value):
                var providerToolName = serverToolCalls[value.toolUseId]
                if providerToolName == nil {
                    let bm25CustomName = toolNameMapping.toCustomToolName("tool_search_tool_bm25")
                    let regexCustomName = toolNameMapping.toCustomToolName("tool_search_tool_regex")

                    if bm25CustomName != "tool_search_tool_bm25" {
                        providerToolName = "tool_search_tool_bm25"
                    } else if regexCustomName != "tool_search_tool_regex" {
                        providerToolName = "tool_search_tool_regex"
                    } else {
                        providerToolName = "tool_search_tool_regex"
                    }
                }
                let customToolName = toolNameMapping.toCustomToolName(providerToolName ?? "tool_search_tool_regex")
                guard case .object(let payload) = value.content,
                      let typeValue = payload["type"],
                      case .string(let type) = typeValue
                else { continue }

                if type == "tool_search_tool_search_result" {
                    guard let referencesValue = payload["tool_references"],
                          case .array(let referencesArray) = referencesValue
                    else { continue }

                    let mapped: [JSONValue] = referencesArray.compactMap { reference in
                        guard case .object(let object) = reference else { return nil }
                        guard let referenceType = object["type"], case .string(let referenceTypeString) = referenceType
                        else { return nil }
                        guard let toolNameValue = object["tool_name"], case .string(let toolName) = toolNameValue
                        else { return nil }
                        return .object([
                            "type": .string(referenceTypeString),
                            "toolName": .string(toolName),
                        ])
                    }

                    let toolResult = LanguageModelV4ToolResult(
                        toolCallId: value.toolUseId,
                        toolName: customToolName,
                        result: .array(mapped)
                    )
                    content.append(.toolResult(toolResult))
                } else if type == "tool_search_tool_result_error" {
                    let errorCode = payload["error_code"] ?? .null
                    let toolResult = LanguageModelV4ToolResult(
                        toolCallId: value.toolUseId,
                        toolName: customToolName,
                        result: .object([
                            "type": .string("tool_search_tool_result_error"),
                            "errorCode": errorCode,
                        ]),
                        isError: true
                    )
                    content.append(.toolResult(toolResult))
                }

            case .webFetchResult(let value):
                let (result, document) = convertWebFetchToolResult(value, toolName: toolNameMapping.toCustomToolName("web_fetch"))
                if let document { citationDocuments.append(document) }
                if let result { content.append(.toolResult(result)) }

            case .webSearchResult(let value):
                let (result, sources) = convertWebSearchToolResult(value, toolName: toolNameMapping.toCustomToolName("web_search"), generateSourceId: generateIdentifier)
                if let result { content.append(.toolResult(result)) }
                content.append(contentsOf: sources.map { .source($0) })

            case .codeExecutionResult(let value):
                let toolName = toolNameMapping.toCustomToolName("code_execution")
                if case .object(let payload) = value.content,
                    let type = payload["type"], case .string(let typeString) = type
                {
                    switch typeString {
                    case "code_execution_result":
                        let stdout = payload["stdout"] ?? .string("")
                        let stderr = payload["stderr"] ?? .string("")
                        let returnCode = payload["return_code"] ?? .number(0)
                        let contentList = payload["content"] ?? .array([])
                        let toolResult = LanguageModelV4ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: toolName,
                            result: .object([
                                "type": .string("code_execution_result"),
                                "stdout": stdout,
                                "stderr": stderr,
                                "return_code": returnCode,
                                "content": contentList,
                            ])
                        )
                        content.append(.toolResult(toolResult))

                    case "encrypted_code_execution_result":
                        let encryptedStdout = payload["encrypted_stdout"] ?? .string("")
                        let stderr = payload["stderr"] ?? .string("")
                        let returnCode = payload["return_code"] ?? .number(0)
                        let contentList = payload["content"] ?? .array([])
                        let toolResult = LanguageModelV4ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: toolName,
                            result: .object([
                                "type": .string("encrypted_code_execution_result"),
                                "encrypted_stdout": encryptedStdout,
                                "stderr": stderr,
                                "return_code": returnCode,
                                "content": contentList,
                            ])
                        )
                        content.append(.toolResult(toolResult))

                    case "code_execution_tool_result_error":
                        let errorCode = payload["error_code"] ?? .null
                        let toolResult = LanguageModelV4ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: toolName,
                            result: .object([
                                "type": .string("code_execution_tool_result_error"),
                                "errorCode": errorCode,
                            ]),
                            isError: true
                        )
                        content.append(.toolResult(toolResult))

                    default:
                        break
                    }
                }

            case .textEditorCodeExecutionResult(let value),
                 .bashCodeExecutionResult(let value):
                let toolResult = LanguageModelV4ToolResult(
                    toolCallId: value.toolUseId,
                    toolName: toolNameMapping.toCustomToolName("code_execution"),
                    result: value.content
                )
                content.append(.toolResult(toolResult))
            }
        }

        return (content, convertAnthropicUsage(response.usage), isJsonResponseFromTool)
    }

    private struct AnthropicUsageState {
        var inputTokens: Int?
        var outputTokens: Int?
        var outputTokensDetails: AnthropicUsage.OutputTokensDetails?
        var cacheCreationInputTokens: Int?
        var cacheReadInputTokens: Int?
        var cacheCreation: AnthropicUsage.CacheCreation?
        var iterations: [AnthropicUsage.Iteration]?

        mutating func merge(_ usage: AnthropicUsage) {
            if let inputTokens = usage.inputTokens {
                self.inputTokens = inputTokens
            }
            if let outputTokens = usage.outputTokens {
                self.outputTokens = outputTokens
            }
            if let details = usage.outputTokensDetails { self.outputTokensDetails = details }
            if let cacheCreationInputTokens = usage.cacheCreationInputTokens {
                self.cacheCreationInputTokens = cacheCreationInputTokens
            }
            if let cacheReadInputTokens = usage.cacheReadInputTokens {
                self.cacheReadInputTokens = cacheReadInputTokens
            }
            if let cacheCreation = usage.cacheCreation {
                self.cacheCreation = cacheCreation
            }
            if let iterations = usage.iterations {
                self.iterations = iterations
            }
        }

        var value: AnthropicUsage {
            AnthropicUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                outputTokensDetails: outputTokensDetails,
                cacheCreationInputTokens: cacheCreationInputTokens,
                cacheReadInputTokens: cacheReadInputTokens,
                cacheCreation: cacheCreation,
                iterations: iterations
            )
        }
    }

    private func convertAnthropicUsage(
        _ usage: AnthropicUsage,
        rawUsage: [String: JSONValue]? = nil
    ) -> LanguageModelV4Usage {
        let cacheCreationTokens = usage.cacheCreationInputTokens ?? 0
        let cacheReadTokens = usage.cacheReadInputTokens ?? 0

        var inputTokens = usage.inputTokens ?? 0
        var outputTokens = usage.outputTokens ?? 0

        let servedByFallback = usage.iterations?.contains {
            $0.type == "fallback_message"
        } == true

        if let iterations = usage.iterations,
           iterations.isEmpty == false,
           servedByFallback == false {
            let executorIterations = iterations.filter {
                $0.type == "compaction" || $0.type == "message"
            }
            if executorIterations.isEmpty == false {
                inputTokens = executorIterations.reduce(0) { $0 + $1.inputTokens }
                outputTokens = executorIterations.reduce(0) { $0 + $1.outputTokens }
            }
        }

        return LanguageModelV4Usage(
            inputTokens: .init(
                total: inputTokens + cacheCreationTokens + cacheReadTokens,
                noCache: inputTokens,
                cacheRead: cacheReadTokens,
                cacheWrite: cacheCreationTokens
            ),
            outputTokens: .init(
                total: outputTokens,
                text: usage.outputTokensDetails?.thinkingTokens.map { outputTokens - $0 },
                reasoning: usage.outputTokensDetails?.thinkingTokens
            ),
            raw: .object(rawUsage ?? anthropicUsageMetadata(usage))
        )
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
        var providerExecuted: Bool?
        var dynamic: Bool?
        var providerMetadata: SharedV4ProviderMetadata?
        var firstDelta: Bool
        var providerToolName: String?
        var providerToolInputType: String?
        var caller: ToolCallerInfo?
        var toolsetName: String? = nil
        var memberName: String? = nil
    }

    private struct ToolCallerInfo {
        var type: String
        var toolId: String?
    }

    private enum ContentBlockState {
        case text(citations: [AnthropicCitation])
        case reasoning
        case toolCall(ToolCallState)
    }

    private func extractCitationDocuments(from prompt: LanguageModelV4Prompt) -> [CitationDocument]
    {
        var documents: [CitationDocument] = []
        for message in prompt {
            guard case let .user(parts, _) = message else { continue }
            for part in parts {
                guard case let .file(filePart) = part else { continue }
                guard filePart.mediaType == "application/pdf" || filePart.mediaType == "text/plain"
                else { continue }
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

    private func createCitationSource(
        from citation: AnthropicCitation, documents: [CitationDocument]
    ) -> LanguageModelV4Source? {
        switch citation {
        case .webSearchResultLocation(let info):
            return .url(id: generateIdentifier(), url: info.url, title: info.title,
                        providerMetadata: ["anthropic": ["citedText": .string(info.citedText), "encryptedIndex": .string(info.encryptedIndex)]])
        case .contentBlockLocation, .searchResultLocation:
            return nil
        case .pageLocation(let info):
            let document = documents[safe: info.documentIndex]
            guard let document else { return nil }
            let metadata: SharedV4ProviderMetadata = [
                "anthropic": [
                    "citedText": .string(info.citedText),
                    "startPageNumber": .number(Double(info.startPageNumber)),
                    "endPageNumber": .number(Double(info.endPageNumber)),
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
            let metadata: SharedV4ProviderMetadata = [
                "anthropic": [
                    "citedText": .string(info.citedText),
                    "startCharIndex": .number(Double(info.startCharIndex)),
                    "endCharIndex": .number(Double(info.endCharIndex)),
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

    private func mapCitation(_ citation: AnthropicCitation, documents: [CitationDocument]) -> LanguageModelV4Citation {
        let raw: [String: JSONValue]
        if case .object(let object) = encodeToJSONValue(citation) { raw = object } else { raw = [:] }
        let metadata: SharedV4ProviderMetadata = ["anthropic": raw]
        let index: Int
        let title: String?
        let fileId: String?
        let citedText: String
        switch citation {
        case .webSearchResultLocation(let info):
            return .init(source: .url(id: info.url, url: info.url, title: info.title, providerMetadata: metadata), citedText: info.citedText)
        case .searchResultLocation(let info):
            return .init(source: .url(id: info.source, url: info.source, title: info.title, providerMetadata: metadata), citedText: info.citedText)
        case .pageLocation(let info):
            (index, title, fileId, citedText) = (info.documentIndex, info.documentTitle, info.fileId, info.citedText)
        case .charLocation(let info):
            (index, title, fileId, citedText) = (info.documentIndex, info.documentTitle, info.fileId, info.citedText)
        case .contentBlockLocation(let info):
            (index, title, fileId, citedText) = (info.documentIndex, info.documentTitle, info.fileId, info.citedText)
        }
        let document = documents[safe: index]
        return .init(source: .document(id: fileId ?? String(index), mediaType: document?.mediaType ?? "text/plain",
                                       title: title ?? document?.title ?? "Document \(index)", filename: document?.filename,
                                       providerMetadata: metadata), citedText: citedText)
    }

    private func contentBlockType(for content: AnthropicMessageContent) -> String {
        switch content {
        case .text: return "text"
        case .thinking: return "thinking"
        case .redactedThinking: return "redacted_thinking"
        case .compaction: return "compaction"
        case .fallback: return "fallback"
        case .containerUpload: return "container_upload"
        case .toolUse: return "tool_use"
        case .serverToolUse: return "server_tool_use"
        case .advisorToolResult: return "advisor_tool_result"
        case .mcpToolUse: return "mcp_tool_use"
        case .mcpToolResult: return "mcp_tool_result"
        case .toolSearchToolResult: return "tool_search_tool_result"
        case .webFetchResult: return "web_fetch_tool_result"
        case .webSearchResult: return "web_search_tool_result"
        case .codeExecutionResult: return "code_execution_tool_result"
        case .textEditorCodeExecutionResult: return "text_editor_code_execution_tool_result"
        case .bashCodeExecutionResult: return "bash_code_execution_tool_result"
        }
    }

    private func handleContentBlockStart(
        _ value: ContentBlockStart,
        usesJsonResponseTool: Bool,
        toolNameMapping: AnthropicToolNameMapping,
        markCodeExecutionDynamic: Bool,
        citationDocuments: inout [CitationDocument],
        contentBlocks: inout [Int: ContentBlockState],
        serverToolCalls: inout [String: String],
        mcpToolCalls: inout [String: (toolName: String, providerMetadata: SharedV4ProviderMetadata)],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        switch value.contentBlock {
        case .text:
            // When a json response tool is used, the tool call is returned as text,
            // so we ignore the text content.
            if usesJsonResponseTool {
                return
            }
            contentBlocks[value.index] = .text(citations: [])
            continuation.yield(.textStart(id: String(value.index), providerMetadata: nil))

        case .thinking:
            contentBlocks[value.index] = .reasoning
            continuation.yield(.reasoningStart(id: String(value.index), providerMetadata: nil))

        case .redactedThinking(let redacted):
            contentBlocks[value.index] = .reasoning
            let metadata: SharedV4ProviderMetadata = [
                "anthropic": ["redactedData": .string(redacted.data)]
            ]
            continuation.yield(.reasoningStart(id: String(value.index), providerMetadata: metadata))

        case .compaction(let compaction):
            contentBlocks[value.index] = .text(citations: [])
            var metadata: [String: JSONValue] = ["type": .string("compaction")]
            if let signature = compaction.signature { metadata["signature"] = .string(signature) }
            continuation.yield(.textStart(id: String(value.index), providerMetadata: ["anthropic": metadata]))
            if compaction.signature != nil, let content = compaction.content, !content.isEmpty {
                continuation.yield(.textDelta(id: String(value.index), delta: content, providerMetadata: nil))
            }

        case .fallback(let value):
            if case .object(let metadata) = encodeToJSONValue(value) {
                continuation.yield(.custom(.init(kind: "anthropic.fallback", providerMetadata: ["anthropic": metadata])))
            }
            return
        case .containerUpload(let value):
            continuation.yield(.custom(.init(kind: "anthropic.container_upload", providerMetadata: ["anthropic": ["fileId": .string(value.fileId)]])))
            return

        case .toolUse(let tool):
            let isJsonResponseTool = usesJsonResponseTool && tool.name == "json"
            if isJsonResponseTool {
                contentBlocks[value.index] = .text(citations: [])
                continuation.yield(.textStart(id: String(value.index), providerMetadata: nil))
            } else {
                let hasNonEmptyInput: Bool
                if let input = tool.input, case .object(let object) = input {
                    hasNonEmptyInput = object.isEmpty == false
                } else {
                    hasNonEmptyInput = false
                }
                let initialInput = hasNonEmptyInput ? stringifyJSON(tool.input) : ""
                let callerInfo: ToolCallerInfo? = tool.caller.map {
                    ToolCallerInfo(type: $0.type, toolId: $0.toolId)
                }

                let state = ToolCallState(
                    toolCallId: tool.id,
                    toolName: tool.toolsetName.map(toolNameMapping.toCustomToolName) ?? tool.name,
                    input: initialInput,
                    providerExecuted: nil,
                    dynamic: nil,
                    providerMetadata: nil,
                    firstDelta: initialInput.isEmpty,
                    providerToolName: nil,
                    providerToolInputType: nil,
                    caller: callerInfo,
                    toolsetName: tool.toolsetName,
                    memberName: tool.toolsetName == nil ? nil : tool.name
                )
                contentBlocks[value.index] = .toolCall(state)
                continuation.yield(
                    .toolInputStart(
                        id: tool.id,
                        toolName: tool.toolsetName.map(toolNameMapping.toCustomToolName) ?? tool.name,
                        providerMetadata: nil,
                        providerExecuted: nil,
                        dynamic: nil,
                        title: nil
                    )
                )
            }

        case .serverToolUse(let tool):
            if tool.name == "web_fetch" || tool.name == "web_search"
                || tool.name == "code_execution"
                || tool.name == "text_editor_code_execution"
                || tool.name == "bash_code_execution" {
                let hasNonEmptyInput: Bool
                if case .object(let object) = tool.input {
                    hasNonEmptyInput = object.isEmpty == false
                } else {
                    hasNonEmptyInput = false
                }
                let initialInput = hasNonEmptyInput ? stringifyJSON(tool.input) : ""
                let providerToolName =
                    (tool.name == "text_editor_code_execution" || tool.name == "bash_code_execution")
                    ? "code_execution"
                    : tool.name
                let providerToolInputType: String? =
                    (tool.name == "text_editor_code_execution" || tool.name == "bash_code_execution")
                    ? tool.name
                    : tool.name == "code_execution" ? "programmatic-tool-call" : nil
                let customToolName = toolNameMapping.toCustomToolName(providerToolName)

                let state = ToolCallState(
                    toolCallId: tool.id,
                    toolName: customToolName,
                    input: initialInput,
                    providerExecuted: true,
                    dynamic: markCodeExecutionDynamic && providerToolName == "code_execution" ? true : nil,
                    providerMetadata: callerMetadata(tool.caller),
                    firstDelta: initialInput.isEmpty,
                    providerToolName: providerToolName,
                    providerToolInputType: providerToolInputType,
                    caller: nil
                )
                contentBlocks[value.index] = .toolCall(state)
                continuation.yield(
                    .toolInputStart(
                        id: tool.id,
                        toolName: customToolName,
                        providerMetadata: nil,
                        providerExecuted: true,
                        dynamic: markCodeExecutionDynamic && providerToolName == "code_execution" ? true : nil,
                        title: nil
                    )
                )
            } else if tool.name == "tool_search_tool_regex" || tool.name == "tool_search_tool_bm25" {
                serverToolCalls[tool.id] = tool.name
                let customToolName = toolNameMapping.toCustomToolName(tool.name)
                let initialInput = ""

                let state = ToolCallState(
                    toolCallId: tool.id,
                    toolName: customToolName,
                    input: initialInput,
                    providerExecuted: true,
                    dynamic: nil,
                    providerMetadata: callerMetadata(tool.caller),
                    firstDelta: initialInput.isEmpty,
                    providerToolName: tool.name,
                    providerToolInputType: nil,
                    caller: nil
                )
                contentBlocks[value.index] = .toolCall(state)
                continuation.yield(
                    .toolInputStart(
                        id: tool.id,
                        toolName: customToolName,
                        providerMetadata: nil,
                        providerExecuted: true,
                        dynamic: nil,
                        title: nil
                    )
                )
            } else if tool.name == "advisor" {
                let customToolName = toolNameMapping.toCustomToolName("advisor")
                let state = ToolCallState(
                    toolCallId: tool.id,
                    toolName: customToolName,
                    input: "{}",
                    providerExecuted: true,
                    dynamic: nil,
                    providerMetadata: callerMetadata(tool.caller),
                    firstDelta: true,
                    providerToolName: tool.name,
                    providerToolInputType: nil,
                    caller: nil
                )
                contentBlocks[value.index] = .toolCall(state)
                continuation.yield(
                    .toolInputStart(
                        id: tool.id,
                        toolName: customToolName,
                        providerMetadata: nil,
                        providerExecuted: true,
                        dynamic: nil,
                        title: nil
                    )
                )
            }

        case .mcpToolUse(let tool):
            let providerMetadata: SharedV4ProviderMetadata = [
                "anthropic": [
                    "type": .string("mcp-tool-use"),
                    "serverName": .string(tool.serverName),
                ]
            ]
            mcpToolCalls[tool.id] = (toolName: tool.name, providerMetadata: providerMetadata)
            continuation.yield(.toolCall(.init(toolCallId: tool.id, toolName: tool.name,
                                              input: stringifyJSON(tool.input), providerExecuted: true,
                                              dynamic: true, providerMetadata: providerMetadata)))

        case .mcpToolResult(let result):
            guard let toolInfo = mcpToolCalls[result.toolUseId] else { return }
            let toolResult = LanguageModelV4ToolResult(
                toolCallId: result.toolUseId,
                toolName: toolInfo.toolName,
                result: result.content,
                isError: result.isError,
                dynamic: true,
                providerMetadata: toolInfo.providerMetadata
            )
            continuation.yield(.toolResult(toolResult))

        case .advisorToolResult(let result):
            let toolName = toolNameMapping.toCustomToolName("advisor")
            if let toolResult = convertAdvisorToolResult(result, toolName: toolName) {
                continuation.yield(.toolResult(toolResult))
            }

        case .toolSearchToolResult(let result):
            var providerToolName = serverToolCalls[result.toolUseId]
            if providerToolName == nil {
                let bm25CustomName = toolNameMapping.toCustomToolName("tool_search_tool_bm25")
                let regexCustomName = toolNameMapping.toCustomToolName("tool_search_tool_regex")

                if bm25CustomName != "tool_search_tool_bm25" {
                    providerToolName = "tool_search_tool_bm25"
                } else if regexCustomName != "tool_search_tool_regex" {
                    providerToolName = "tool_search_tool_regex"
                } else {
                    providerToolName = "tool_search_tool_regex"
                }
            }
            let customToolName = toolNameMapping.toCustomToolName(providerToolName ?? "tool_search_tool_regex")
            if let toolResult = convertToolSearchToolResult(result, toolName: customToolName) {
                continuation.yield(.toolResult(toolResult))
            }

        case .webFetchResult(let result):
            let toolName = toolNameMapping.toCustomToolName("web_fetch")
            let (toolResult, document) = convertWebFetchToolResult(result, toolName: toolName)
            if let document {
                citationDocuments.append(document)
            }
            if let toolResult {
                continuation.yield(.toolResult(toolResult))
            }

        case .webSearchResult(let result):
            let toolName = toolNameMapping.toCustomToolName("web_search")
            let (toolResult, sources) = convertWebSearchToolResult(
                result, toolName: toolName, generateSourceId: generateIdentifier)
            if let toolResult {
                continuation.yield(.toolResult(toolResult))
            }
            for source in sources {
                continuation.yield(.source(source))
            }

        case .codeExecutionResult(let result):
            let toolName = toolNameMapping.toCustomToolName("code_execution")
            if let toolResult = convertCodeExecutionToolResult(result, toolName: toolName) {
                continuation.yield(.toolResult(toolResult))
            }

        case .textEditorCodeExecutionResult(let result),
             .bashCodeExecutionResult(let result):
            let toolResult = LanguageModelV4ToolResult(
                toolCallId: result.toolUseId,
                toolName: toolNameMapping.toCustomToolName("code_execution"),
                result: result.content
            )
            continuation.yield(.toolResult(toolResult))
        }
    }

    private func handleContentBlockDelta(
        _ value: ContentBlockDelta,
        blockType: String?,
        usesJsonResponseTool: Bool,
        citationDocuments: [CitationDocument],
        fallbackWebCitations: inout [AnthropicCitation],
        contentBlocks: inout [Int: ContentBlockState],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        switch value.delta {
        case .textDelta(let text):
            guard usesJsonResponseTool == false else { return }
            continuation.yield(
                .textDelta(id: String(value.index), delta: text, providerMetadata: nil))

        case .thinkingDelta(let thinking):
            continuation.yield(
                .reasoningDelta(id: String(value.index), delta: thinking, providerMetadata: nil))

        case .signatureDelta(let signature):
            guard blockType == "thinking" else { return }
            let metadata: SharedV4ProviderMetadata = [
                "anthropic": ["signature": .string(signature)]
            ]
            continuation.yield(
                .reasoningDelta(id: String(value.index), delta: "", providerMetadata: metadata))

        case .compactionDelta(let content):
            guard let content else { return }
            continuation.yield(
                .textDelta(id: String(value.index), delta: content, providerMetadata: nil)
            )

        case .inputJSONDelta(let partialJSON):
            // Skip empty deltas to enable replacing the first character
            // in the code execution 20250825 tool.
            if partialJSON.isEmpty {
                return
            }

            if usesJsonResponseTool, case .text = contentBlocks[value.index] {
                continuation.yield(
                    .textDelta(id: String(value.index), delta: partialJSON, providerMetadata: nil))
            } else if case .toolCall(var toolState) = contentBlocks[value.index] {
                if toolState.toolsetName != nil {
                    toolState.input += partialJSON
                    contentBlocks[value.index] = .toolCall(toolState)
                    return
                }
                var delta = partialJSON
                // For the code execution 20250825, we need to add the type to the delta
                // and change the tool name.
                if toolState.firstDelta,
                   let providerToolInputType = toolState.providerToolInputType,
                   delta.first == "{" {
                    delta = "{\"type\": \"\(providerToolInputType)\"," + String(delta.dropFirst())
                }

                continuation.yield(
                    .toolInputDelta(
                        id: toolState.toolCallId,
                        delta: delta,
                        providerMetadata: nil
                    ))
                toolState.input += delta
                toolState.firstDelta = false
                contentBlocks[value.index] = .toolCall(toolState)
            }

        case .citationsDelta(let citation):
            if case .text(var citations) = contentBlocks[value.index] {
                citations.append(citation)
                contentBlocks[value.index] = .text(citations: citations)
            }
            if case .webSearchResultLocation = citation {
                fallbackWebCitations.append(citation)
            } else if let source = createCitationSource(from: citation, documents: citationDocuments) {
                continuation.yield(.source(source))
            }
        }
    }

    private func handleContentBlockStop(
        index: Int,
        usesJsonResponseTool: Bool,
        citationDocuments: [CitationDocument],
        contentBlocks: inout [Int: ContentBlockState],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let state = contentBlocks.removeValue(forKey: index) else { return }

        switch state {
        case .text(let citations):
            continuation.yield(.textEnd(
                id: String(index),
                providerMetadata: citations.isEmpty ? nil : ["anthropic": ["citations": encodeToJSONValue(citations) ?? .array([])]],
                citations: citations.isEmpty ? nil : citations.map { mapCitation($0, documents: citationDocuments) }
            ))

        case .reasoning:
            continuation.yield(.reasoningEnd(id: String(index), providerMetadata: nil))

        case .toolCall(var toolState):
            if let member = toolState.memberName {
                if let data = (toolState.input.isEmpty ? "{}" : toolState.input).data(using: .utf8),
                   let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    toolState.input = stringifyJSON(toolsetInput(member: member, input: parsed))
                }
                continuation.yield(.toolInputDelta(id: toolState.toolCallId, delta: toolState.input, providerMetadata: nil))
            }
            if usesJsonResponseTool && toolState.toolName == "json" {
                continuation.yield(.textEnd(id: String(index), providerMetadata: nil))
            } else {
                continuation.yield(
                    .toolInputEnd(id: toolState.toolCallId, providerMetadata: nil))

                var finalInput = toolState.input.isEmpty ? "{}" : toolState.input
                if toolState.providerToolName == "code_execution" {
                    if let data = finalInput.data(using: .utf8),
                       let json = try? JSONDecoder().decode(JSONValue.self, from: data),
                       case .object(let object) = json,
                       object["code"] != nil,
                       object["type"] == nil {
                        var injected = object
                        injected["type"] = .string("programmatic-tool-call")
                        finalInput = stringifyJSON(.object(injected))
                    }
                }

                var providerMetadata = toolState.providerMetadata
                if providerMetadata == nil, let caller = toolState.caller {
                    var callerObject: [String: JSONValue] = [
                        "type": .string(caller.type)
                    ]
                    if let toolId = caller.toolId {
                        callerObject["toolId"] = .string(toolId)
                    }
                    providerMetadata = [
                        "anthropic": [
                            "caller": .object(callerObject)
                        ]
                    ]
                }

                if let toolset = toolState.toolsetName {
                    var metadata = providerMetadata ?? [:]
                    var anthropic = metadata["anthropic"] ?? [:]
                    anthropic["toolsetName"] = .string(toolset)
                    metadata["anthropic"] = anthropic
                    providerMetadata = metadata
                }
                let toolCall = LanguageModelV4ToolCall(
                    toolCallId: toolState.toolCallId,
                    toolName: toolState.toolName,
                    input: finalInput,
                    providerExecuted: toolState.providerExecuted,
                    dynamic: toolState.dynamic,
                    providerMetadata: providerMetadata
                )
                continuation.yield(.toolCall(toolCall))
            }
        }
    }

    private func anthropicUsageMetadata(_ usage: AnthropicUsage) -> [String: JSONValue] {
        if let raw = usage.raw { return raw }
        var metadata: [String: JSONValue] = [:]
        if let inputTokens = usage.inputTokens {
            metadata["input_tokens"] = .number(Double(inputTokens))
        }
        if let outputTokens = usage.outputTokens {
            metadata["output_tokens"] = .number(Double(outputTokens))
        }
        if let details = usage.outputTokensDetails { metadata["output_tokens_details"] = encodeToJSONValue(details) }
        if let cacheCreation = usage.cacheCreationInputTokens {
            metadata["cache_creation_input_tokens"] = .number(Double(cacheCreation))
        }
        if let cacheRead = usage.cacheReadInputTokens {
            metadata["cache_read_input_tokens"] = .number(Double(cacheRead))
        }
        if let cacheCreation = usage.cacheCreation {
            metadata["cache_creation"] = .object([
                "ephemeral_5m_input_tokens": cacheCreation.ephemeral5mInputTokens.map {
                    .number(Double($0))
                } ?? .null,
                "ephemeral_1h_input_tokens": cacheCreation.ephemeral1hInputTokens.map {
                    .number(Double($0))
                } ?? .null,
            ])
        }
        if let iterations = usage.iterations,
           let encodedIterations = encodeToJSONValue(iterations) {
            metadata["iterations"] = encodedIterations
        }
        return metadata
    }

    private func anthropicIterationsMetadata(
        _ iterations: [AnthropicUsage.Iteration]?
    ) -> JSONValue {
        guard let iterations else { return .null }

        return .array(iterations.map { iteration in
            var metadata: [String: JSONValue] = [
                "type": .string(iteration.type),
                "inputTokens": .number(Double(iteration.inputTokens)),
                "outputTokens": .number(Double(iteration.outputTokens)),
            ]
            if let model = iteration.model {
                metadata["model"] = .string(model)
            }
            if let cacheCreation = iteration.cacheCreationInputTokens,
               cacheCreation != 0 {
                metadata["cacheCreationInputTokens"] = .number(Double(cacheCreation))
            }
            if let cacheRead = iteration.cacheReadInputTokens,
               cacheRead != 0 {
                metadata["cacheReadInputTokens"] = .number(Double(cacheRead))
            }
            return .object(metadata)
        })
    }

    private func anthropicStopDetailsMetadata(
        _ stopDetails: AnthropicStopDetails?
    ) -> JSONValue? {
        guard let stopDetails else { return nil }

        var metadata: [String: JSONValue] = [
            "type": .string(stopDetails.type)
        ]
        if let category = stopDetails.category {
            metadata["category"] = .string(category)
        }
        if let explanation = stopDetails.explanation {
            metadata["explanation"] = .string(explanation)
        }
        if let recommendedModel = stopDetails.recommendedModel {
            metadata["recommendedModel"] = .string(recommendedModel)
        }
        return .object(metadata)
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func convertWebFetchToolResult(
        _ content: WebFetchToolResultContent,
        toolName: String
    ) -> (LanguageModelV4ToolResult?, CitationDocument?) {
        guard case .object(let payload) = content.content else { return (nil, nil) }
        guard let typeValue = payload["type"], case .string(let type) = typeValue else {
            return (nil, nil)
        }

        if type == "web_fetch_result" {
            let url = payload["url"] ?? .string("")
            let retrievedAt = payload["retrieved_at"] ?? .null
            var resultObject: [String: JSONValue] = [
                "type": .string("web_fetch_result"),
                "url": url,
                "retrievedAt": retrievedAt,
            ]
            var document: CitationDocument? = nil

            if let contentValue = payload["content"], case .object(let inner) = contentValue,
                let sourceValue = inner["source"], case .object(let sourceObject) = sourceValue
            {
                var mappedContent: [String: JSONValue] = [
                    "type": inner["type"] ?? .string("document"),
                    "title": inner["title"] ?? .null,
                ]
                mappedContent["source"] = .object([
                    "type": sourceObject["type"] ?? .string("base64"),
                    "mediaType": sourceObject["media_type"] ?? .string(""),
                    "data": sourceObject["data"] ?? .string(""),
                ])
                if let citations = inner["citations"] {
                    mappedContent["citations"] = citations
                }
                resultObject["content"] = .object(mappedContent)

                let documentTitle: String
                if let titleValue = inner["title"],
                   case .string(let titleString) = titleValue {
                    documentTitle = titleString
                } else if case .string(let urlString) = url {
                    documentTitle = urlString
                } else {
                    documentTitle = ""
                }

                if let mediaTypeValue = sourceObject["media_type"],
                   case .string(let mediaType) = mediaTypeValue {
                    document = CitationDocument(title: documentTitle, filename: nil, mediaType: mediaType)
                }
            }

            return (LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object(resultObject), providerMetadata: callerMetadata(content.caller)
            ), document)
        }

        if type == "web_fetch_tool_result_error" {
            return (LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string("web_fetch_tool_result_error"),
                    "errorCode": payload["error_code"] ?? .null,
                ]),
                isError: true, providerMetadata: callerMetadata(content.caller)
            ), nil)
        }

        return (nil, nil)
    }

    private func convertWebSearchToolResult(
        _ content: WebSearchToolResultContent,
        toolName: String,
        generateSourceId: @Sendable () -> String
    ) -> (LanguageModelV4ToolResult?, [LanguageModelV4Source]) {
        switch content.content {
        case .array(let items):
            var resultsJSON: [JSONValue] = []
            var sources: [LanguageModelV4Source] = []

            for item in items {
                guard case .object(let object) = item else { continue }
                let urlValue = object["url"] ?? .string("")
                let title: String?
                if case .string(let value) = object["title"] { title = value } else { title = nil }
                let pageAge = object["page_age"] ?? .null
                var result: [String: JSONValue] = [
                    "url": urlValue, "pageAge": pageAge,
                    "encryptedContent": object["encrypted_content"] ?? .string(""),
                    "type": object["type"] ?? .string("web_search_result"),
                ]
                if let title { result["title"] = .string(title) }
                resultsJSON.append(.object(result))
                if case .string(let url) = urlValue {
                    sources.append(.url(id: generateSourceId(), url: url, title: title,
                                        providerMetadata: ["anthropic": ["pageAge": pageAge]]))
                }
            }

            let toolResult = LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .array(resultsJSON), providerMetadata: callerMetadata(content.caller)
            )
            return (toolResult, sources)

        case .object(let object):
            let toolResult = LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string("web_search_tool_result_error"),
                    "errorCode": object["error_code"] ?? .null,
                ]),
                isError: true, providerMetadata: callerMetadata(content.caller)
            )
            return (toolResult, [])

        default:
            return (nil, [])
        }
    }

    private func convertCodeExecutionToolResult(
        _ content: CodeExecutionToolResultContent,
        toolName: String
    )
        -> LanguageModelV4ToolResult?
    {
        guard case .object(let payload) = content.content else { return nil }
        guard let typeValue = payload["type"], case .string(let type) = typeValue else {
            return nil
        }

        if type == "code_execution_result" {
            return LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string("code_execution_result"),
                    "stdout": payload["stdout"] ?? .string(""),
                    "stderr": payload["stderr"] ?? .string(""),
                    "return_code": payload["return_code"] ?? .number(0),
                    "content": payload["content"] ?? .array([]),
                ])
            )
        }

        if type == "encrypted_code_execution_result" {
            return LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string("encrypted_code_execution_result"),
                    "encrypted_stdout": payload["encrypted_stdout"] ?? .string(""),
                    "stderr": payload["stderr"] ?? .string(""),
                    "return_code": payload["return_code"] ?? .number(0),
                    "content": payload["content"] ?? .array([]),
                ])
            )
        }

        if type == "code_execution_tool_result_error" {
            return LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string("code_execution_tool_result_error"),
                    "errorCode": payload["error_code"] ?? .null,
                ]),
                isError: true
            )
        }

        return nil
    }

    private func convertAdvisorToolResult(
        _ content: AdvisorToolResultContent,
        toolName: String
    ) -> LanguageModelV4ToolResult? {
        guard case .object(let payload) = content.content,
              let typeValue = payload["type"],
              case .string(let type) = typeValue
        else { return nil }

        switch type {
        case "advisor_result":
            guard let text = payload["text"] else { return nil }
            var result: [String: JSONValue] = ["type": .string(type), "text": text]
            if let stopReason = payload["stop_reason"], stopReason != .null { result["stopReason"] = stopReason }
            return .init(toolCallId: content.toolUseId, toolName: toolName, result: .object(result))

        case "advisor_redacted_result":
            guard let encryptedContent = payload["encrypted_content"] else { return nil }
            var result: [String: JSONValue] = ["type": .string(type), "encryptedContent": encryptedContent]
            if let stopReason = payload["stop_reason"], stopReason != .null { result["stopReason"] = stopReason }
            return .init(toolCallId: content.toolUseId, toolName: toolName, result: .object(result))

        case "advisor_tool_result_error":
            guard let errorCode = payload["error_code"] else { return nil }
            return LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string(type),
                    "errorCode": errorCode,
                ]),
                isError: true
            )

        default:
            return nil
        }
    }

    private func convertToolSearchToolResult(
        _ content: ToolSearchToolResultContent,
        toolName: String
    ) -> LanguageModelV4ToolResult? {
        guard case .object(let payload) = content.content,
              let typeValue = payload["type"],
              case .string(let type) = typeValue
        else { return nil }

        if type == "tool_search_tool_search_result" {
            guard let referencesValue = payload["tool_references"],
                  case .array(let referencesArray) = referencesValue
            else { return nil }

            let mapped: [JSONValue] = referencesArray.compactMap { reference in
                guard case .object(let object) = reference else { return nil }
                guard let referenceType = object["type"], case .string(let referenceTypeString) = referenceType
                else { return nil }
                guard let toolNameValue = object["tool_name"],
                      case .string(let referencedToolName) = toolNameValue
                else { return nil }
                return .object([
                    "type": .string(referenceTypeString),
                    "toolName": .string(referencedToolName),
                ])
            }

            return LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .array(mapped)
            )
        }

        if type == "tool_search_tool_result_error" {
            return LanguageModelV4ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string("tool_search_tool_result_error"),
                    "errorCode": payload["error_code"] ?? .null,
                ]),
                isError: true
            )
        }

        return nil
    }

    private func hasDynamicFilteringWebToolWithoutCodeExecution(_ body: [String: JSONValue]) -> Bool {
        guard case .array(let tools) = body["tools"] else { return false }
        var hasWebTool = false
        for tool in tools {
            guard case .object(let tool) = tool, case .string(let type) = tool["type"] else { continue }
            if ["code_execution_20250522", "code_execution_20250825", "code_execution_20260120"].contains(type) { return false }
            if ["web_fetch_20260209", "web_fetch_20260318", "web_search_20260209", "web_search_20260318"].contains(type) { hasWebTool = true }
        }
        return hasWebTool
    }

    private func toolsetInput(member: String, input: JSONValue) -> JSONValue {
        var object: [String: JSONValue] = ["action": .string(member)]
        if case .object(let input) = input { object.merge(input, uniquingKeysWith: { _, value in value }) }
        return .object(object)
    }

    private func callerMetadata(_ caller: ToolUseContent.Caller?) -> SharedV4ProviderMetadata? {
        guard let caller else { return nil }
        var object: [String: JSONValue] = ["type": .string(caller.type)]
        if let id = caller.toolId { object["toolId"] = .string(id) }
        return ["anthropic": ["caller": .object(object)]]
    }

    private func stringifyJSON(_ value: JSONValue?) -> String {
        guard let value else { return "null" }
        if let data = try? JSONEncoder().encode(value),
            let string = String(data: data, encoding: .utf8)
        {
            return string
        }
        return "null"
    }

    private func anthropicContainerMetadata(_ container: AnthropicContainer?) -> JSONValue {
        guard let container else { return .null }

        var payload: [String: JSONValue] = [
            "expiresAt": .string(container.expiresAt),
            "id": .string(container.id),
        ]

        if let skills = container.skills {
            payload["skills"] = .array(
                skills.map { skill in
                    .object([
                        "type": .string(skill.type),
                        "skillId": .string(skill.skillId),
                        "version": .string(skill.version),
                    ])
                }
            )
        } else {
            payload["skills"] = .null
        }

        return .object(payload)
    }

    private func anthropicContextManagementMetadata(
        _ contextManagement: AnthropicResponseContextManagement?
    ) -> JSONValue {
        guard let contextManagement else { return .null }

        let appliedEdits: [JSONValue] = contextManagement.appliedEdits.compactMap { edit in
            switch edit {
            case .clearToolUses20250919(let value):
                return .object([
                    "type": .string(value.type),
                    "clearedToolUses": .number(Double(value.clearedToolUses)),
                    "clearedInputTokens": .number(Double(value.clearedInputTokens)),
                ])
            case .clearThinking20251015(let value):
                return .object([
                    "type": .string(value.type),
                    "clearedThinkingTurns": .number(Double(value.clearedThinkingTurns)),
                    "clearedInputTokens": .number(Double(value.clearedInputTokens)),
                ])
            case .compact20260112(let value):
                return .object([
                    "type": .string(value.type),
                ])
            }
        }

        return .object(["appliedEdits": .array(appliedEdits)])
    }

    private func mergeProviderMetadata(
        _ anthropicMetadata: [String: JSONValue],
        providerOptionsName: String,
        usedCustomProviderKey: Bool
    ) -> SharedV4ProviderMetadata {
        var providerMetadata: SharedV4ProviderMetadata = [
            "anthropic": anthropicMetadata
        ]

        if usedCustomProviderKey, providerOptionsName != "anthropic" {
            providerMetadata[providerOptionsName] = anthropicMetadata
        }

        return providerMetadata
    }

    private func makeProviderMetadata(
        response: AnthropicMessagesResponse,
        providerOptionsName: String,
        usedCustomProviderKey: Bool
    ) -> SharedV4ProviderMetadata? {
        guard let usageJSON = encodeToJSONValue(response.usage) else {
            return nil
        }

        var anthropicMetadata: [String: JSONValue] = [
            "usage": usageJSON,
            "stopSequence": response.stopSequence.map(JSONValue.string) ?? .null,
            "iterations": anthropicIterationsMetadata(response.usage.iterations),
            "container": anthropicContainerMetadata(response.container),
            "contextManagement": anthropicContextManagementMetadata(response.contextManagement),
        ]
        if let transformations = response.inputTransformations { anthropicMetadata["inputTransformations"] = encodeToJSONValue(transformations) }
        if let results = response.safeguardResults { anthropicMetadata["safeguardResults"] = encodeToJSONValue(results) }
        if let stopDetails = anthropicStopDetailsMetadata(response.stopDetails) {
            anthropicMetadata["stopDetails"] = stopDetails
        }

        return mergeProviderMetadata(
            anthropicMetadata,
            providerOptionsName: providerOptionsName,
            usedCustomProviderKey: usedCustomProviderKey
        )
    }
}

private final class AnthropicStreamReader: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.AsyncIterator
    private var prefix: [LanguageModelV4StreamPart] = []

    init(_ stream: AsyncThrowingStream<LanguageModelV4StreamPart, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func prepend(_ parts: [LanguageModelV4StreamPart]) { prefix = parts }

    func next() async throws -> LanguageModelV4StreamPart? {
        if !prefix.isEmpty { return prefix.removeFirst() }
        return try await iterator.next()
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
