import AISDKProvider
import AISDKProviderUtils
import Foundation

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
    public let supportsNativeStructuredOutput: Bool?

    public init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction? = nil,
        supportedUrls: @escaping @Sendable () -> [String: [NSRegularExpression]] = { [:] },
        generateId: @escaping @Sendable () -> String = defaultAnthropicId,
        requestTransform: RequestTransform = .init(),
        supportsNativeStructuredOutput: Bool? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.supportedUrls = supportedUrls
        self.generateId = generateId
        self.requestTransform = requestTransform
        self.supportsNativeStructuredOutput = supportsNativeStructuredOutput
    }
}

private struct AnthropicRequestArguments {
    let body: [String: JSONValue]
    let warnings: [SharedV3Warning]
    let betas: Set<String>
    let usesJsonResponseTool: Bool
    let toolNameMapping: AnthropicToolNameMapping
    let toolStreaming: Bool
    let providerOptionsName: String
    let usedCustomProviderKey: Bool
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

    public func doGenerate(options: LanguageModelV3CallOptions) async throws
        -> LanguageModelV3GenerateResult
    {
        let prepared = try await prepareRequest(options: options)
        let requestURL = buildRequestURL(isStreaming: false)
        let headers = getHeaders(betas: prepared.betas, additional: options.headers)

        let body = config.requestTransform.transformBody?(prepared.body) ?? prepared.body

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
            prompt: options.prompt,
            usesJsonResponseTool: prepared.usesJsonResponseTool,
            toolNameMapping: prepared.toolNameMapping
        )

        let providerMetadata = makeProviderMetadata(
            response: response.value,
            providerOptionsName: prepared.providerOptionsName,
            usedCustomProviderKey: prepared.usedCustomProviderKey
        )

