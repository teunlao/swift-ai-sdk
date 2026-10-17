import Foundation
import AISDKProvider
import AISDKProviderUtils

private let openAIHTTPSURLRegex: NSRegularExpression = {
    // Safe to use try! for a static, well-formed pattern
    try! NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
}()

public final class OpenAIResponsesLanguageModel: LanguageModelV4, @unchecked Sendable {
    public let specificationVersion: String = "v4"
    private let modelIdentifier: OpenAIResponsesModelId
    private let config: OpenAIConfig
    private let providerOptionsName: String
    private static let providerToolNames: [String: String] = [
        "openai.code_interpreter": "code_interpreter",
        "openai.computer": "computer",
        "openai.file_search": "file_search",
        "openai.image_generation": "image_generation",
        "openai.local_shell": "local_shell",
        "openai.shell": "shell",
        "openai.web_search": "web_search",
        "openai.web_search_preview": "web_search_preview",
        "openai.mcp": "mcp",
        "openai.apply_patch": "apply_patch",
        "openai.tool_search": "tool_search"
    ]

    public init(modelId: OpenAIResponsesModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
        self.providerOptionsName = (config.provider as NSString).range(of: "azure", options: .literal).location != NSNotFound ? "azure" : "openai"
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            [
                "image/*": [openAIHTTPSURLRegex],
                "application/pdf": [openAIHTTPSURLRegex]
            ]
        }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options: options)

        let url = try config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses"))
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = headers.compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: url,
            headers: normalizedHeaders,
            body: prepared.body,
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAIResponsesResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let value = response.value

        if let errorPayload = value.error {
            throw APICallError(
                message: errorPayload.message,
                url: url,
                requestBodyValues: prepared.body,
                statusCode: 400,
                responseHeaders: response.responseHeaders,
                responseBody: try response.rawValue.map { try openAIJSONStringify(jsonValue(from: $0)) },
                isRetryable: false,
                data: ["code": errorPayload.code]
            )
        }

        guard let output = value.output else {
            let detail = value.incompleteDetails?.reason
            throw APICallError(
                message: detail.flatMap { $0.isEmpty ? nil : "Responses API returned no output (\($0))" } ?? "Responses API returned no output",
                url: url,
                requestBodyValues: prepared.body,
                statusCode: 500,
                responseHeaders: response.responseHeaders,
                responseBody: try response.rawValue.map { try openAIJSONStringify(jsonValue(from: $0)) },
                isRetryable: false
            )
        }

        let logprobsRequested: Bool = {
            guard let logprobs = prepared.openAIOptions?.logprobs else { return false }
            switch logprobs {
            case .bool(let flag):
                return flag
            case .number:
                return true
            }
        }()

        let approvalRequestIdToToolCallIdFromPrompt = extractApprovalRequestIdToToolCallIdMapping(options.prompt)

        let mapped = try await mapResponseOutput(
            output,
            approvalRequestIdToToolCallIdFromPrompt: approvalRequestIdToToolCallIdFromPrompt,
            webSearchToolName: prepared.webSearchToolName,
            toolNameMapping: prepared.toolNameMapping,
            logprobsRequested: logprobsRequested,
            isShellProviderExecuted: prepared.isShellProviderExecuted,
            functionTools: prepared.functionTools
        )

        let providerMetadata = makeProviderMetadata(
            responseId: value.id,
            logprobs: mapped.logprobs,
            serviceTier: value.serviceTier,
            reasoningContext: value.reasoning?.context
        )

        let usage = convertOpenAIResponsesUsage(value.usage)

        let outputWarnings = value.warnings?.map { $0.toWarning() } ?? []
        let rawFinishReason = value.incompleteDetails?.reason
        let finishReason = LanguageModelV4FinishReason(
            unified: mapOpenAIResponsesFinishReason(
                finishReason: rawFinishReason,
                hasFunctionCall: mapped.hasFunctionCall
            ),
            raw: rawFinishReason
        )

        return LanguageModelV4GenerateResult(
            content: mapped.content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV4RequestInfo(body: prepared.body),
            response: LanguageModelV4ResponseInfo(
                id: value.id,
                timestamp: value.createdAt.map { Date(timeIntervalSince1970: $0) },
                modelId: value.model,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings + outputWarnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options: options)

        let url = try config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses"))
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = headers.compactMapValues { $0 }

        var requestBody = prepared.body
        requestBody.stream = true

        let response = try await postJsonToAPI(
            url: url,
            headers: normalizedHeaders,
            body: requestBody,
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAIResponsesChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let chunkStream = try await prepareOpenAIStream(
            stream: response.value,
            getError: { chunk in
                if chunk.type == "error" { return chunk.rawValue }
                if chunk.type == "response.failed", let error = chunk.rawValue.objectValue?["response"]?.objectValue?["error"], error != .null { return chunk.rawValue }
                return nil
            },
            isOutput: { chunk in
                guard let type = chunk.type else { return false }
                return !["response.created", "response.in_progress", "response.failed", "error", "unknown_chunk"].contains(type)
            },
            isAccepted: { $0.type == "response.in_progress" },
            url: url,
            requestBodyValues: prepared.body,
            responseHeaders: response.responseHeaders
        )
        let webSearchToolName = prepared.toolNameMapping.toCustomToolName(prepared.webSearchToolName ?? "web_search")
        let logprobsRequested: Bool = {
            guard let logprobs = prepared.openAIOptions?.logprobs else { return false }
            switch logprobs {
            case .bool(let flag):
                return flag
            case .number:
                return true
            }
        }()

        let approvalRequestIdToToolCallIdFromPrompt = extractApprovalRequestIdToToolCallIdMapping(options.prompt)

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            let task = Task {
                var finishReason: LanguageModelV4FinishReason = .init(unified: .other, raw: nil)
                var usage = LanguageModelV4Usage()
                var logprobs: [JSONValue] = []
                var responseId: String?
                var serviceTier: String?
                var reasoningContext: String?
                var hasFunctionCall = false
                var encounteredStreamError = false

                var ongoingAnnotations: [JSONValue] = []
                var activeMessagePhase: String?

                let ongoingToolCalls: IndexMap<ToolCallState> = [:]
                var activeReasoning: [String: ReasoningState] = [:]
                var approvalRequestIdToDummyToolCallIdFromStream: [String: String] = [:]
                var hostedToolSearchCallIds: [String] = []

                do {
                    for try await result in chunkStream {
                        try Task.checkCancellation()
                        if options.includeRawChunks == true, let raw = result.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch result {
                        case .success(let chunk, _):
                            guard let type = chunk.type,
                                  let chunkObject = chunk.rawValue.objectValue else {
                                continue
                            }

                            switch type {
                            case "response.output_item.added":
                                try handleOutputItemAdded(
                                    chunkObject,
                                    webSearchToolName: webSearchToolName,
                                    toolNameMapping: prepared.toolNameMapping,
                                    functionTools: prepared.functionTools,
                                    ongoingAnnotations: &ongoingAnnotations,
                                    activeMessagePhase: &activeMessagePhase,
                                    ongoingToolCalls: ongoingToolCalls,
                                    activeReasoning: &activeReasoning,
                                    continuation: continuation
                                )
                            case "response.output_item.done":
                                try await handleOutputItemDone(
                                    chunkObject,
                                    webSearchToolName: webSearchToolName,
                                    toolNameMapping: prepared.toolNameMapping,
                                    functionTools: prepared.functionTools,
                                    ongoingAnnotations: &ongoingAnnotations,
                                    activeMessagePhase: &activeMessagePhase,
                                    approvalRequestIdToToolCallIdFromPrompt: approvalRequestIdToToolCallIdFromPrompt,
                                    approvalRequestIdToDummyToolCallIdFromStream: &approvalRequestIdToDummyToolCallIdFromStream,
                                    hostedToolSearchCallIds: &hostedToolSearchCallIds,
                                    ongoingToolCalls: ongoingToolCalls,
                                    activeReasoning: &activeReasoning,
                                    isShellProviderExecuted: prepared.isShellProviderExecuted,
                                    hasFunctionCall: &hasFunctionCall,
                                    continuation: continuation
                                )
                            case "response.function_call_arguments.delta":
                                handleFunctionCallArgumentsDelta(
                                    chunkObject,
                                    ongoingToolCalls: ongoingToolCalls,
                                    continuation: continuation
                                )
                            case "response.custom_tool_call_input.delta":
                                handleFunctionCallArgumentsDelta(
                                    chunkObject,
                                    ongoingToolCalls: ongoingToolCalls,
                                    continuation: continuation
                                )
                            case "response.apply_patch_call_operation_diff.delta":
                                handleApplyPatchCallOperationDiffDelta(
                                    chunkObject,
                                    ongoingToolCalls: ongoingToolCalls,
                                    continuation: continuation
                                )
                            case "response.apply_patch_call_operation_diff.done":
                                handleApplyPatchCallOperationDiffDone(
                                    chunkObject,
                                    ongoingToolCalls: ongoingToolCalls,
                                    continuation: continuation
                                )
                            case "response.image_generation_call.partial_image":
                                handleImageGenerationPartial(
                                    chunkObject,
                                    toolNameMapping: prepared.toolNameMapping,
                                    continuation: continuation
                                )
                            case "response.code_interpreter_call_code.delta":
                                handleCodeInterpreterDelta(
                                    chunkObject,
                                    ongoingToolCalls: ongoingToolCalls,
                                    continuation: continuation
                                )
                            case "response.code_interpreter_call_code.done":
                                handleCodeInterpreterDone(
                                    chunkObject,
                                    ongoingToolCalls: ongoingToolCalls,
                                    continuation: continuation
                                )
                            case "response.reasoning_summary_part.added":
                                handleReasoningSummaryPartAdded(
                                    chunkObject,
                                    activeReasoning: &activeReasoning,
                                    continuation: continuation
                                )
                            case "response.reasoning_summary_text.delta":
                                handleReasoningSummaryTextDelta(
                                    chunkObject,
                                    continuation: continuation
                                )
                            case "response.reasoning_summary_part.done":
                                handleReasoningSummaryPartDone(
                                    chunkObject,
                                    store: prepared.store,
                                    activeReasoning: &activeReasoning,
                                    continuation: continuation
                                )
                            case "response.output_text.delta":
                                handleTextDelta(
                                    chunkObject,
                                    logprobsRequested: logprobsRequested,
                                    collectedLogprobs: &logprobs,
                                    continuation: continuation
                                )
                            case "response.output_text.annotation.added":
                                handleAnnotationAdded(
                                    chunkObject,
                                    ongoingAnnotations: &ongoingAnnotations,
                                    continuation: continuation
                                )
                            case "response.created":
                                if let metadata = makeResponseMetadata(from: chunkObject) {
                                    responseId = metadata.id
                                    serviceTier = metadata.serviceTier ?? serviceTier
                                    continuation.yield(.responseMetadata(
                                        id: metadata.id,
                                        modelId: metadata.modelId,
                                        timestamp: metadata.timestamp
                                    ))
                                }
                            case "response.completed", "response.incomplete":
                                if let metadata = chunkObject["response"], let responseObject = metadata.objectValue {
                                    let rawFinishReason = responseObject["incomplete_details"]?.objectValue?["reason"]?.stringValue
                                    if !encounteredStreamError {
                                        finishReason = LanguageModelV4FinishReason(
                                            unified: mapOpenAIResponsesFinishReason(
                                                finishReason: rawFinishReason,
                                                hasFunctionCall: hasFunctionCall
                                            ),
                                            raw: rawFinishReason
                                        )
                                    }
                                    usage = convertOpenAIResponsesUsage(chunk.usage)

                                    if let tier = responseObject["service_tier"]?.stringValue {
                                        serviceTier = tier
                                    }

                                    if let context = responseObject["reasoning"]?.objectValue?["context"]?.stringValue {
                                        reasoningContext = context
                                    }

                                    if responseId == nil, let id = responseObject["id"]?.stringValue {
                                        responseId = id
                                    }
                                }
                            case "response.failed":
                                if let context = chunkObject["response"]?.objectValue?["reasoning"]?.objectValue?["context"]?.stringValue {
                                    reasoningContext = context
                                }
                                handleResponseFailed(
                                    chunkObject,
                                    parsedUsage: chunk.usage,
                                    hasFunctionCall: hasFunctionCall,
                                    finishReason: &finishReason,
                                    usage: &usage,
                                    responseId: &responseId,
                                    serviceTier: &serviceTier,
                                    encounteredStreamError: &encounteredStreamError,
                                    continuation: continuation
                                )
                            case "error":
                                encounteredStreamError = true
                                finishReason = .init(unified: .error, raw: nil)
                                continuation.yield(.error(error: createOpenAIProviderStreamError(chunk.rawValue).map(LanguageModelV4StreamError.providerStreamError) ?? .value(chunk.rawValue)))
                            default:
                                break
                            }
                        case .failure(let error, _):
                            encounteredStreamError = true
                            finishReason = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .error(error)))
                        }
                    }

                    for (_, call) in ongoingToolCalls.ordered where call.suppressInputStreaming {
                        continuation.yield(.toolInputStart(id: call.toolCallId, toolName: call.toolName, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil))
                        for delta in call.bufferedInputDeltas { continuation.yield(.toolInputDelta(id: call.toolCallId, delta: delta, providerMetadata: nil)) }
                    }
                    let metadata = makeProviderMetadata(
                        responseId: responseId,
                        logprobs: logprobs,
                        serviceTier: serviceTier,
                        reasoningContext: reasoningContext
                    )

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: usage,
                        providerMetadata: metadata
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }

        return LanguageModelV4StreamResult(
            stream: stream,
            request: LanguageModelV4RequestInfo(body: requestBody),
            response: LanguageModelV4StreamResponseInfo(headers: response.responseHeaders)
        )
    }

    private struct PreparedRequest {
        let body: OpenAIResponsesRequestBody
        let warnings: [SharedV4Warning]
        let webSearchToolName: String?
        let toolNameMapping: ToolNameMapping
        let store: Bool
        let openAIOptions: OpenAIResponsesProviderOptions?
        let isShellProviderExecuted: Bool
        let functionTools: [LanguageModelV4FunctionTool]
    }

    private static func collectCustomProviderToolNames(from tools: [LanguageModelV4Tool]?) -> Set<Data> {
        Set((tools ?? []).compactMap { tool in
            guard case .provider(let tool) = tool, tool.id == "openai.custom" else { return nil }
            return Data(tool.name.utf8)
        })
    }

    private func prepareRequest(options: LanguageModelV4CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV4Warning] = []

        func addUnsupportedSetting(_ name: String, details: String? = nil) {
            warnings.append(.unsupported(feature: name, details: details))
        }

        if options.topK != nil { addUnsupportedSetting("topK") }
        if options.seed != nil { addUnsupportedSetting("seed") }
        if options.presencePenalty != nil { addUnsupportedSetting("presencePenalty") }
        if options.frequencyPenalty != nil { addUnsupportedSetting("frequencyPenalty") }
        if options.stopSequences != nil { addUnsupportedSetting("stopSequences") }

        var openAIOptions = try await parseProviderOptions(
            provider: providerOptionsName,
            providerOptions: options.providerOptions,
            schema: openAIResponsesProviderOptionsSchema
        )

        if openAIOptions == nil, providerOptionsName != "openai" {
            openAIOptions = try await parseProviderOptions(
                provider: "openai",
                providerOptions: options.providerOptions,
                schema: openAIResponsesProviderOptionsSchema
            )
        }

        if openAIOptions?.reasoningEffort == nil, isCustomReasoning(options.reasoning), let reasoning = options.reasoning {
            if openAIOptions == nil { openAIOptions = OpenAIResponsesProviderOptions() }
            openAIOptions?.reasoningEffort = reasoning.rawValue
        }
        if let effort = openAIOptions?.reasoningEffort, effort != "none", openAIOptions?.reasoningSummary == nil {
            openAIOptions?.reasoningSummary = "detailed"
        }

        let storeOption = openAIOptions?.store
        let storeForInput = storeOption ?? true
        let hasConversation = openAIOptions?.conversation != nil
        if openAIOptions?.conversation != nil, openAIOptions?.previousResponseId != nil {
            addUnsupportedSetting("conversation", details: "conversation and previousResponseId cannot be used together")
        }
        let modelCapabilities = getOpenAIResponsesModelConfig(for: modelIdentifier)
        let isReasoningModel = openAIOptions?.forceReasoning ?? modelCapabilities.isReasoningModel
        let systemMessageMode = openAIOptions?.systemMessageMode
            ?? (isReasoningModel ? .developer : modelCapabilities.systemMessageMode)
        let hasLocalShellTool = containsLocalShellTool(options.tools)
        let hasShellTool = containsProviderTool(options.tools, id: "openai.shell")
        let hasApplyPatchTool = containsProviderTool(options.tools, id: "openai.apply_patch")
        let customProviderToolNames = Self.collectCustomProviderToolNames(from: options.tools)
        let functionTools = (options.tools ?? []).compactMap { tool -> LanguageModelV4FunctionTool? in
            if case .function(let function) = tool { return function }; return nil
        }
        let toolSearchToolName = (options.tools ?? []).compactMap { tool -> String? in
            if case .provider(let provider) = tool, provider.id == "openai.tool_search" { return provider.name }; return nil
        }.first
        let toolNameMapping = createToolNameMapping(tools: options.tools, providerToolNames: Self.providerToolNames)

        let preparedTools = try await prepareOpenAIResponsesTools(
            tools: options.tools,
            toolChoice: options.toolChoice,
            allowedTools: openAIOptions?.allowedTools,
            toolNameMapping: toolNameMapping,
            customProviderToolNames: customProviderToolNames,
            supportsAsyncToolCalling: modelCapabilities.supportsAsyncToolCalling
        )

        let (input, inputWarnings) = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: options.prompt,
            providerOptionsName: providerOptionsName,
            toolNameMapping: toolNameMapping,
            customProviderToolNames: customProviderToolNames,
            outputSchemaToolNames: preparedTools.outputSchemaToolNames,
            systemMessageMode: systemMessageMode,
            fileIdPrefixes: config.fileIdPrefixes,
            store: storeForInput,
            hasConversation: hasConversation,
            hasPreviousResponseId: openAIOptions?.previousResponseId != nil,
            passThroughUnsupportedFiles: openAIOptions?.passThroughUnsupportedFiles ?? false,
            hasLocalShellTool: hasLocalShellTool,
            hasShellTool: hasShellTool,
            hasApplyPatchTool: hasApplyPatchTool,
            hasComputerTool: containsProviderTool(options.tools, id: "openai.computer"),
            explicitMessageItemType: config.explicitMessageItemType ?? false,
            isReasoningModel: isReasoningModel,
            toolSearchToolName: toolSearchToolName
        )
        warnings.append(contentsOf: inputWarnings)

        let strictJsonSchema = openAIOptions?.strictJsonSchema ?? true
        let webSearchToolName = findWebSearchToolName(options.tools)

        var includeSet: Set<OpenAIResponsesIncludeValue> = []
        if let includes = openAIOptions?.include {
            includeSet.formUnion(includes.map(\.requestIncludeValue))
        }

        func addInclude(_ value: OpenAIResponsesIncludeValue) {
            includeSet.insert(value)
        }

        var topLogprobs: Double?
        if let logprobs = openAIOptions?.logprobs {
            switch logprobs {
            case .bool(let flag) where flag:
                topLogprobs = Double(TOP_LOGPROBS_MAX)
            case .bool:
                break
            case .number(let value):
                topLogprobs = value
            }
        }
        if topLogprobs != nil {
            addInclude(.messageOutputTextLogprobs)
        }

        if webSearchToolName != nil && config.supportsWebSearchSourcesInclude != false {
            addInclude(.webSearchCallActionSources)
        }
        if containsProviderTool(options.tools, id: "openai.code_interpreter") {
            addInclude(.codeInterpreterCallOutputs)
        }

        if storeOption == false && isReasoningModel {
            addInclude(.reasoningEncryptedContent)
        }

        let textOptions = makeTextOptions(
            responseFormat: options.responseFormat,
            textVerbosity: openAIOptions?.textVerbosity,
            strictJsonSchema: strictJsonSchema
        )

        var reasoningValue: JSONValue?
        if isReasoningModel,
           openAIOptions?.reasoningEffort != nil
            || openAIOptions?.reasoningSummary != nil
            || openAIOptions?.reasoningMode != nil
            || openAIOptions?.reasoningContext != nil {
            var payload: [String: JSONValue] = [:]
            if let effort = openAIOptions?.reasoningEffort {
                payload["effort"] = .string(effort)
            }
            if let summary = openAIOptions?.reasoningSummary {
                payload["summary"] = .string(summary)
            }
            if let mode = openAIOptions?.reasoningMode {
                payload["mode"] = .string(mode.rawValue)
            }
            if let context = openAIOptions?.reasoningContext {
                payload["context"] = .string(context.rawValue)
            }
            reasoningValue = .object(payload)
        } else {
            if openAIOptions?.reasoningEffort != nil {
                addUnsupportedSetting("reasoningEffort", details: "reasoningEffort is not supported for non-reasoning models")
            }
            if openAIOptions?.reasoningSummary != nil {
                addUnsupportedSetting("reasoningSummary", details: "reasoningSummary is not supported for non-reasoning models")
            }
            if openAIOptions?.reasoningMode != nil {
                addUnsupportedSetting("reasoningMode", details: "reasoningMode is not supported for non-reasoning models")
            }
            if openAIOptions?.reasoningContext != nil {
                addUnsupportedSetting("reasoningContext", details: "reasoningContext is not supported for non-reasoning models")
            }
        }

        var body = OpenAIResponsesRequestBody(
            model: modelIdentifier.rawValue,
            input: input,
            temperature: options.temperature,
            topP: options.topP,
            maxOutputTokens: options.maxOutputTokens,
            text: textOptions,
            maxToolCalls: openAIOptions?.maxToolCalls,
            metadata: openAIOptions?.metadata,
            parallelToolCalls: openAIOptions?.parallelToolCalls,
            previousResponseId: openAIOptions?.previousResponseId,
            conversation: openAIOptions?.conversation,
            store: storeOption,
            user: openAIOptions?.user,
            instructions: openAIOptions?.instructions,
            serviceTier: openAIOptions?.serviceTier,
            include: includeSet.isEmpty ? nil : includeSet.map { $0.rawValue },
            promptCacheKey: openAIOptions?.promptCacheKey,
            promptCacheOptions: openAIOptions?.promptCacheOptions,
            promptCacheRetention: openAIOptions?.promptCacheRetention,
            safetyIdentifier: openAIOptions?.safetyIdentifier,
            topLogprobs: topLogprobs,
            reasoning: reasoningValue,
            truncation: openAIOptions?.truncation,
            contextManagement: openAIOptions?.contextManagement?.map { item in
                .object([
                    "type": .string(item.type),
                    "compact_threshold": .number(item.compactThreshold)
                ])
            },
            tools: preparedTools.tools,
            toolChoice: preparedTools.toolChoice
        )

        if isReasoningModel {
            let allowsNonReasoningParameters = openAIOptions?.reasoningEffort == "none"
                && modelCapabilities.supportsNonReasoningParameters

            if !allowsNonReasoningParameters {
                if body.temperature != nil {
                    addUnsupportedSetting("temperature", details: "temperature is not supported for reasoning models")
                    body.temperature = nil
                }
                if body.topP != nil {
                    addUnsupportedSetting("topP", details: "topP is not supported for reasoning models")
                    body.topP = nil
                }
            }
        }

        if let serviceTier = body.serviceTier {
            switch serviceTier {
            case "flex" where !modelCapabilities.supportsFlexProcessing:
                addUnsupportedSetting("serviceTier", details: "flex processing is only available for o3, o4-mini, and gpt-5 models")
                body.serviceTier = nil
            case let tier where (tier == "priority" || tier == "fast") && !modelCapabilities.supportsPriorityProcessing:
                addUnsupportedSetting("serviceTier", details: "priority processing is only available for supported models (gpt-4, gpt-5, gpt-5-mini, o3, o4-mini) and requires Enterprise access. gpt-5-nano is not supported")
                body.serviceTier = nil
            default:
                break
            }
        }

        return PreparedRequest(
            body: body,
            warnings: warnings + preparedTools.warnings,
            webSearchToolName: webSearchToolName,
            toolNameMapping: toolNameMapping,
            store: storeForInput,
            openAIOptions: openAIOptions,
            isShellProviderExecuted: shellToolIsProviderExecuted(options.tools),
            functionTools: functionTools
        )
    }

    private func makeTextOptions(
        responseFormat: LanguageModelV4ResponseFormat?,
        textVerbosity: String?,
        strictJsonSchema: Bool
    ) -> JSONValue? {
        var payload: [String: JSONValue] = [:]

        if let responseFormat {
            switch responseFormat {
            case .text:
                break
            case .json(let schema, let name, let description):
                var formatPayload: [String: JSONValue] = [
                    "type": .string(schema == nil ? "json_object" : "json_schema")
                ]
                if let schema {
                    formatPayload["strict"] = .bool(strictJsonSchema)
                    formatPayload["name"] = .string(name ?? "response")
                    if let description {
                        formatPayload["description"] = .string(description)
                    }
                    formatPayload["schema"] = schema
                }
                payload["format"] = .object(formatPayload)
            }
        }

        if let textVerbosity {
            payload["verbosity"] = .string(textVerbosity)
        }

        return payload.isEmpty ? nil : .object(payload)
    }

    private func containsLocalShellTool(_ tools: [LanguageModelV4Tool]?) -> Bool {
        guard let tools else { return false }
        return tools.contains { tool in
            if case .provider(let providerTool) = tool {
                return providerTool.id == "openai.local_shell"
            }
            return false
        }
    }

    private func containsProviderTool(_ tools: [LanguageModelV4Tool]?, id: String) -> Bool {
        guard let tools else { return false }
        return tools.contains { tool in
            if case .provider(let providerTool) = tool {
                return providerTool.id == id
            }
            return false
        }
    }

    private func findWebSearchToolName(_ tools: [LanguageModelV4Tool]?) -> String? {
        guard let tools else { return nil }
        for tool in tools {
            if case .provider(let providerTool) = tool,
               providerTool.id == "openai.web_search" || providerTool.id == "openai.web_search_preview" {
                return providerTool.name
            }
        }
        return nil
    }

    private func shellToolIsProviderExecuted(_ tools: [LanguageModelV4Tool]?) -> Bool {
        guard let tools else { return false }

        for tool in tools {
            guard case .provider(let providerTool) = tool,
                  providerTool.id == "openai.shell",
                  let environment = providerTool.args["environment"]?.objectValue else {
                continue
            }

            let environmentType = environment["type"]?.stringValue
            if environmentType == "containerAuto" || environmentType == "containerReference" {
                return true
            }
        }

        return false
    }

    private struct MappedResponse {
        let content: [LanguageModelV4Content]
        let logprobs: [JSONValue]
        let hasFunctionCall: Bool
    }

    private func extractApprovalRequestIdToToolCallIdMapping(_ prompt: LanguageModelV4Prompt) -> [String: String] {
        var mapping: [String: String] = [:]
        for message in prompt {
            guard case .assistant(let parts, _) = message else { continue }
            for part in parts {
                guard case .toolCall(let toolCall) = part else { continue }
                let providerOptions = toolCall.providerOptions
                let approvalRequestId = providerOptions?["openai"]?["approvalRequestId"]?.stringValue
                    ?? providerOptions?[providerOptionsName]?["approvalRequestId"]?.stringValue
                if let approvalRequestId {
                    mapping[approvalRequestId] = toolCall.toolCallId
                }
            }
        }
        return mapping
    }

    private func mapResponseOutput(
        _ output: [JSONValue],
        approvalRequestIdToToolCallIdFromPrompt: [String: String],
        webSearchToolName: String?,
        toolNameMapping: ToolNameMapping,
        logprobsRequested: Bool,
        isShellProviderExecuted: Bool,
        functionTools: [LanguageModelV4FunctionTool]
    ) async throws -> MappedResponse {
        var content: [LanguageModelV4Content] = []
        var logprobs: [JSONValue] = []
        var hasFunctionCall = false
        var hostedToolSearchCallIds: [String] = []

        for item in output {
            guard let object = item.objectValue,
                  let type = object["type"]?.stringValue else {
                continue
            }

            switch type {
            case "reasoning":
                var summary = object["summary"]?.arrayValue ?? []
                if summary.isEmpty {
                    summary = [.object(["type": .string("summary_text"), "text": .string("")])]
                }

                let itemId = object["id"]?.stringValue ?? generateID()
                let encrypted = object["encrypted_content"]?.stringValue
                let metadata = openAIProviderMetadata([
                    "itemId": .string(itemId),
                    "reasoningEncryptedContent": encrypted.map(JSONValue.string) ?? .null
                ])

                for entry in summary {
                    guard let entryObject = entry.objectValue,
                          let text = entryObject["text"]?.stringValue else { continue }
                    content.append(.reasoning(LanguageModelV4Reasoning(text: text, providerMetadata: metadata)))
                }

            case "message":
                guard let itemId = object["id"]?.stringValue,
                      let parts = object["content"]?.arrayValue else {
                    continue
                }

                for part in parts {
                    guard let partObject = part.objectValue,
                          partObject["type"]?.stringValue == "output_text",
                          let text = partObject["text"]?.stringValue else {
                        continue
                    }

                    if logprobsRequested, let logprobValue = partObject["logprobs"], logprobValue != .null {
                        logprobs.append(logprobValue)
                    }

                    let rawAnnotations = partObject["annotations"]?.arrayValue ?? []
                    let annotations = rawAnnotations.compactMap { filterOpenAIResponsesAnnotation($0) }
                    var textMetadataItems: [String: JSONValue] = ["itemId": .string(itemId)]
                    if let phase = object["phase"]?.stringValue {
                        textMetadataItems["phase"] = .string(phase)
                    }
                    if !annotations.isEmpty {
                        textMetadataItems["annotations"] = .array(annotations)
                    }
                    let textMetadata = openAIProviderMetadata(textMetadataItems)

                    content.append(.text(LanguageModelV4Text(text: text, providerMetadata: textMetadata)))

                    for annotation in annotations {
                        guard let annotationObject = annotation.objectValue,
                              let annotationType = annotationObject["type"]?.stringValue else {
                            continue
                        }

                        switch annotationType {
                        case "url_citation":
                            guard let url = annotationObject["url"]?.stringValue else { continue }
                            let title = annotationObject["title"]?.stringValue
                            content.append(.source(.url(
                                id: nextSourceId(),
                                url: url,
                                title: title,
                                providerMetadata: nil
                            )))

                        case "file_citation":
                            guard let fileId = annotationObject["file_id"]?.stringValue,
                                  let filename = annotationObject["filename"]?.stringValue else { continue }

                            var metadataItems: [String: JSONValue] = [
                                "type": .string("file_citation"),
                                "fileId": .string(fileId)
                            ]
                            if let index = annotationObject["index"], index != .null {
                                metadataItems["index"] = index
                            }

                            content.append(.source(.document(
                                id: nextSourceId(),
                                mediaType: "text/plain",
                                title: filename,
                                filename: filename,
                                providerMetadata: openAIProviderMetadata(metadataItems)
                            )))

                        case "container_file_citation":
                            guard let fileId = annotationObject["file_id"]?.stringValue,
                                  let containerId = annotationObject["container_id"]?.stringValue,
                                  let filename = annotationObject["filename"]?.stringValue else { continue }

                            content.append(.source(.document(
                                id: nextSourceId(),
                                mediaType: "text/plain",
                                title: filename,
                                filename: filename,
                                providerMetadata: openAIProviderMetadata([
                                    "type": .string("container_file_citation"),
                                    "fileId": .string(fileId),
                                    "containerId": .string(containerId)
                                ])
                            )))

                        case "file_path":
                            guard let fileId = annotationObject["file_id"]?.stringValue else { continue }

                            var metadataItems: [String: JSONValue] = [
                                "type": .string("file_path"),
                                "fileId": .string(fileId)
                            ]
                            if let index = annotationObject["index"], index != .null {
                                metadataItems["index"] = index
                            }

                            content.append(.source(.document(
                                id: nextSourceId(),
                                mediaType: "application/octet-stream",
                                title: fileId,
                                filename: fileId,
                                providerMetadata: openAIProviderMetadata(metadataItems)
                            )))

                        default:
                            break
                        }
                    }
                }

            case "function_call":
                guard let toolCallId = object["call_id"]?.stringValue,
                      let toolName = object["name"]?.stringValue,
                      let input = object["arguments"]?.stringValue else {
                    continue
                }
                hasFunctionCall = true

                var callMetadata: [String: JSONValue] = ["itemId": object["id"]!]
                for key in ["async", "namespace"] { if let value = object[key], value != .null { callMetadata[key] = value } }
                let providerMetadata = openAIProviderMetadata(callMetadata)

                let call = LanguageModelV4ToolCall(toolCallId: toolCallId, toolName: toolName, input: input, providerMetadata: providerMetadata)
                if let expanded = try await OpenAIParallelCalls.expand(call, itemId: object["id"]!.stringValue!, tools: functionTools, namespace: providerOptionsName) {
                    content.append(contentsOf: expanded.map(LanguageModelV4Content.toolCall))
                } else { content.append(.toolCall(call)) }

            case "custom_tool_call":
                guard let toolCallId = object["call_id"]?.stringValue,
                      let providerToolName = object["name"]?.stringValue,
                      let rawInput = object["input"]?.stringValue else {
                    continue
                }
                hasFunctionCall = true

                var metadata: [String: JSONValue] = ["itemId": object["id"] ?? .null]
                if let value = object["async"], value != .null { metadata["async"] = value }
                let providerMetadata = openAIProviderMetadata(metadata)
                let toolName = toolNameMapping.toCustomToolName(providerToolName)
                let input = try openAIJSONStringify(.string(rawInput))

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    input: input,
                    providerExecuted: nil,
                    providerMetadata: providerMetadata
                )))

            case "tool_search_call":
                guard let itemId = object["id"]?.stringValue else { continue }
                let toolCallId = object["call_id"]?.stringValue ?? itemId
                let isHosted = object["execution"]?.stringValue == "server"
                if isHosted {
                    hostedToolSearchCallIds.append(toolCallId)
                }

                let inputValue: JSONValue = .object([
                    "arguments": object["arguments"] ?? .null,
                    "call_id": object["call_id"] ?? .null
                ])
                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("tool_search"),
                    input: try openAIJSONStringify(inputValue),
                    providerExecuted: isHosted ? true : nil,
                    providerMetadata: openAIProviderMetadata(["itemId": .string(itemId)])
                )))

            case "tool_search_output":
                guard let itemId = object["id"]?.stringValue else { continue }
                let toolCallId = object["call_id"]?.stringValue
                    ?? (hostedToolSearchCallIds.isEmpty ? nil : hostedToolSearchCallIds.removeFirst())
                    ?? itemId
                content.append(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("tool_search"),
                    result: .object([
                        "tools": object["tools"] ?? .array([])
                    ]),
                    isError: nil,
                    preliminary: nil,
                    providerMetadata: openAIProviderMetadata(["itemId": .string(itemId)])
                )))

            case "compaction":
                guard let itemId = object["id"]?.stringValue else { continue }
                var metadataItems: [String: JSONValue] = [
                    "type": .string("compaction"),
                    "itemId": .string(itemId)
                ]
                if let encryptedContent = object["encrypted_content"]?.stringValue {
                    metadataItems["encryptedContent"] = .string(encryptedContent)
                }
                content.append(.custom(LanguageModelV4CustomContent(
                    kind: "openai.compaction",
                    providerMetadata: openAIProviderMetadata(metadataItems)
                )))

            case "web_search_call":
                guard let toolCallId = object["id"]?.stringValue,
                      let mappedOutput = mapWebSearchOutput(object["action"]) else { continue }

                let toolName = toolNameMapping.toCustomToolName(webSearchToolName ?? "web_search")

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    input: "{}",
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                content.append(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    result: mappedOutput,
                    isError: nil,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "mcp_call":
                guard let itemId = object["id"]?.stringValue,
                      let name = object["name"]?.stringValue,
                      let arguments = object["arguments"]?.stringValue,
                      let serverLabel = object["server_label"]?.stringValue else {
                    continue
                }

                let approvalRequestId = object["approval_request_id"]?.stringValue
                let toolCallId = approvalRequestId.flatMap { approvalRequestIdToToolCallIdFromPrompt[$0] } ?? itemId
                let toolName = "mcp.\(name)"

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    input: arguments,
                    providerExecuted: true,
                    dynamic: true,
                    providerMetadata: nil
                )))

                var resultPayload: [String: JSONValue] = [
                    "type": .string("call"),
                    "serverLabel": .string(serverLabel),
                    "name": .string(name),
                    "arguments": .string(arguments)
                ]
                if let output = object["output"], output != .null {
                    resultPayload["output"] = output
                }
                if let error = object["error"], error != .null {
                    resultPayload["error"] = error
                }

                let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
                content.append(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    result: .object(resultPayload),
                    isError: nil,
                    preliminary: nil,
                    providerMetadata: metadata
                )))

            case "mcp_list_tools":
                // Skip list tools - we don't expose this to the UI or send it back
                break

            case "mcp_approval_request":
                guard let itemId = object["id"]?.stringValue,
                      let name = object["name"]?.stringValue,
                      let arguments = object["arguments"]?.stringValue else {
                    continue
                }

                let approvalRequestId = object["approval_request_id"]?.stringValue ?? itemId
                let dummyToolCallId = config.generateId?() ?? generateID()
                let toolName = "mcp.\(name)"

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: dummyToolCallId,
                    toolName: toolName,
                    input: arguments,
                    providerExecuted: true,
                    dynamic: true,
                    providerMetadata: nil
                )))

                content.append(.toolApprovalRequest(LanguageModelV4ToolApprovalRequest(
                    approvalId: approvalRequestId,
                    toolCallId: dummyToolCallId,
                    providerMetadata: nil
                )))

            case "computer_call":
                if let callId = object["call_id"]?.stringValue {
                    hasFunctionCall = true
                    content.append(.toolCall(LanguageModelV4ToolCall(
                        toolCallId: callId,
                        toolName: toolNameMapping.toCustomToolName("computer"),
                        input: try openAIJSONStringify(mapOpenAIComputerCallInput(object)),
                        providerMetadata: openAIProviderMetadata(["itemId": object["id"]!])
                    )))
                    continue
                }
                guard let toolCallId = object["id"]?.stringValue else { continue }
                let status = object["status"]?.stringValue ?? "completed"

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("computer_use"),
                    input: "",
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                let resultValue: JSONValue = .object([
                    "type": .string("computer_use_tool_result"),
                    "status": .string(status)
                ])
                content.append(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("computer_use"),
                    result: resultValue,
                    isError: nil,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "file_search_call":
                guard let toolCallId = object["id"]?.stringValue else { continue }

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("file_search"),
                    input: "{}",
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                let queries = object["queries"]?.arrayValue?.compactMap { $0.stringValue } ?? []
                let resultsArray = object["results"]?.arrayValue?.compactMap { entry -> JSONValue? in
                    guard let entryObject = entry.objectValue,
                          let attributes = entryObject["attributes"],
                          let fileId = entryObject["file_id"]?.stringValue,
                          let filename = entryObject["filename"]?.stringValue,
                          let score = entryObject["score"]?.numberValue,
                          let text = entryObject["text"]?.stringValue else {
                        return nil
                    }
                    return .object([
                        "attributes": attributes,
                        "fileId": .string(fileId),
                        "filename": .string(filename),
                        "score": .number(score),
                        "text": .string(text)
                    ])
                }
                let resultValue: JSONValue = .object([
                    "queries": .array(queries.map(JSONValue.string)),
                    "results": resultsArray.map(JSONValue.array) ?? .null
                ])

                content.append(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("file_search"),
                    result: resultValue,
                    isError: nil,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "code_interpreter_call":
                guard let toolCallId = object["id"]?.stringValue,
                      let containerId = object["container_id"]?.stringValue else {
                    continue
                }
                var inputPayload: [String: JSONValue] = [
                    "containerId": .string(containerId)
                ]
                if let code = object["code"] {
                    inputPayload["code"] = code
                }
                let inputValue: JSONValue = .object(inputPayload)
                let inputString = try openAIJSONStringify(inputValue)

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("code_interpreter"),
                    input: inputString,
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                var resultPayload: [String: JSONValue] = [:]
                if let outputs = object["outputs"] {
                    resultPayload["outputs"] = outputs
                }
                let resultValue: JSONValue = .object(resultPayload)
                content.append(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("code_interpreter"),
                    result: resultValue,
                    isError: nil,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "image_generation_call":
                guard let toolCallId = object["id"]?.stringValue,
                      let resultString = object["result"]?.stringValue else {
                    continue
                }

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("image_generation"),
                    input: "{}",
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                let resultValue: JSONValue = .object(["result": .string(resultString)])
                content.append(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("image_generation"),
                    result: resultValue,
                    isError: nil,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "shell_call":
                guard let toolCallId = object["call_id"]?.stringValue,
                      let actionObject = object["action"]?.objectValue,
                      let commands = actionObject["commands"]?.arrayValue?.compactMap({ $0.stringValue }),
                      let itemId = object["id"]?.stringValue else {
                    continue
                }

                let inputValue: JSONValue = .object([
                    "action": .object([
                        "commands": .array(commands.map(JSONValue.string))
                    ])
                ])
                let inputString = try openAIJSONStringify(inputValue)
                let metadata = openAIProviderMetadata(["itemId": .string(itemId)])

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("shell"),
                    input: inputString,
                    providerExecuted: isShellProviderExecuted ? true : nil,
                    providerMetadata: metadata
                )))

            case "shell_call_output":
                guard let toolCallId = object["call_id"]?.stringValue,
                      let outputs = object["output"]?.arrayValue else {
                    continue
                }

                let mappedOutputs = outputs.compactMap { outputEntry -> JSONValue? in
                    guard let outputObject = outputEntry.objectValue,
                          let stdout = outputObject["stdout"]?.stringValue,
                          let stderr = outputObject["stderr"]?.stringValue,
                          let outcomeObject = outputObject["outcome"]?.objectValue,
                          let outcomeType = outcomeObject["type"]?.stringValue else {
                        return nil
                    }

                    let outcome: JSONValue
                    if outcomeType == "exit" {
                        guard let exitCode = outcomeObject["exit_code"]?.numberValue else {
                            return nil
                        }
                        outcome = .object([
                            "type": .string("exit"),
                            "exitCode": .number(exitCode)
                        ])
                    } else if outcomeType == "timeout" {
                        outcome = .object([
                            "type": .string("timeout")
                        ])
                    } else {
                        return nil
                    }

                    return .object([
                        "stdout": .string(stdout),
                        "stderr": .string(stderr),
                        "outcome": outcome
                    ])
                }

                let resultValue: JSONValue = .object([
                    "output": .array(mappedOutputs)
                ])

                content.append(.toolResult(LanguageModelV4ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("shell"),
                    result: resultValue,
                    isError: nil,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "apply_patch_call":
                guard let toolCallId = object["call_id"]?.stringValue,
                      let operation = object["operation"],
                      let itemId = object["id"]?.stringValue else {
                    continue
                }

                let inputValue: JSONValue = .object([
                    "callId": .string(toolCallId),
                    "operation": operation
                ])
                let inputString = try openAIJSONStringify(inputValue)
                let metadata = openAIProviderMetadata(["itemId": .string(itemId)])

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("apply_patch"),
                    input: inputString,
                    providerExecuted: nil,
                    providerMetadata: metadata
                )))

            case "local_shell_call":
                guard let toolCallId = object["call_id"]?.stringValue,
                      let actionObject = object["action"]?.objectValue,
                      let actionType = actionObject["type"]?.stringValue,
                      let commands = actionObject["command"]?.arrayValue?.compactMap({ $0.stringValue }),
                      let itemId = object["id"]?.stringValue else {
                    continue
                }

                var actionPayload: [String: JSONValue] = [
                    "type": .string(actionType),
                    "command": .array(commands.map(JSONValue.string))
                ]
                if let timeoutMs = actionObject["timeout_ms"]?.numberValue {
                    actionPayload["timeoutMs"] = .number(timeoutMs)
                }
                if let user = actionObject["user"]?.stringValue {
                    actionPayload["user"] = .string(user)
                }
                if let workingDirectory = actionObject["working_directory"]?.stringValue {
                    actionPayload["workingDirectory"] = .string(workingDirectory)
                }
                if let env = actionObject["env"]?.objectValue {
                    let mappedEnv = env.compactMapValues { value in value.stringValue.map(JSONValue.string) }
                    actionPayload["env"] = .object(mappedEnv)
                }

                let inputValue: JSONValue = .object(["action": .object(actionPayload)])
                let inputString = try openAIJSONStringify(inputValue)
                let metadata = openAIProviderMetadata(["itemId": .string(itemId)])

                content.append(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolNameMapping.toCustomToolName("local_shell"),
                    input: inputString,
                    providerExecuted: nil,
                    providerMetadata: metadata
                )))

            default:
                break
            }
        }

        return MappedResponse(content: content, logprobs: logprobs, hasFunctionCall: hasFunctionCall)
    }

    private func makeProviderMetadata(
        responseId: String?,
        logprobs: [JSONValue],
        serviceTier: String?,
        reasoningContext: String?
    ) -> SharedV4ProviderMetadata? {
        var inner: [String: JSONValue] = [:]
        if let responseId {
            inner["responseId"] = .string(responseId)
        }
        if !logprobs.isEmpty {
            inner["logprobs"] = .array(logprobs)
        }
        if let serviceTier {
            inner["serviceTier"] = .string(serviceTier)
        }
        if let reasoningContext {
            inner["reasoningContext"] = .string(reasoningContext)
        }
        return inner.isEmpty ? nil : [providerOptionsName: inner]
    }

    private func nextSourceId() -> String {
        config.generateId?() ?? generateID()
    }

    // MARK: - Streaming helpers
    
    private struct ToolCallState {
        let toolName: String
        let toolCallId: String
        let providerExecuted: Bool
        let codeInterpreter: CodeInterpreterState?
        var applyPatch: ApplyPatchState?
        var suppressInputStreaming = false
        var bufferedInputDeltas: [String] = []
        var asyncValue: JSONValue? = nil
    }

    private struct CodeInterpreterState {
        let containerId: String
    }

    private struct ApplyPatchState {
        var hasDiff: Bool
        var endEmitted: Bool
    }

    private final class IndexMap<Value>: ExpressibleByDictionaryLiteral {
        private var values: [Double: Value] = [:]
        private var creation: [Double] = []
        private var known: Set<Double> = []

        init(dictionaryLiteral elements: (Double, Value)...) {
            for (index, value) in elements { self[index] = value }
        }
        subscript(index: Double) -> Value? {
            get { values[index] }
            set {
                if known.insert(index).inserted { creation.append(index) }
                values[index] = newValue
            }
        }
        var count: Int { values.count }
        var ordered: [(Double, Value)] {
            var indices: [Double] = []
            var others: [Double] = []
            for key in creation where values[key] != nil {
                // ECMAScript ranks array indices below UInt32.max before other keys.
                if key >= 0 && key < Double(UInt32.max) && key.rounded(.towardZero) == key {
                    indices.append(key)
                } else {
                    others.append(key)
                }
            }
            return (indices.sorted() + others).map { ($0, values[$0]!) }
        }
    }
    private enum SummaryStatus: Sendable { case active, canConclude, concluded }
    private struct ReasoningState {
        var encryptedContent: String?
        let summaryParts: IndexMap<SummaryStatus>
    }

    private struct ResponseMetadata {
        let id: String
        let modelId: String?
        let timestamp: Date?
        let serviceTier: String?
    }

    private func openAIProviderMetadata(_ items: [String: JSONValue]) -> SharedV4ProviderMetadata {
        var filtered: [String: JSONValue] = [:]
        for (key, value) in items {
            filtered[key] = value
        }
        return [providerOptionsName: filtered]
    }

    private func filterOpenAIResponsesAnnotation(_ annotation: JSONValue) -> JSONValue? {
        guard let object = annotation.objectValue,
              let type = object["type"]?.stringValue else {
            return nil
        }

        switch type {
        case "url_citation":
            guard let url = object["url"]?.stringValue,
                  let title = object["title"]?.stringValue,
                  let startIndex = object["start_index"], startIndex != .null,
                  let endIndex = object["end_index"], endIndex != .null else {
                return nil
            }

            return .object([
                "type": .string("url_citation"),
                "start_index": startIndex,
                "end_index": endIndex,
                "url": .string(url),
                "title": .string(title)
            ])

        case "file_citation":
            guard let fileId = object["file_id"]?.stringValue,
                  let filename = object["filename"]?.stringValue,
                  let index = object["index"], index != .null else {
                return nil
            }

            return .object([
                "type": .string("file_citation"),
                "file_id": .string(fileId),
                "filename": .string(filename),
                "index": index
            ])

        case "container_file_citation":
            guard let containerId = object["container_id"]?.stringValue,
                  let fileId = object["file_id"]?.stringValue,
                  let filename = object["filename"]?.stringValue,
                  let startIndex = object["start_index"], startIndex != .null,
                  let endIndex = object["end_index"], endIndex != .null else {
                return nil
            }

            return .object([
                "type": .string("container_file_citation"),
                "container_id": .string(containerId),
                "file_id": .string(fileId),
                "filename": .string(filename),
                "start_index": startIndex,
                "end_index": endIndex
            ])

        case "file_path":
            guard let fileId = object["file_id"]?.stringValue,
                  let index = object["index"], index != .null else {
                return nil
            }

            return .object([
                "type": .string("file_path"),
                "file_id": .string(fileId),
                "index": index
            ])

        default:
            return nil
        }
    }

    private func mapWebSearchOutput(_ action: JSONValue?) -> JSONValue? {
        guard let action else {
            return .object([:])
        }
        guard action != .null else {
            return .object([:])
        }
        guard let actionObject = action.objectValue,
              let actionType = actionObject["type"]?.stringValue else {
            return nil
        }

        switch actionType {
        case "search":
            var mappedAction: [String: JSONValue] = [
                "type": .string("search")
            ]
            if let query = actionObject["query"]?.stringValue {
                mappedAction["query"] = .string(query)
            }
            if let queries = actionObject["queries"], queries != .null { mappedAction["queries"] = queries }

            var result: [String: JSONValue] = [
                "action": .object(mappedAction)
            ]
            if let sources = actionObject["sources"], sources != .null {
                result["sources"] = sources
            }

            return .object(result)

        case "open_page":
            var value: [String: JSONValue] = ["type": .string("openPage")]
            value["url"] = actionObject["url"]
            return .object(["action": .object(value)])

        case "find_in_page":
            var value: [String: JSONValue] = ["type": .string("findInPage")]
            value["url"] = actionObject["url"]
            value["pattern"] = actionObject["pattern"]
            return .object(["action": .object(value)])

        default:
            return nil
        }
    }

    private func handleOutputItemAdded(
        _ chunk: [String: JSONValue],
        webSearchToolName: String,
        toolNameMapping: ToolNameMapping,
        functionTools: [LanguageModelV4FunctionTool],
        ongoingAnnotations: inout [JSONValue],
        activeMessagePhase: inout String?,
        ongoingToolCalls: IndexMap<ToolCallState>,
        activeReasoning: inout [String: ReasoningState],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) throws {
        guard let outputIndex = chunk["output_index"]?.numberValue,
              let item = chunk["item"]?.objectValue,
              let type = item["type"]?.stringValue else {
            return
        }

        switch type {
        case "function_call":
            guard let callId = item["call_id"]?.stringValue,
                  let name = item["name"]?.stringValue else { return }
            let suppressed = OpenAIParallelCalls.isWrapper(name, tools: functionTools)
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: name, toolCallId: callId, providerExecuted: false, codeInterpreter: nil, applyPatch: nil,
                suppressInputStreaming: suppressed, asyncValue: item["async"]
            )
            if !suppressed { continuation.yield(.toolInputStart(id: callId, toolName: name, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil)) }
        case "custom_tool_call":
            guard let callId = item["call_id"]?.stringValue,
                  let providerToolName = item["name"]?.stringValue else { return }
            let toolName = toolNameMapping.toCustomToolName(providerToolName)
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: toolName,
                toolCallId: callId,
                providerExecuted: false,
                codeInterpreter: nil,
                applyPatch: nil,
                asyncValue: item["async"]
            )
            continuation.yield(.toolInputStart(
                id: callId,
                toolName: toolName,
                providerMetadata: nil,
                providerExecuted: nil,
                dynamic: nil,
                title: nil,
                inputEncoding: .text
            ))
        case "web_search_call":
            guard let callId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: webSearchToolName,
                toolCallId: callId,
                providerExecuted: true,
                codeInterpreter: nil,
                applyPatch: nil
            )
            continuation.yield(.toolInputStart(
                id: callId,
                toolName: webSearchToolName,
                providerMetadata: nil,
                providerExecuted: true,
                dynamic: nil,
                title: nil
            ))
            continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: callId,
                toolName: webSearchToolName,
                input: "{}",
                providerExecuted: true,
                providerMetadata: nil
            )))
        case "computer_call":
            guard let callId = item["call_id"]?.stringValue ?? item["id"]?.stringValue else { return }
            let toolName = toolNameMapping.toCustomToolName("computer")
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: toolName,
                toolCallId: callId,
                providerExecuted: false,
                codeInterpreter: nil,
                applyPatch: nil
            )
            continuation.yield(.toolInputStart(
                id: callId,
                toolName: toolName,
                providerMetadata: nil,
                providerExecuted: nil,
                dynamic: nil,
                title: nil
            ))
        case "code_interpreter_call":
            guard let callId = item["id"]?.stringValue,
                  let containerId = item["container_id"]?.stringValue else { return }
            let state = CodeInterpreterState(containerId: containerId)
            let toolName = toolNameMapping.toCustomToolName("code_interpreter")
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: toolName,
                toolCallId: callId,
                providerExecuted: true,
                codeInterpreter: state,
                applyPatch: nil
            )
            continuation.yield(.toolInputStart(
                id: callId,
                toolName: toolName,
                providerMetadata: nil,
                providerExecuted: true,
                dynamic: nil,
                title: nil
            ))
            let initial = "{\"containerId\":\"\(containerId)\",\"code\":\""
            continuation.yield(.toolInputDelta(id: callId, delta: initial, providerMetadata: nil))
        case "apply_patch_call":
            guard let callId = item["call_id"]?.stringValue,
                  let operationObject = item["operation"]?.objectValue,
                  let operationType = operationObject["type"]?.stringValue,
                  let path = operationObject["path"]?.stringValue else { return }

            let isDelete = operationType == "delete_file"
            let toolName = toolNameMapping.toCustomToolName("apply_patch")
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: toolName,
                toolCallId: callId,
                providerExecuted: false,
                codeInterpreter: nil,
                applyPatch: ApplyPatchState(hasDiff: isDelete, endEmitted: isDelete)
            )
            continuation.yield(.toolInputStart(
                id: callId,
                toolName: toolName,
                providerMetadata: nil,
                providerExecuted: nil,
                dynamic: nil,
                title: nil
            ))
            if isDelete {
                let inputValue: JSONValue = .object([
                    "callId": .string(callId),
                    "operation": .object([
                        "type": .string(operationType),
                        "path": .string(path)
                    ])
                ])
                let inputString = try openAIJSONStringify(inputValue)
                continuation.yield(.toolInputDelta(id: callId, delta: inputString, providerMetadata: nil))
                continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
            } else {
                let escapedCallId = escapeJSONString(callId)
                let escapedOperationType = escapeJSONString(operationType)
                let escapedPath = escapeJSONString(path)
                let prefix = "{\"callId\":\"\(escapedCallId)\",\"operation\":{\"type\":\"\(escapedOperationType)\",\"path\":\"\(escapedPath)\",\"diff\":\""
                continuation.yield(.toolInputDelta(id: callId, delta: prefix, providerMetadata: nil))
            }
        case "shell_call":
            guard let callId = item["call_id"]?.stringValue else { return }
            let toolName = toolNameMapping.toCustomToolName("shell")
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: toolName,
                toolCallId: callId,
                providerExecuted: false,
                codeInterpreter: nil,
                applyPatch: nil
            )
        case "file_search_call":
            guard let callId = item["id"]?.stringValue else { return }
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: callId,
                toolName: toolNameMapping.toCustomToolName("file_search"),
                input: "{}",
                providerExecuted: true,
                providerMetadata: nil
            )))
        case "image_generation_call":
            guard let callId = item["id"]?.stringValue else { return }
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: callId,
                toolName: toolNameMapping.toCustomToolName("image_generation"),
                input: "{}",
                providerExecuted: true,
                providerMetadata: nil
            )))
        case "tool_search_call":
            guard let itemId = item["id"]?.stringValue else { return }
            let execution = item["execution"]?.stringValue ?? "server"
            let isHosted = execution == "server"
            let toolName = toolNameMapping.toCustomToolName("tool_search")
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: toolName,
                toolCallId: itemId,
                providerExecuted: isHosted,
                codeInterpreter: nil,
                applyPatch: nil
            )
            if isHosted {
                continuation.yield(.toolInputStart(
                    id: itemId,
                    toolName: toolName,
                    providerMetadata: nil,
                    providerExecuted: true,
                    dynamic: nil,
                    title: nil
                ))
            }
        case "tool_search_output":
            break
        case "message":
            guard let id = item["id"]?.stringValue else { return }
            ongoingAnnotations.removeAll(keepingCapacity: true)
            activeMessagePhase = item["phase"]?.stringValue
            var metadataItems: [String: JSONValue] = ["itemId": .string(id)]
            if let phase = activeMessagePhase {
                metadataItems["phase"] = .string(phase)
            }
            let metadata = openAIProviderMetadata(metadataItems)
            continuation.yield(.textStart(id: id, providerMetadata: metadata))
        case "reasoning":
            guard let id = item["id"]?.stringValue else { return }
            let encrypted = item["encrypted_content"]?.stringValue
            activeReasoning[id] = ReasoningState(encryptedContent: encrypted, summaryParts: [0: .active])
            let metadata = openAIProviderMetadata([
                "itemId": .string(id),
                "reasoningEncryptedContent": encrypted.map(JSONValue.string) ?? .null
            ])
            continuation.yield(.reasoningStart(id: "\(id):0", providerMetadata: metadata))
        default:
            break
        }
    }

    private func handleOutputItemDone(
        _ chunk: [String: JSONValue],
        webSearchToolName: String,
        toolNameMapping: ToolNameMapping,
        functionTools: [LanguageModelV4FunctionTool],
        ongoingAnnotations: inout [JSONValue],
        activeMessagePhase: inout String?,
        approvalRequestIdToToolCallIdFromPrompt: [String: String],
        approvalRequestIdToDummyToolCallIdFromStream: inout [String: String],
        hostedToolSearchCallIds: inout [String],
        ongoingToolCalls: IndexMap<ToolCallState>,
        activeReasoning: inout [String: ReasoningState],
        isShellProviderExecuted: Bool,
        hasFunctionCall: inout Bool,
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) async throws {
        guard let outputIndex = chunk["output_index"]?.numberValue,
              let item = chunk["item"]?.objectValue,
              let type = item["type"]?.stringValue else {
            return
        }

        switch type {
        case "function_call":
            guard let callId = item["call_id"]?.stringValue,
                  let name = item["name"]?.stringValue,
                  let arguments = item["arguments"]?.stringValue else { return }
            hasFunctionCall = true
            let state = ongoingToolCalls[outputIndex]
            ongoingToolCalls[outputIndex] = nil
            let suppressed = state?.suppressInputStreaming ?? OpenAIParallelCalls.isWrapper(name, tools: functionTools)
            var metadata: [String: JSONValue] = ["itemId": item["id"]!]
            let asyncValue = item["async"].flatMap { $0 == .null ? nil : $0 } ?? state?.asyncValue.flatMap { $0 == .null ? nil : $0 }
            if let asyncValue { metadata["async"] = asyncValue }
            if let namespace = item["namespace"], namespace != .null { metadata["namespace"] = namespace }
            let call = LanguageModelV4ToolCall(toolCallId: callId, toolName: name, input: arguments, providerMetadata: openAIProviderMetadata(metadata))
            if suppressed, let expanded = try await OpenAIParallelCalls.expand(call, itemId: item["id"]!.stringValue!, tools: functionTools, namespace: providerOptionsName) {
                for child in expanded {
                    continuation.yield(.toolInputStart(id: child.toolCallId, toolName: child.toolName, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil))
                    continuation.yield(.toolInputDelta(id: child.toolCallId, delta: child.input, providerMetadata: nil))
                    continuation.yield(.toolInputEnd(id: child.toolCallId, providerMetadata: nil))
                    continuation.yield(.toolCall(child))
                }
            } else {
                if suppressed {
                    continuation.yield(.toolInputStart(id: callId, toolName: name, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil))
                    let deltas = state?.bufferedInputDeltas ?? []
                    if !deltas.isEmpty {
                        for delta in deltas { continuation.yield(.toolInputDelta(id: callId, delta: delta, providerMetadata: nil)) }
                    } else if !arguments.isEmpty { continuation.yield(.toolInputDelta(id: callId, delta: arguments, providerMetadata: nil)) }
                }
                let endMetadata = item["namespace"].flatMap { $0 == .null ? nil : openAIProviderMetadata(["namespace": $0]) }
                continuation.yield(.toolInputEnd(id: callId, providerMetadata: endMetadata))
                continuation.yield(.toolCall(call))
            }
        case "custom_tool_call":
            guard let callId = item["call_id"]?.stringValue,
                  let providerToolName = item["name"]?.stringValue,
                  let rawInput = item["input"]?.stringValue else { return }
            hasFunctionCall = true
            let ongoing = ongoingToolCalls[outputIndex]
            ongoingToolCalls[outputIndex] = nil
            continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
            var values: [String: JSONValue] = ["itemId": item["id"] ?? .null]
            let asyncValue = item["async"].flatMap { $0 == .null ? nil : $0 } ?? ongoing?.asyncValue.flatMap { $0 == .null ? nil : $0 }
            if let asyncValue { values["async"] = asyncValue }
            let metadata = openAIProviderMetadata(values)
            let toolName = toolNameMapping.toCustomToolName(providerToolName)
            let input = try openAIJSONStringify(.string(rawInput))
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: callId,
                toolName: toolName,
                input: input,
                providerExecuted: nil,
                providerMetadata: metadata
            )))
        case "web_search_call":
            guard let callId = item["id"]?.stringValue,
                  let mappedOutput = mapWebSearchOutput(item["action"]) else { return }
            ongoingToolCalls[outputIndex] = nil
            continuation.yield(.toolResult(LanguageModelV4ToolResult(
                toolCallId: callId,
                toolName: webSearchToolName,
                result: mappedOutput,
                isError: nil,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "mcp_call":
            guard let itemId = item["id"]?.stringValue,
                  let name = item["name"]?.stringValue,
                  let arguments = item["arguments"]?.stringValue,
                  let serverLabel = item["server_label"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil

            let approvalRequestId = item["approval_request_id"]?.stringValue
            let aliasedToolCallId: String
            if let approvalRequestId {
                aliasedToolCallId = approvalRequestIdToDummyToolCallIdFromStream[approvalRequestId]
                    ?? approvalRequestIdToToolCallIdFromPrompt[approvalRequestId]
                    ?? itemId
            } else {
                aliasedToolCallId = itemId
            }

            let toolName = "mcp.\(name)"
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: aliasedToolCallId,
                toolName: toolName,
                input: arguments,
                providerExecuted: true,
                dynamic: true,
                providerMetadata: nil
            )))

            var resultPayload: [String: JSONValue] = [
                "type": .string("call"),
                "serverLabel": .string(serverLabel),
                "name": .string(name),
                "arguments": .string(arguments)
            ]
            if let output = item["output"], output != .null {
                resultPayload["output"] = output
            }
            if let error = item["error"], error != .null {
                resultPayload["error"] = error
            }

            let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
            continuation.yield(.toolResult(LanguageModelV4ToolResult(
                toolCallId: aliasedToolCallId,
                toolName: toolName,
                result: .object(resultPayload),
                isError: nil,
                preliminary: nil,
                providerMetadata: metadata
            )))
        case "mcp_list_tools":
            // Skip list tools - we don't expose this to the UI or send it back
            ongoingToolCalls[outputIndex] = nil
        case "mcp_approval_request":
            guard let itemId = item["id"]?.stringValue,
                  let name = item["name"]?.stringValue,
                  let arguments = item["arguments"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil

            let approvalRequestId = item["approval_request_id"]?.stringValue ?? itemId
            let dummyToolCallId = config.generateId?() ?? generateID()
            approvalRequestIdToDummyToolCallIdFromStream[approvalRequestId] = dummyToolCallId

            let toolName = "mcp.\(name)"
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: dummyToolCallId,
                toolName: toolName,
                input: arguments,
                providerExecuted: true,
                dynamic: true,
                providerMetadata: nil
            )))
            continuation.yield(.toolApprovalRequest(LanguageModelV4ToolApprovalRequest(
                approvalId: approvalRequestId,
                toolCallId: dummyToolCallId,
                providerMetadata: nil
            )))
        case "computer_call":
            ongoingToolCalls[outputIndex] = nil
            if let callId = item["call_id"]?.stringValue {
                hasFunctionCall = true
                let input = try openAIJSONStringify(mapOpenAIComputerCallInput(item))
                continuation.yield(.toolInputDelta(id: callId, delta: input, providerMetadata: nil))
                continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
                continuation.yield(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: callId, toolName: toolNameMapping.toCustomToolName("computer"), input: input,
                    providerMetadata: openAIProviderMetadata(["itemId": item["id"]!])
                )))
                return
            }
            guard let callId = item["id"]?.stringValue else { return }
            continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
            let toolName = toolNameMapping.toCustomToolName("computer_use")
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: callId,
                toolName: toolName,
                input: "",
                providerExecuted: true,
                providerMetadata: nil
            )))
            let status = item["status"]?.stringValue ?? "completed"
            let resultValue: JSONValue = .object([
                "type": .string("computer_use_tool_result"),
                "status": .string(status)
            ])
            continuation.yield(.toolResult(LanguageModelV4ToolResult(
                toolCallId: callId,
                toolName: toolName,
                result: resultValue,
                isError: nil,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "file_search_call":
            guard let callId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil
            let queries = item["queries"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            let resultsArray = item["results"]?.arrayValue?.compactMap { entry -> JSONValue? in
                guard let entryObject = entry.objectValue,
                      let attributes = entryObject["attributes"],
                      let fileId = entryObject["file_id"]?.stringValue,
                      let filename = entryObject["filename"]?.stringValue,
                      let score = entryObject["score"]?.numberValue,
                      let text = entryObject["text"]?.stringValue else {
                    return nil
                }
                return .object([
                    "attributes": attributes,
                    "fileId": .string(fileId),
                    "filename": .string(filename),
                    "score": .number(score),
                    "text": .string(text)
                ])
            }
            let resultValue: JSONValue = .object([
                "queries": .array(queries.map(JSONValue.string)),
                "results": resultsArray.map(JSONValue.array) ?? .null
            ])
            continuation.yield(.toolResult(LanguageModelV4ToolResult(
                toolCallId: callId,
                toolName: toolNameMapping.toCustomToolName("file_search"),
                result: resultValue,
                isError: nil,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "code_interpreter_call":
            guard let callId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil
            var resultPayload: [String: JSONValue] = [:]
            if let outputs = item["outputs"] {
                resultPayload["outputs"] = outputs
            }
            let resultValue: JSONValue = .object(resultPayload)
            continuation.yield(.toolResult(LanguageModelV4ToolResult(
                toolCallId: callId,
                toolName: toolNameMapping.toCustomToolName("code_interpreter"),
                result: resultValue,
                isError: nil,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "image_generation_call":
            guard let callId = item["id"]?.stringValue,
                  let resultString = item["result"]?.stringValue else { return }
            let resultValue: JSONValue = .object(["result": .string(resultString)])
            continuation.yield(.toolResult(LanguageModelV4ToolResult(
                toolCallId: callId,
                toolName: toolNameMapping.toCustomToolName("image_generation"),
                result: resultValue,
                isError: nil,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "tool_search_call":
            guard let itemId = item["id"]?.stringValue,
                  let state = ongoingToolCalls[outputIndex] else { return }
            let isHosted = (item["execution"]?.stringValue ?? "server") == "server"
            let toolCallId = isHosted ? state.toolCallId : (item["call_id"]?.stringValue ?? state.toolCallId)
            if isHosted {
                hostedToolSearchCallIds.append(toolCallId)
            } else {
                continuation.yield(.toolInputStart(
                    id: toolCallId,
                    toolName: state.toolName,
                    providerMetadata: nil,
                    providerExecuted: nil,
                    dynamic: nil,
                    title: nil
                ))
            }
            continuation.yield(.toolInputEnd(id: toolCallId, providerMetadata: nil))
            let inputValue: JSONValue = .object([
                "arguments": item["arguments"] ?? .null,
                "call_id": isHosted ? .null : .string(toolCallId)
            ])
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: toolCallId,
                toolName: state.toolName,
                input: try openAIJSONStringify(inputValue),
                providerExecuted: isHosted ? true : nil,
                providerMetadata: openAIProviderMetadata(["itemId": .string(itemId)])
            )))
            ongoingToolCalls[outputIndex] = nil
        case "tool_search_output":
            guard let itemId = item["id"]?.stringValue else { return }
            let toolCallId = item["call_id"]?.stringValue
                ?? (hostedToolSearchCallIds.isEmpty ? nil : hostedToolSearchCallIds.removeFirst())
                ?? itemId
            continuation.yield(.toolResult(LanguageModelV4ToolResult(
                toolCallId: toolCallId,
                toolName: toolNameMapping.toCustomToolName("tool_search"),
                result: .object([
                    "tools": item["tools"] ?? .array([])
                ]),
                isError: nil,
                preliminary: nil,
                providerMetadata: openAIProviderMetadata(["itemId": .string(itemId)])
            )))
        case "apply_patch_call":
            guard let callId = item["call_id"]?.stringValue,
                  let status = item["status"]?.stringValue,
                  let operation = item["operation"],
                  let operationType = operation.objectValue?["type"]?.stringValue,
                  let itemId = item["id"]?.stringValue else { return }

            if var state = ongoingToolCalls[outputIndex],
               var applyPatch = state.applyPatch,
               applyPatch.endEmitted == false,
               operationType != "delete_file" {
                if applyPatch.hasDiff == false,
                   let diff = operation.objectValue?["diff"]?.stringValue {
                    continuation.yield(.toolInputDelta(id: state.toolCallId, delta: escapeJSONString(diff), providerMetadata: nil))
                    applyPatch.hasDiff = true
                }

                continuation.yield(.toolInputDelta(id: state.toolCallId, delta: "\"}}", providerMetadata: nil))
                continuation.yield(.toolInputEnd(id: state.toolCallId, providerMetadata: nil))
                applyPatch.endEmitted = true
                state.applyPatch = applyPatch
                ongoingToolCalls[outputIndex] = state
            }

            if status == "completed" {
                let inputValue: JSONValue = .object([
                    "callId": .string(callId),
                    "operation": operation
                ])
                let inputString = try openAIJSONStringify(inputValue)
                let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
                continuation.yield(.toolCall(LanguageModelV4ToolCall(
                    toolCallId: callId,
                    toolName: toolNameMapping.toCustomToolName("apply_patch"),
                    input: inputString,
                    providerExecuted: nil,
                    providerMetadata: metadata
                )))
            }

            ongoingToolCalls[outputIndex] = nil
        case "shell_call":
            guard let callId = item["call_id"]?.stringValue,
                  let actionObject = item["action"]?.objectValue,
                  let commands = actionObject["commands"]?.arrayValue?.compactMap({ $0.stringValue }),
                  let itemId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil
            let inputValue: JSONValue = .object([
                "action": .object([
                    "commands": .array(commands.map(JSONValue.string))
                ])
            ])
            let inputString = try openAIJSONStringify(inputValue)
            let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: callId,
                toolName: toolNameMapping.toCustomToolName("shell"),
                input: inputString,
                providerExecuted: isShellProviderExecuted ? true : nil,
                providerMetadata: metadata
            )))
        case "shell_call_output":
            guard let callId = item["call_id"]?.stringValue,
                  let output = item["output"]?.arrayValue else { return }
            ongoingToolCalls[outputIndex] = nil

            let mappedOutput = output.compactMap { entry -> JSONValue? in
                guard let outputObject = entry.objectValue,
                      let stdout = outputObject["stdout"]?.stringValue,
                      let stderr = outputObject["stderr"]?.stringValue,
                      let outcomeObject = outputObject["outcome"]?.objectValue,
                      let outcomeType = outcomeObject["type"]?.stringValue else {
                    return nil
                }

                let outcome: JSONValue
                if outcomeType == "exit" {
                    guard let exitCode = outcomeObject["exit_code"]?.numberValue else {
                        return nil
                    }
                    outcome = .object([
                        "type": .string("exit"),
                        "exitCode": .number(exitCode)
                    ])
                } else if outcomeType == "timeout" {
                    outcome = .object([
                        "type": .string("timeout")
                    ])
                } else {
                    return nil
                }

                return .object([
                    "stdout": .string(stdout),
                    "stderr": .string(stderr),
                    "outcome": outcome
                ])
            }

            let resultValue: JSONValue = .object([
                "output": .array(mappedOutput)
            ])
            continuation.yield(.toolResult(LanguageModelV4ToolResult(
                toolCallId: callId,
                toolName: toolNameMapping.toCustomToolName("shell"),
                result: resultValue,
                isError: nil,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "local_shell_call":
            guard let callId = item["call_id"]?.stringValue,
                  let actionObject = item["action"]?.objectValue,
                  let actionType = actionObject["type"]?.stringValue,
                  let commands = actionObject["command"]?.arrayValue?.compactMap({ $0.stringValue }),
                  let itemId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil
            var actionPayload: [String: JSONValue] = [
                "type": .string(actionType),
                "command": .array(commands.map(JSONValue.string))
            ]
            if let timeoutMs = actionObject["timeout_ms"]?.numberValue {
                actionPayload["timeoutMs"] = .number(timeoutMs)
            }
            if let user = actionObject["user"]?.stringValue {
                actionPayload["user"] = .string(user)
            }
            if let workingDirectory = actionObject["working_directory"]?.stringValue {
                actionPayload["workingDirectory"] = .string(workingDirectory)
            }
            if let env = actionObject["env"]?.objectValue {
                let mappedEnv = env.compactMapValues { value in value.stringValue.map(JSONValue.string) }
                actionPayload["env"] = .object(mappedEnv)
            }
            let inputValue: JSONValue = .object(["action": .object(actionPayload)])
            let inputString = try openAIJSONStringify(inputValue)
            let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: callId,
                toolName: toolNameMapping.toCustomToolName("local_shell"),
                input: inputString,
                providerExecuted: nil,
                providerMetadata: metadata
            )))
        case "message":
            if let id = item["id"]?.stringValue {
                var metadataItems: [String: JSONValue] = ["itemId": .string(id)]
                let phase = item["phase"]?.stringValue ?? activeMessagePhase
                activeMessagePhase = nil
                if let phase {
                    metadataItems["phase"] = .string(phase)
                }
                if !ongoingAnnotations.isEmpty {
                    metadataItems["annotations"] = .array(ongoingAnnotations)
                }
                let metadata = openAIProviderMetadata(metadataItems)
                continuation.yield(.textEnd(id: id, providerMetadata: metadata))
            }
        case "reasoning":
            guard let id = item["id"]?.stringValue,
                  let state = activeReasoning[id] else { return }
            let finalEncryptedContent = item["encrypted_content"]?.stringValue
            let metadata = openAIProviderMetadata([
                "itemId": .string(id),
                "reasoningEncryptedContent": finalEncryptedContent.map(JSONValue.string) ?? .null
            ])
            for (summaryIndex, status) in state.summaryParts.ordered {
                if status == .concluded { continue }
                continuation.yield(.reasoningEnd(id: "\(id):\(jsNumberString(summaryIndex))", providerMetadata: metadata))
            }
            activeReasoning[id] = nil
        case "compaction":
            guard let itemId = item["id"]?.stringValue else { return }
            var metadataItems: [String: JSONValue] = [
                "type": .string("compaction"),
                "itemId": .string(itemId)
            ]
            if let encryptedContent = item["encrypted_content"]?.stringValue {
                metadataItems["encryptedContent"] = .string(encryptedContent)
            }
            continuation.yield(.custom(LanguageModelV4CustomContent(
                kind: "openai.compaction",
                providerMetadata: openAIProviderMetadata(metadataItems)
            )))
        default:
            break
        }
    }

    private func handleFunctionCallArgumentsDelta(
        _ chunk: [String: JSONValue],
        ongoingToolCalls: IndexMap<ToolCallState>,
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let outputIndex = chunk["output_index"]?.numberValue,
              let delta = chunk["delta"]?.stringValue,
              var state = ongoingToolCalls[outputIndex] else { return }
        if state.suppressInputStreaming {
            state.bufferedInputDeltas.append(delta)
            ongoingToolCalls[outputIndex] = state
        } else { continuation.yield(.toolInputDelta(id: state.toolCallId, delta: delta, providerMetadata: nil)) }
    }

    private func handleApplyPatchCallOperationDiffDelta(
        _ chunk: [String: JSONValue],
        ongoingToolCalls: IndexMap<ToolCallState>,
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let outputIndex = chunk["output_index"]?.numberValue,
              let delta = chunk["delta"]?.stringValue,
              var state = ongoingToolCalls[outputIndex],
              var applyPatch = state.applyPatch else {
            return
        }

        continuation.yield(.toolInputDelta(id: state.toolCallId, delta: escapeJSONString(delta), providerMetadata: nil))
        applyPatch.hasDiff = true
        state.applyPatch = applyPatch
        ongoingToolCalls[outputIndex] = state
    }

    private func handleApplyPatchCallOperationDiffDone(
        _ chunk: [String: JSONValue],
        ongoingToolCalls: IndexMap<ToolCallState>,
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let outputIndex = chunk["output_index"]?.numberValue,
              let diff = chunk["diff"]?.stringValue,
              var state = ongoingToolCalls[outputIndex],
              var applyPatch = state.applyPatch,
              applyPatch.endEmitted == false else {
            return
        }

        if applyPatch.hasDiff == false {
            continuation.yield(.toolInputDelta(id: state.toolCallId, delta: escapeJSONString(diff), providerMetadata: nil))
            applyPatch.hasDiff = true
        }

        continuation.yield(.toolInputDelta(id: state.toolCallId, delta: "\"}}", providerMetadata: nil))
        continuation.yield(.toolInputEnd(id: state.toolCallId, providerMetadata: nil))
        applyPatch.endEmitted = true
        state.applyPatch = applyPatch
        ongoingToolCalls[outputIndex] = state
    }

    private func handleImageGenerationPartial(
        _ chunk: [String: JSONValue],
        toolNameMapping: ToolNameMapping,
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let toolCallId = chunk["item_id"]?.stringValue,
              let partial = chunk["partial_image_b64"]?.stringValue else {
            return
        }
        let resultValue: JSONValue = .object(["result": .string(partial)])
        continuation.yield(.toolResult(LanguageModelV4ToolResult(
            toolCallId: toolCallId,
            toolName: toolNameMapping.toCustomToolName("image_generation"),
            result: resultValue,
            isError: nil,
            preliminary: true,
            providerMetadata: nil
        )))
    }

    private func handleCodeInterpreterDelta(
        _ chunk: [String: JSONValue],
        ongoingToolCalls: IndexMap<ToolCallState>,
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let outputIndex = chunk["output_index"]?.numberValue,
              let delta = chunk["delta"]?.stringValue,
              let state = ongoingToolCalls[outputIndex],
              state.codeInterpreter != nil else {
            return
        }

        let escaped = escapeJSONString(delta)
        continuation.yield(.toolInputDelta(id: state.toolCallId, delta: escaped, providerMetadata: nil))
    }

    private func handleCodeInterpreterDone(
        _ chunk: [String: JSONValue],
        ongoingToolCalls: IndexMap<ToolCallState>,
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let outputIndex = chunk["output_index"]?.numberValue,
              let state = ongoingToolCalls[outputIndex],
              let interpreter = state.codeInterpreter,
              let code = chunk["code"]?.stringValue else {
            return
        }

        continuation.yield(.toolInputDelta(id: state.toolCallId, delta: "\"}", providerMetadata: nil))
        continuation.yield(.toolInputEnd(id: state.toolCallId, providerMetadata: nil))

        let inputValue: JSONValue = .object([
            "code": .string(code),
            "containerId": .string(interpreter.containerId)
        ])
        do {
            let inputString = try openAIJSONStringify(inputValue)
            continuation.yield(.toolCall(LanguageModelV4ToolCall(
                toolCallId: state.toolCallId,
                toolName: state.toolName,
                input: inputString,
                providerExecuted: true,
                providerMetadata: nil
            )))
        } catch {
            continuation.yield(.error(error: .error(error)))
        }

        ongoingToolCalls[outputIndex] = nil
    }

    private func handleReasoningSummaryPartAdded(
        _ chunk: [String: JSONValue],
        activeReasoning: inout [String: ReasoningState],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let itemId = chunk["item_id"]?.stringValue,
              let state = activeReasoning[itemId],
              let summaryIndex = chunk["summary_index"]?.numberValue,
              summaryIndex >= 0 else {
            return
        }

        // The first reasoning start is emitted by `response.output_item.added`.
        guard summaryIndex > 0 else { return }

        if state.summaryParts[summaryIndex] == nil {
            // Since there is a new active summary part, conclude all can-conclude parts.
            var concludedIndices: [Double] = []
            concludedIndices.reserveCapacity(state.summaryParts.count)
            for (index, status) in state.summaryParts.ordered where status == .canConclude {
                concludedIndices.append(index)
            }

            for index in concludedIndices {
                let endMetadata = openAIProviderMetadata(["itemId": .string(itemId)])
                continuation.yield(.reasoningEnd(id: "\(itemId):\(jsNumberString(index))", providerMetadata: endMetadata))
                state.summaryParts[index] = .concluded
            }

            state.summaryParts[summaryIndex] = .active

            let startMetadata = openAIProviderMetadata([
                "itemId": .string(itemId),
                "reasoningEncryptedContent": state.encryptedContent.map(JSONValue.string) ?? .null
            ])
            continuation.yield(.reasoningStart(id: "\(itemId):\(jsNumberString(summaryIndex))", providerMetadata: startMetadata))
        }
    }

    private func handleReasoningSummaryTextDelta(
        _ chunk: [String: JSONValue],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let itemId = chunk["item_id"]?.stringValue,
              let summaryIndex = chunk["summary_index"]?.numberValue,
              let delta = chunk["delta"]?.stringValue else {
            return
        }
        let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
        continuation.yield(.reasoningDelta(id: "\(itemId):\(jsNumberString(summaryIndex))", delta: delta, providerMetadata: metadata))
    }

    private func handleReasoningSummaryPartDone(
        _ chunk: [String: JSONValue],
        store: Bool,
        activeReasoning: inout [String: ReasoningState],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let itemId = chunk["item_id"]?.stringValue,
              let summaryIndex = chunk["summary_index"]?.numberValue,
              let state = activeReasoning[itemId],
              state.summaryParts[summaryIndex] != nil else {
            return
        }

        if store {
            let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
            continuation.yield(.reasoningEnd(id: "\(itemId):\(jsNumberString(summaryIndex))", providerMetadata: metadata))
            state.summaryParts[summaryIndex] = .concluded
        } else {
            state.summaryParts[summaryIndex] = .canConclude
        }

    }

    private func handleTextDelta(
        _ chunk: [String: JSONValue],
        logprobsRequested: Bool,
        collectedLogprobs: inout [JSONValue],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let itemId = chunk["item_id"]?.stringValue,
              let delta = chunk["delta"]?.stringValue else {
            return
        }
        continuation.yield(.textDelta(id: itemId, delta: delta, providerMetadata: nil))
        if logprobsRequested, let logprobValue = chunk["logprobs"], logprobValue != .null {
            collectedLogprobs.append(logprobValue)
        }
    }

    private func handleAnnotationAdded(
        _ chunk: [String: JSONValue],
        ongoingAnnotations: inout [JSONValue],
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let annotationValue = chunk["annotation"],
              let filteredAnnotationValue = filterOpenAIResponsesAnnotation(annotationValue),
              let annotation = filteredAnnotationValue.objectValue,
              let type = annotation["type"]?.stringValue else {
            return
        }
        ongoingAnnotations.append(filteredAnnotationValue)

        switch type {
        case "url_citation":
            guard let url = annotation["url"]?.stringValue else { return }
            let title = annotation["title"]?.stringValue
            continuation.yield(.source(.url(
                id: nextSourceId(),
                url: url,
                title: title,
                providerMetadata: nil
            )))

        case "file_citation":
            guard let fileId = annotation["file_id"]?.stringValue,
                  let filename = annotation["filename"]?.stringValue else { return }
            let title = filename

            var metadataItems: [String: JSONValue] = [
                "type": .string("file_citation"),
                "fileId": .string(fileId)
            ]
            if let index = annotation["index"], index != .null {
                metadataItems["index"] = index
            }

            continuation.yield(.source(.document(
                id: nextSourceId(),
                mediaType: "text/plain",
                title: title,
                filename: filename,
                providerMetadata: openAIProviderMetadata(metadataItems)
            )))

        case "container_file_citation":
            guard let fileId = annotation["file_id"]?.stringValue,
                  let containerId = annotation["container_id"]?.stringValue,
                  let filename = annotation["filename"]?.stringValue else { return }
            let title = filename

            continuation.yield(.source(.document(
                id: nextSourceId(),
                mediaType: "text/plain",
                title: title,
                filename: filename,
                providerMetadata: openAIProviderMetadata([
                    "type": .string("container_file_citation"),
                    "fileId": .string(fileId),
                    "containerId": .string(containerId)
                ])
            )))

        case "file_path":
            guard let fileId = annotation["file_id"]?.stringValue else { return }

            var metadataItems: [String: JSONValue] = [
                "type": .string("file_path"),
                "fileId": .string(fileId)
            ]
            if let index = annotation["index"], index != .null {
                metadataItems["index"] = index
            }

            continuation.yield(.source(.document(
                id: nextSourceId(),
                mediaType: "application/octet-stream",
                title: fileId,
                filename: fileId,
                providerMetadata: openAIProviderMetadata(metadataItems)
            )))

        default:
            break
        }
    }

    private func handleResponseFailed(
        _ chunk: [String: JSONValue],
        parsedUsage: OpenAIResponsesResponse.Usage?,
        hasFunctionCall: Bool,
        finishReason: inout LanguageModelV4FinishReason,
        usage: inout LanguageModelV4Usage,
        responseId: inout String?,
        serviceTier: inout String?,
        encounteredStreamError: inout Bool,
        continuation: AsyncThrowingStream<LanguageModelV4StreamPart, Error>.Continuation
    ) {
        guard let responseObject = chunk["response"]?.objectValue else {
            return
        }

        let incompleteReason = responseObject["incomplete_details"]?.objectValue?["reason"]?.stringValue
        if let incompleteReason {
            finishReason = LanguageModelV4FinishReason(
                unified: mapOpenAIResponsesFinishReason(
                    finishReason: incompleteReason,
                    hasFunctionCall: hasFunctionCall
                ),
                raw: incompleteReason
            )
        } else {
            finishReason = .init(unified: .error, raw: "error")
        }

        usage = convertOpenAIResponsesUsage(parsedUsage)

        if let tier = responseObject["service_tier"]?.stringValue {
            serviceTier = tier
        }

        if responseId == nil, let id = responseObject["id"]?.stringValue {
            responseId = id
        }

        guard !encounteredStreamError,
              let errorPayload = makeResponseFailedStreamErrorPayload(from: chunk) else {
            return
        }

        encounteredStreamError = true
        continuation.yield(.error(error: createOpenAIProviderStreamError(errorPayload).map(LanguageModelV4StreamError.providerStreamError) ?? .value(errorPayload)))
    }

    private func makeResponseFailedStreamErrorPayload(from chunk: [String: JSONValue]) -> JSONValue? {
        guard let responseObject = chunk["response"]?.objectValue,
              let errorValue = responseObject["error"],
              errorValue != .null else {
            return nil
        }

        var failure: [String: JSONValue] = ["error": errorValue]
        failure["incomplete_details"] = responseObject["incomplete_details"]
        failure["service_tier"] = responseObject["service_tier"]
        var payload: [String: JSONValue] = [
            "type": .string("response.failed"),
            "response": .object(failure)
        ]
        if let sequenceNumber = chunk["sequence_number"] {
            payload["sequence_number"] = sequenceNumber
        }

        return .object(payload)
    }

    private func makeResponseMetadata(from object: [String: JSONValue]) -> ResponseMetadata? {
        guard let response = object["response"]?.objectValue,
              let id = response["id"]?.stringValue else {
            return nil
        }
        let timestamp = response["created_at"]?.numberValue.map { Date(timeIntervalSince1970: $0) }
        let modelId = response["model"]?.stringValue
        let serviceTier = response["service_tier"]?.stringValue
        return ResponseMetadata(id: id, modelId: modelId, timestamp: timestamp, serviceTier: serviceTier)
    }

    private func escapeJSONString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(JSONValue.string(value)),
           var string = String(data: data, encoding: .utf8) {
            string.removeFirst()
            string.removeLast()
            return string
        }
        return value
    }
}

private extension ParseJSONResult where Output == OpenAIResponsesChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }

}

private func convertOpenAIResponsesUsage(_ usage: OpenAIResponsesResponse.Usage?) -> LanguageModelV4Usage {
    // Port of `packages/openai/src/responses/convert-openai-responses-usage.ts`
    guard let usage else {
        return LanguageModelV4Usage()
    }

    let inputTokens = usage.inputTokens
    let outputTokens = usage.outputTokens
    let cachedTokens = usage.inputTokensDetails?.cachedTokens ?? 0
    let cacheWriteTokens = usage.inputTokensDetails?.cacheWriteTokens
    let reasoningTokens = usage.outputTokensDetails?.reasoningTokens ?? 0

    return LanguageModelV4Usage(
        inputTokens: .init(
            total: inputTokens,
            noCache: inputTokens - cachedTokens - (cacheWriteTokens ?? 0),
            cacheRead: cachedTokens,
            cacheWrite: cacheWriteTokens
        ),
        outputTokens: .init(
            total: outputTokens,
            text: outputTokens - reasoningTokens,
            reasoning: reasoningTokens
        ),
        raw: usage.rawValue
    )
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let array) = self {
            return array
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

}