        return LanguageModelV3GenerateResult(
            content: usageAndContent.content,
            finishReason: LanguageModelV3FinishReason(
                unified: mapAnthropicStopReason(
                    finishReason: response.value.stopReason,
                    isJsonResponseFromTool: prepared.usesJsonResponseTool
                ),
                raw: response.value.stopReason
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

    public func doStream(options: LanguageModelV3CallOptions) async throws
        -> LanguageModelV3StreamResult
    {
        let prepared = try await prepareRequest(options: options)

        var betas = prepared.betas
        if prepared.toolStreaming {
            betas.insert("fine-grained-tool-streaming-2025-05-14")
        }

        var requestBody = prepared.body
        requestBody["stream"] = .bool(true)
        let transformedBody = config.requestTransform.transformBody?(requestBody) ?? requestBody

        let response = try await postJsonToAPI(
            url: buildRequestURL(isStreaming: true),
            headers: getHeaders(betas: betas, additional: options.headers),
            body: JSONValue.object(transformedBody),
            failedResponseHandler: anthropicFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(
                chunkSchema: anthropicMessagesChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let initialCitationDocuments = extractCitationDocuments(from: options.prompt)

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var citationDocuments = initialCitationDocuments
                var contentBlocks: [Int: ContentBlockState] = [:]
                var blockType: String?
                var serverToolCalls: [String: String] = [:]
                var mcpToolCalls: [String: (toolName: String, providerMetadata: SharedV3ProviderMetadata)] = [:]
                var finishReason: LanguageModelV3FinishReason = .init(unified: .other, raw: nil)
                var usage = LanguageModelV3Usage()
                var rawUsage: [String: JSONValue]? = nil
                var cacheCreationInputTokens: Int? = nil
                var stopSequence: String? = nil
                var container: JSONValue = .null
                var contextManagement: JSONValue = .null

                do {
                    for try await chunk in response.value {
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
                                blockType = contentBlockType(for: value.contentBlock)
                                handleContentBlockStart(
                                    value,
                                    usesJsonResponseTool: prepared.usesJsonResponseTool,
                                    toolNameMapping: prepared.toolNameMapping,
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
                                    let usageMetadata = anthropicUsageMetadata(usageInfo)

                                    let inputTokens = usageInfo.inputTokens ?? usage.inputTokens.noCache ?? 0
                                    let cacheCreationTokens = usageInfo.cacheCreationInputTokens ?? usage.inputTokens.cacheWrite ?? 0
                                    let cacheReadTokens = usageInfo.cacheReadInputTokens ?? usage.inputTokens.cacheRead ?? 0
                                    let outputTokensTotal: Int? = {
                                        if let output = usageInfo.outputTokens {
                                            return output
                                        }
                                        return usage.outputTokens.total
                                    }()

                                    usage = LanguageModelV3Usage(
                                        inputTokens: .init(
                                            total: inputTokens + cacheCreationTokens + cacheReadTokens,
                                            noCache: inputTokens,
                                            cacheRead: cacheReadTokens,
                                            cacheWrite: cacheCreationTokens
                                        ),
                                        outputTokens: .init(
                                            total: outputTokensTotal,
                                            text: nil,
                                            reasoning: nil
                                        ),
                                        raw: .object(usageMetadata)
                                    )

                                    cacheCreationInputTokens = usageInfo.cacheCreationInputTokens
                                    rawUsage = usageMetadata
                                }

                                container = anthropicContainerMetadata(value.message.container)

                                if let stopReason = value.message.stopReason {
                                    finishReason = LanguageModelV3FinishReason(
                                        unified: mapAnthropicStopReason(
                                            finishReason: stopReason,
                                            isJsonResponseFromTool: prepared.usesJsonResponseTool
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

                                // Programmatic tool calling: process pre-populated content blocks
                                // (for deferred tool calls, content may be in message_start)
                                if let content = value.message.content {
                                    for part in content {
                                        guard case .toolUse(let tool) = part else { continue }

                                        var providerMetadata: SharedV3ProviderMetadata? = nil
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
                                                providerExecuted: false,
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

                                        let toolCall = LanguageModelV3ToolCall(
                                            toolCallId: tool.id,
                                            toolName: tool.name,
                                            input: inputStr,
                                            providerExecuted: false,
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

                                    if let cacheCreation = usageInfo.cacheCreationInputTokens {
                                        cacheCreationInputTokens = cacheCreation
                                    }

                                    let inputTokens = usageInfo.inputTokens ?? usage.inputTokens.noCache ?? 0
                                    let cacheCreationTokens = cacheCreationInputTokens ?? usage.inputTokens.cacheWrite ?? 0
                                    let cacheReadTokens = usageInfo.cacheReadInputTokens ?? usage.inputTokens.cacheRead ?? 0
                                    let outputTokens = usageInfo.outputTokens ?? usage.outputTokens.total ?? 0

                                    usage = LanguageModelV3Usage(
                                        inputTokens: .init(
                                            total: inputTokens + cacheCreationTokens + cacheReadTokens,
                                            noCache: inputTokens,
                                            cacheRead: cacheReadTokens,
                                            cacheWrite: cacheCreationTokens
                                        ),
                                        outputTokens: .init(
                                            total: outputTokens,
                                            text: nil,
                                            reasoning: nil
                                        ),
                                        raw: rawUsage.map { .object($0) }
                                    )
                                }

                                let rawFinishReason = value.delta.stopReason
                                finishReason = LanguageModelV3FinishReason(
                                    unified: mapAnthropicStopReason(
                                        finishReason: rawFinishReason,
                                        isJsonResponseFromTool: prepared.usesJsonResponseTool
                                    ),
                                    raw: rawFinishReason
                                )
                                stopSequence = value.delta.stopSequence
                                container = anthropicContainerMetadata(value.delta.container)

                                if let newContextManagement = value.contextManagement {
                                    contextManagement = anthropicContextManagementMetadata(newContextManagement)
                                }

                            case .messageStop:
                                var metadata: [String: JSONValue] = [:]
                                metadata["usage"] = rawUsage.map(JSONValue.object) ?? .null
                                metadata["cacheCreationInputTokens"] =
                                    cacheCreationInputTokens.map { .number(Double($0)) } ?? .null
                                metadata["stopSequence"] =
                                    stopSequence.map(JSONValue.string) ?? .null
                                metadata["container"] = container
                                metadata["contextManagement"] = contextManagement

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
                                if let errorJSON = encodeToJSONValue(value) {
                                    continuation.yield(.error(error: errorJSON))
                                } else {
                                    continuation.yield(
                                        .error(error: .string("Anthropic stream error")))
                                }

                            }

                        case .failure(let error, let rawValue):
                            let errorJSON =
                                rawValue.flatMap({ try? jsonValue(from: $0) })
                                ?? .string(String(describing: error))
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
        return LanguageModelV3StreamResult(
            stream: stream, request: requestInfo, response: responseInfo)
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
        if let speed = custom.speed {
            merged.speed = speed
        }
        if let contextManagement = custom.contextManagement {
            merged.contextManagement = contextManagement
        }

        return merged
    }

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws
        -> AnthropicRequestArguments
    {
        var warnings: [SharedV3Warning] = []

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

        let anthropicOptions = mergeProviderOptions(
            canonical: canonicalOptions,
            custom: customOptions
        )

        let capabilities = getModelCapabilities(modelId: modelIdentifier.rawValue)
        let supportsStructuredOutput =
            (config.supportsNativeStructuredOutput ?? true) && capabilities.supportsStructuredOutput

        let structuredOutputMode = anthropicOptions?.structuredOutputMode ?? .auto
        let useStructuredOutput =
            structuredOutputMode == .outputFormat
            || (structuredOutputMode == .auto && supportsStructuredOutput)

        let responseFormatSchema: JSONValue? =
            if case let .json(schema, _, _) = options.responseFormat { schema } else { nil }

        // If we're not using native output_format, fall back to the json tool.
        let jsonResponseTool: LanguageModelV3FunctionTool? =
            (options.responseFormat != nil
             && responseFormatSchema != nil
             && useStructuredOutput == false)
            ? LanguageModelV3FunctionTool(
                name: "json",
                inputSchema: responseFormatSchema!,
                description: "Respond with a JSON object."
            )
            : nil

        let usesJsonResponseTool = jsonResponseTool != nil
        let contextManagement = anthropicOptions?.contextManagement
        let toolStreaming = anthropicOptions?.toolStreaming ?? true
        let cacheControlValidator = CacheControlValidator()

        let toolNameMapping = AnthropicToolNameMapping.create(
            tools: options.tools,
            providerToolNames: [
                "anthropic.code_execution_20250522": "code_execution",
                "anthropic.code_execution_20250825": "code_execution",
                "anthropic.computer_20241022": "computer",
                "anthropic.computer_20250124": "computer",
                "anthropic.computer_20251124": "computer",
                "anthropic.text_editor_20241022": "str_replace_editor",
                "anthropic.text_editor_20250124": "str_replace_editor",
                "anthropic.text_editor_20250429": "str_replace_based_edit_tool",
                "anthropic.text_editor_20250728": "str_replace_based_edit_tool",
                "anthropic.bash_20241022": "bash",
                "anthropic.bash_20250124": "bash",
                "anthropic.memory_20250818": "memory",
                "anthropic.web_search_20250305": "web_search",
                "anthropic.web_fetch_20250910": "web_fetch",
                "anthropic.tool_search_regex_20251119": "tool_search_tool_regex",
                "anthropic.tool_search_bm25_20251119": "tool_search_tool_bm25",
            ]
        )

        var conversionWarnings = warnings
        let conversion = try await convertToAnthropicMessagesPrompt(
            prompt: options.prompt,
            sendReasoning: anthropicOptions?.sendReasoning ?? true,
            toolNameMapping: toolNameMapping,
            warnings: &conversionWarnings,
            cacheControlValidator: cacheControlValidator
        )
        warnings = conversionWarnings

        var betas = conversion.betas

        var args: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "messages": .array(conversion.prompt.messages.map { $0.toJSONValue() }),
        ]

        if let system = conversion.prompt.system, !system.isEmpty {
            args["system"] = .array(system)
        }

        let inputMaxOutputTokens = options.maxOutputTokens
        let maxTokens = inputMaxOutputTokens ?? capabilities.maxOutputTokens

        args["max_tokens"] = .number(Double(maxTokens))

        // Standard sampling settings
        if let temperature {
            args["temperature"] = .number(temperature)
        }

        if let topK = options.topK {
            args["top_k"] = .number(Double(topK))
        }

        var topP = options.topP

        let thinkingMode = anthropicOptions?.thinking?.type
        let isThinking = thinkingMode == .enabled || thinkingMode == .adaptive
        var thinkingBudget = thinkingMode == .enabled ? anthropicOptions?.thinking?.budgetTokens : nil

        if !isThinking, topP != nil, temperature != nil {
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

        if let stopSequences = options.stopSequences, !stopSequences.isEmpty {
            args["stop_sequences"] = .array(stopSequences.map(JSONValue.string))
        }

        // Thinking (both manual and adaptive modes suppress sampling params)
        if isThinking {
            if thinkingMode == .enabled, thinkingBudget == nil {
                warnings.append(
                    .other(
                        message:
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
            if options.topK != nil {
                warnings.append(
                    .unsupported(
                        feature: "topK",
                        details: "topK is not supported when thinking is enabled"
                    )
                )
                args.removeValue(forKey: "top_k")
            }
            if options.topP != nil {
                warnings.append(
                    .unsupported(
                        feature: "topP",
                        details: "topP is not supported when thinking is enabled"
                    )
                )
                args.removeValue(forKey: "top_p")
            }

            switch thinkingMode {
            case .enabled:
                if let budget = thinkingBudget {
                    args["thinking"] = .object([
                        "type": .string("enabled"),
                        "budget_tokens": .number(Double(budget)),
                    ])
                    args["max_tokens"] = .number(Double(maxTokens + budget))
                }
            case .adaptive:
                // Adaptive mode: Claude dynamically decides when and how much to think
                args["thinking"] = .object(["type": .string("adaptive")])
            default:
                break
            }
        }

        // limit max output tokens for known models (including thinking budget)
        if capabilities.isKnownModel,
            case .number(let rawMaxTokensValue) = args["max_tokens"],
            Int(rawMaxTokensValue) > capabilities.maxOutputTokens
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

        // Effort
        if let effort = anthropicOptions?.effort {
            args["output_config"] = .object(["effort": .string(effort.rawValue)])
            betas.insert("effort-2025-11-24")
        }

        // Speed (fast mode, Opus 4.6 only)
        if let speed = anthropicOptions?.speed {
            args["speed"] = .string(speed.rawValue)
            if speed == .fast {
                betas.insert("fast-mode-2026-02-01")
            }
        }

        // Native structured outputs
        let usingNativeOutputFormat =
            useStructuredOutput && responseFormatSchema != nil
        if usingNativeOutputFormat, let schema = responseFormatSchema {
            args["output_format"] = .object([
                "type": .string("json_schema"),
                "schema": schema,
            ])
            betas.insert("structured-outputs-2025-11-13")
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
                        if !toolConfig.isEmpty {
                            payload["tool_configuration"] = .object(toolConfig)
                        }
                    }
                    return .object(payload)
                }
            )
        }

        // Container: ID-only (string) or ID+skills (object)
        if let container = anthropicOptions?.container,
            let containerId = container.id
        {
            if let skills = container.skills, !skills.isEmpty {
                betas.insert("code-execution-2025-08-25")
                betas.insert("skills-2025-10-02")
                betas.insert("files-api-2025-04-14")

                if options.tools?.contains(where: { tool in
                    guard case .provider(let providerTool) = tool else { return false }
                    return providerTool.id == "anthropic.code_execution_20250825"
                }) != true {
                    warnings.append(.other(message: "code execution tool is required when using skills"))
                }

                args["container"] = .object([
                    "id": .string(containerId),
                    "skills": .array(
                        skills.map { skill in
                            var skillPayload: [String: JSONValue] = [
                                "type": .string(skill.type.rawValue),
                                "skill_id": .string(skill.skillId),
                            ]
                            if let version = skill.version {
                                skillPayload["version"] = .string(version)
                            }
                            return .object(skillPayload)
                        })
                ])
            } else {
                args["container"] = .string(containerId)
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
            cacheControlValidator: cacheControlValidator
        )

        warnings.append(contentsOf: preparedTools.warnings)
        warnings.append(contentsOf: cacheControlValidator.getWarnings())
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
            usesJsonResponseTool: usesJsonResponseTool,
            toolNameMapping: toolNameMapping,
            toolStreaming: toolStreaming,
            providerOptionsName: providerOptionsName,
            usedCustomProviderKey: usedCustomProviderKey
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
            combined = combineHeaders(
                combined, ["anthropic-beta": betas.sorted().joined(separator: ",")])
        }
        if let additional {
            combined = combineHeaders(combined, additional.mapValues { Optional($0) })
        }
        return combined.compactMapValues { $0 }
    }

    private struct AnthropicModelCapabilities: Sendable {
        let maxOutputTokens: Int
        let supportsStructuredOutput: Bool
        let isKnownModel: Bool
    }

    /// Port of `getModelCapabilities` from `@ai-sdk/anthropic/src/anthropic-messages-language-model.ts`.
    private func getModelCapabilities(modelId: String) -> AnthropicModelCapabilities {
        if modelId.contains("claude-sonnet-4-6") || modelId.contains("claude-opus-4-6") {
            return AnthropicModelCapabilities(
                maxOutputTokens: 128000,
                supportsStructuredOutput: true,
                isKnownModel: true
            )
        } else if modelId.contains("claude-sonnet-4-5")
            || modelId.contains("claude-opus-4-5")
            || modelId.contains("claude-haiku-4-5")
        {
            return AnthropicModelCapabilities(
                maxOutputTokens: 64000,
                supportsStructuredOutput: true,
                isKnownModel: true
            )
        } else if modelId.contains("claude-opus-4-1") {
            return AnthropicModelCapabilities(
                maxOutputTokens: 32000,
                supportsStructuredOutput: true,
                isKnownModel: true
            )
        } else if modelId.contains("claude-sonnet-4-") || modelId.contains("claude-3-7-sonnet") {
            return AnthropicModelCapabilities(
                maxOutputTokens: 64000,
                supportsStructuredOutput: false,
                isKnownModel: true
            )
        } else if modelId.contains("claude-opus-4-") {
            return AnthropicModelCapabilities(
                maxOutputTokens: 32000,
                supportsStructuredOutput: false,
                isKnownModel: true
            )
        } else if modelId.contains("claude-3-5-haiku") {
            return AnthropicModelCapabilities(
                maxOutputTokens: 8192,
                supportsStructuredOutput: false,
                isKnownModel: true
            )
        } else if modelId.contains("claude-3-haiku") {
            return AnthropicModelCapabilities(
                maxOutputTokens: 4096,
                supportsStructuredOutput: false,
                isKnownModel: true
            )
        } else {
            return AnthropicModelCapabilities(
                maxOutputTokens: 4096,
                supportsStructuredOutput: false,
                isKnownModel: false
            )
        }
    }

    private func mapResponseContent(
        response: AnthropicMessagesResponse,
        prompt: LanguageModelV3Prompt,
        usesJsonResponseTool: Bool,
        toolNameMapping: AnthropicToolNameMapping
    ) throws -> (content: [LanguageModelV3Content], usage: LanguageModelV3Usage) {
        var content: [LanguageModelV3Content] = []
        var serverToolCalls: [String: String] = [:]
        var mcpToolCalls: [String: (toolName: String, providerMetadata: SharedV3ProviderMetadata)] = [:]
        var citationDocuments = extractCitationDocuments(from: prompt)

        for part in response.content {
            switch part {
            case .text(let value):
                if usesJsonResponseTool {
                    continue
                }

                content.append(.text(LanguageModelV3Text(text: value.text)))

                if let citations = value.citations {
                    for citation in citations {
                        if let source = createCitationSource(
                            from: citation, documents: citationDocuments)
                        {
                            content.append(.source(source))
                        }
                    }
                }

            case .thinking(let value):
                var metadata: SharedV3ProviderMetadata? = nil
                if let signature = value.signature {
                    metadata = [
                        "anthropic": ["signature": .string(signature)]
                    ]
                }
                content.append(
                    .reasoning(
                        LanguageModelV3Reasoning(text: value.thinking, providerMetadata: metadata)))

            case .redactedThinking(let value):
                let metadata: SharedV3ProviderMetadata = [
                    "anthropic": ["redactedData": .string(value.data)]
                ]
                content.append(
                    .reasoning(LanguageModelV3Reasoning(text: "", providerMetadata: metadata)))

            case .toolUse(let value):
                let isJsonResponseTool = usesJsonResponseTool && value.name == "json"
                if isJsonResponseTool {
                    content.append(.text(LanguageModelV3Text(text: stringifyJSON(value.input))))
                } else {
                    var providerMetadata: SharedV3ProviderMetadata? = nil
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

                    let toolCall = LanguageModelV3ToolCall(
                        toolCallId: value.id,
                        toolName: value.name,
                        input: stringifyJSON(value.input),
                        providerMetadata: providerMetadata
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

                    let toolCall = LanguageModelV3ToolCall(
                        toolCallId: value.id,
                        toolName: toolNameMapping.toCustomToolName("code_execution"),
                        input: stringifyJSON(inputToSerialize),
                        providerExecuted: true
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

                    let toolCall = LanguageModelV3ToolCall(
                        toolCallId: value.id,
                        toolName: toolNameMapping.toCustomToolName(value.name),
                        input: stringifyJSON(inputToSerialize),
                        providerExecuted: true
                    )
                    content.append(.toolCall(toolCall))
                } else if value.name == "tool_search_tool_regex"
                            || value.name == "tool_search_tool_bm25" {
                    serverToolCalls[value.id] = value.name
                    let toolCall = LanguageModelV3ToolCall(
                        toolCallId: value.id,
                        toolName: toolNameMapping.toCustomToolName(value.name),
                        input: stringifyJSON(value.input),
                        providerExecuted: true
                    )
                    content.append(.toolCall(toolCall))
                } else {
                    continue
                }

            case .mcpToolUse(let value):
                let providerMetadata: SharedV3ProviderMetadata = [
                    "anthropic": [
                        "type": .string("mcp-tool-use"),
                        "serverName": .string(value.serverName),
                    ]
                ]
                mcpToolCalls[value.id] = (toolName: value.name, providerMetadata: providerMetadata)
                let toolCall = LanguageModelV3ToolCall(
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
                let toolResult = LanguageModelV3ToolResult(
                    toolCallId: value.toolUseId,
                    toolName: toolInfo.toolName,
                    result: value.content,
                    isError: value.isError,
                    dynamic: true,
                    providerMetadata: toolInfo.providerMetadata
                )
                content.append(.toolResult(toolResult))

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

                    let toolResult = LanguageModelV3ToolResult(
                        toolCallId: value.toolUseId,
                        toolName: customToolName,
                        result: .array(mapped)
                    )
                    content.append(.toolResult(toolResult))
                } else if type == "tool_search_tool_result_error" {
                    let errorCode = payload["error_code"] ?? .null
                    let toolResult = LanguageModelV3ToolResult(
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
                let toolName = toolNameMapping.toCustomToolName("web_fetch")
                if case .object(let payload) = value.content,
                    let type = payload["type"], case .string(let typeString) = type
                {
                    switch typeString {
                    case "web_fetch_result":
                        guard
                            let urlValue = payload["url"], case .string(let url) = urlValue,
                            let retrievedAtValue = payload["retrieved_at"],
                            let contentValue = payload["content"],
                            case .object(let resultContent) = contentValue,
                            let sourceValue = resultContent["source"],
                            case .object(let sourceObject) = sourceValue,
                            let sourceTypeValue = sourceObject["type"],
                            case .string(let sourceType) = sourceTypeValue,
                            let mediaTypeValue = sourceObject["media_type"],
                            case .string(let mediaType) = mediaTypeValue,
                            let dataValue = sourceObject["data"], case .string(let data) = dataValue
                        else {
                            continue
                        }

                        var resultObject: [String: JSONValue] = [
                            "type": .string("web_fetch_result"),
                            "url": .string(url),
                            "retrievedAt": retrievedAtValue,
                        ]

                        var contentObject: [String: JSONValue] = [
                            "type": resultContent["type"] ?? .string("document"),
                            "title": resultContent["title"] ?? .null,
                            "source": .object([
                                "type": .string(sourceType),
                                "mediaType": .string(mediaType),
                                "data": .string(data),
                            ]),
                        ]
                        if let citations = resultContent["citations"], citations != .null {
                            contentObject["citations"] = citations
                        }
                        resultObject["content"] = .object(contentObject)

                        let documentTitle: String
                        if let titleValue = resultContent["title"],
                           case .string(let title) = titleValue {
                            documentTitle = title
                        } else {
                            documentTitle = url
                        }
                        citationDocuments.append(
                            CitationDocument(title: documentTitle, filename: nil, mediaType: mediaType))

                        let toolResult = LanguageModelV3ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: toolName,
                            result: .object(resultObject)
                        )
                        content.append(.toolResult(toolResult))

                    case "web_fetch_tool_result_error":
                        let errorCode = payload["error_code"] ?? .null
                        let toolResult = LanguageModelV3ToolResult(
                            toolCallId: value.toolUseId,
                            toolName: toolName,
                            result: .object([
                                "type": .string("web_fetch_tool_result_error"),
                                "errorCode": errorCode,
                            ]),
                            isError: true
                        )
                        content.append(.toolResult(toolResult))

                    default:
                        break
                    }
                }

            case .webSearchResult(let value):
                let toolName = toolNameMapping.toCustomToolName("web_search")
                switch value.content {
                case .array(let results):
                    var array: [JSONValue] = []
                    var sources: [LanguageModelV3Source] = []

                    for item in results {
                        guard case .object(let object) = item else { continue }
                        guard
                            let urlValue = object["url"], case .string(let url) = urlValue,
                            let encryptedValue = object["encrypted_content"],
                            case .string(let encrypted) = encryptedValue
                        else { continue }

                        let pageAge = object["page_age"]
                        let titleValue = object["title"] ?? .null
                        let title: String?
                        if case .string(let titleString) = titleValue {
                            title = titleString
                        } else {
                            title = nil
                        }
                        array.append(
                            .object([
                                "url": .string(url),
                                "title": titleValue,
                                "pageAge": pageAge ?? .null,
                                "encryptedContent": .string(encrypted),
                                "type": object["type"] ?? .string("web_search_result"),
                            ]))

                        let metadata: SharedV3ProviderMetadata = [
                            "anthropic": ["pageAge": pageAge ?? .null]
                        ]
                        sources.append(
                            .url(
                                id: generateIdentifier(),
                                url: url,
                                title: title,
                                providerMetadata: metadata
                            ))
                    }

                    let toolResult = LanguageModelV3ToolResult(
                        toolCallId: value.toolUseId,
                        toolName: toolName,
                        result: .array(array)
                    )
                    content.append(.toolResult(toolResult))

                    for source in sources {
                        content.append(.source(source))
                    }

                case .object(let object):
                    let errorCode = object["error_code"] ?? .null
                    let toolResult = LanguageModelV3ToolResult(
                        toolCallId: value.toolUseId,
                        toolName: toolName,
                        result: .object([
                            "type": .string("web_search_tool_result_error"),
                            "errorCode": errorCode,
                        ]),
                        isError: true
                    )
                    content.append(.toolResult(toolResult))

                default:
                    break
                }

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
                        let toolResult = LanguageModelV3ToolResult(
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

                    case "code_execution_tool_result_error":
                        let errorCode = payload["error_code"] ?? .null
                        let toolResult = LanguageModelV3ToolResult(
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
                let toolResult = LanguageModelV3ToolResult(
                    toolCallId: value.toolUseId,
                    toolName: toolNameMapping.toCustomToolName("code_execution"),
                    result: value.content
                )
                content.append(.toolResult(toolResult))
            }
        }

        let inputTokens = response.usage.inputTokens ?? 0
        let outputTokens = response.usage.outputTokens ?? 0
        let cacheCreationTokens = response.usage.cacheCreationInputTokens ?? 0
        let cacheReadTokens = response.usage.cacheReadInputTokens ?? 0

        let usage = LanguageModelV3Usage(
            inputTokens: .init(
                total: inputTokens + cacheCreationTokens + cacheReadTokens,
                noCache: inputTokens,
                cacheRead: cacheReadTokens,
                cacheWrite: cacheCreationTokens
            ),
            outputTokens: .init(
                total: outputTokens,
                text: nil,
                reasoning: nil
            ),
            raw: .object(anthropicUsageMetadata(response.usage))
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
        var dynamic: Bool?
        var providerMetadata: SharedV3ProviderMetadata?
        var firstDelta: Bool
        var providerToolName: String?
        var caller: ToolCallerInfo?
    }

    private struct ToolCallerInfo {
        var type: String
        var toolId: String?
    }

    private enum ContentBlockState {
        case text
        case reasoning
        case toolCall(ToolCallState)
    }

    private func extractCitationDocuments(from prompt: LanguageModelV3Prompt) -> [CitationDocument]
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
    ) -> LanguageModelV3Source? {
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
            let metadata: SharedV3ProviderMetadata = [
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

    private func contentBlockType(for content: AnthropicMessageContent) -> String {
        switch content {
        case .text: return "text"
        case .thinking: return "thinking"
        case .redactedThinking: return "redacted_thinking"
        case .toolUse: return "tool_use"
        case .serverToolUse: return "server_tool_use"
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
        citationDocuments: inout [CitationDocument],
        contentBlocks: inout [Int: ContentBlockState],
        serverToolCalls: inout [String: String],
        mcpToolCalls: inout [String: (toolName: String, providerMetadata: SharedV3ProviderMetadata)],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        switch value.contentBlock {
        case .text:
            // When a json response tool is used, the tool call is returned as text,
            // so we ignore the text content.
            if usesJsonResponseTool {
                return
            }
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
            let isJsonResponseTool = usesJsonResponseTool && tool.name == "json"
            if isJsonResponseTool {
                contentBlocks[value.index] = .text
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
                    toolName: tool.name,
                    input: initialInput,
                    providerExecuted: false,
                    dynamic: nil,
                    providerMetadata: nil,
                    firstDelta: initialInput.isEmpty,
                    providerToolName: nil,
                    caller: callerInfo
                )
                contentBlocks[value.index] = .toolCall(state)
                continuation.yield(
                    .toolInputStart(
                        id: tool.id,
                        toolName: tool.name,
                        providerMetadata: nil,
                        providerExecuted: false,
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
                let providerToolName =
                    (tool.name == "text_editor_code_execution" || tool.name == "bash_code_execution")
                    ? "code_execution"
                    : tool.name
                let customToolName = toolNameMapping.toCustomToolName(providerToolName)

                let state = ToolCallState(
                    toolCallId: tool.id,
                    toolName: customToolName,
                    input: "",
                    providerExecuted: true,
                    dynamic: nil,
                    providerMetadata: nil,
                    firstDelta: true,
                    providerToolName: tool.name,
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
            } else if tool.name == "tool_search_tool_regex" || tool.name == "tool_search_tool_bm25" {
                serverToolCalls[tool.id] = tool.name
                let customToolName = toolNameMapping.toCustomToolName(tool.name)

                let state = ToolCallState(
                    toolCallId: tool.id,
                    toolName: customToolName,
                    input: "",
                    providerExecuted: true,
                    dynamic: nil,
                    providerMetadata: nil,
                    firstDelta: true,
                    providerToolName: tool.name,
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
            let providerMetadata: SharedV3ProviderMetadata = [
                "anthropic": [
                    "type": .string("mcp-tool-use"),
                    "serverName": .string(tool.serverName),
                ]
            ]
            mcpToolCalls[tool.id] = (toolName: tool.name, providerMetadata: providerMetadata)
            let state = ToolCallState(
                toolCallId: tool.id,
                toolName: tool.name,
                input: "",
                providerExecuted: true,
                dynamic: true,
                providerMetadata: providerMetadata,
                firstDelta: true,
                providerToolName: nil,
                caller: nil
            )
            contentBlocks[value.index] = .toolCall(state)
            continuation.yield(
                .toolInputStart(
                    id: tool.id,
                    toolName: tool.name,
                    providerMetadata: providerMetadata,
                    providerExecuted: true,
                    dynamic: true,
                    title: nil
                )
            )

        case .mcpToolResult(let result):
            guard let toolInfo = mcpToolCalls[result.toolUseId] else { return }
            let toolResult = LanguageModelV3ToolResult(
                toolCallId: result.toolUseId,
                toolName: toolInfo.toolName,
                result: result.content,
                isError: result.isError,
                dynamic: true,
                providerMetadata: toolInfo.providerMetadata
            )
            continuation.yield(.toolResult(toolResult))

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
            let toolResult = LanguageModelV3ToolResult(
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
        contentBlocks: inout [Int: ContentBlockState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
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
            let metadata: SharedV3ProviderMetadata = [
                "anthropic": ["signature": .string(signature)]
            ]
            continuation.yield(
                .reasoningDelta(id: String(value.index), delta: "", providerMetadata: metadata))

        case .inputJSONDelta(let partialJSON):
            // Skip empty deltas to enable replacing the first character
            // in the code execution 20250825 tool.
            if partialJSON.isEmpty {
                return
            }

            if usesJsonResponseTool {
                continuation.yield(
                    .textDelta(id: String(value.index), delta: partialJSON, providerMetadata: nil))
            } else if case .toolCall(var toolState) = contentBlocks[value.index] {
                var delta = partialJSON
                // For the code execution 20250825, we need to add the type to the delta
                // and change the tool name.
                if toolState.firstDelta,
                   let providerToolName = toolState.providerToolName,
                   providerToolName == "bash_code_execution" || providerToolName == "text_editor_code_execution",
                   delta.first == "{" {
                    delta = "{\"type\": \"\(providerToolName)\"," + String(delta.dropFirst())
                }

                continuation.yield(
                    .toolInputDelta(
                        id: toolState.toolCallId,
                        delta: delta,
                        providerMetadata: toolState.providerMetadata
                    ))
                toolState.input += delta
                toolState.firstDelta = false
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
                continuation.yield(
                    .toolInputEnd(id: toolState.toolCallId, providerMetadata: toolState.providerMetadata))

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

                let toolCall = LanguageModelV3ToolCall(
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
        var metadata: [String: JSONValue] = [:]
        if let inputTokens = usage.inputTokens {
            metadata["input_tokens"] = .number(Double(inputTokens))
        }
        if let outputTokens = usage.outputTokens {
            metadata["output_tokens"] = .number(Double(outputTokens))
        }
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
        return metadata
    }

    private func encodeToJSONValue<T: Encodable>(_ value: T) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func convertWebFetchToolResult(
        _ content: WebFetchToolResultContent,
        toolName: String
    ) -> (LanguageModelV3ToolResult?, CitationDocument?) {
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
                    "title": inner["title"] ?? .string(""),
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
                   case .string(let titleString) = titleValue,
                   titleString.isEmpty == false {
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

            return (LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object(resultObject)
            ), document)
        }

        if type == "web_fetch_tool_result_error" {
            return (LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string("web_fetch_tool_result_error"),
                    "errorCode": payload["error_code"] ?? .null,
                ]),
                isError: true
            ), nil)
        }

        return (nil, nil)
    }

    private func convertWebSearchToolResult(
        _ content: WebSearchToolResultContent,
        toolName: String,
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
                resultsJSON.append(
                    .object([
                        "url": urlValue,
                        "title": titleValue,
                        "pageAge": pageAge,
                        "encryptedContent": object["encrypted_content"] ?? .string(""),
                        "type": object["type"] ?? .string("web_search_result"),
                    ]))

                if case .string(let url) = urlValue,
                    case .string(let title) = titleValue
                {
                    let metadata: SharedV3ProviderMetadata = [
                        "anthropic": ["pageAge": pageAge]
                    ]
                    sources.append(
                        .url(
                            id: generateSourceId(), url: url, title: title,
                            providerMetadata: metadata))
                }
            }

            let toolResult = LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .array(resultsJSON)
            )
            return (toolResult, sources)

        case .object(let object):
            let toolResult = LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .object([
                    "type": .string("web_search_tool_result_error"),
                    "errorCode": object["error_code"] ?? .null,
                ]),
                isError: true
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
        -> LanguageModelV3ToolResult?
    {
        guard case .object(let payload) = content.content else { return nil }
        guard let typeValue = payload["type"], case .string(let type) = typeValue else {
            return nil
        }

        if type == "code_execution_result" {
            return LanguageModelV3ToolResult(
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

        if type == "code_execution_tool_result_error" {
            return LanguageModelV3ToolResult(
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

    private func convertToolSearchToolResult(
        _ content: ToolSearchToolResultContent,
        toolName: String
    ) -> LanguageModelV3ToolResult? {
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

            return LanguageModelV3ToolResult(
                toolCallId: content.toolUseId,
                toolName: toolName,
                result: .array(mapped)
            )
        }

        if type == "tool_search_tool_result_error" {
            return LanguageModelV3ToolResult(
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
    ) -> SharedV3ProviderMetadata {
        var providerMetadata: SharedV3ProviderMetadata = [
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
    ) -> SharedV3ProviderMetadata? {
        guard let usageJSON = encodeToJSONValue(response.usage) else {
            return nil
        }

        let anthropicMetadata: [String: JSONValue] = [
            "usage": usageJSON,
            "cacheCreationInputTokens": response.usage.cacheCreationInputTokens.map {
                .number(Double($0))
            } ?? .null,
            "stopSequence": response.stopSequence.map(JSONValue.string) ?? .null,
            "container": anthropicContainerMetadata(response.container),
            "contextManagement": anthropicContextManagementMetadata(response.contextManagement),
        ]

        return mergeProviderMetadata(
            anthropicMetadata,
            providerOptionsName: providerOptionsName,
            usedCustomProviderKey: usedCustomProviderKey
        )
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
