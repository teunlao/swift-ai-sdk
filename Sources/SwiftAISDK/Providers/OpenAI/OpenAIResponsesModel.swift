import Foundation
import AISDKProvider
import AISDKProviderUtils

private let openAIHTTPSURLRegex: NSRegularExpression = {
    // Safe to use try! for a static, well-formed pattern
    try! NSRegularExpression(pattern: "^https?://.*$", options: [.caseInsensitive])
}()

public final class OpenAIResponsesLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"
    private let modelIdentifier: OpenAIResponsesModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAIResponsesModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
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

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)

        let url = config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses"))
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
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
                responseBody: nil,
                isRetryable: false,
                data: ["code": errorPayload.code]
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

        let mapped = try mapResponseOutput(
            value.output,
            webSearchToolName: prepared.webSearchToolName,
            logprobsRequested: logprobsRequested
        )

        let providerMetadata = makeProviderMetadata(
            responseId: value.id,
            logprobs: mapped.logprobs,
            serviceTier: value.serviceTier
        )

        let usage = LanguageModelV3Usage(
            inputTokens: value.usage.inputTokens,
            outputTokens: value.usage.outputTokens,
            totalTokens: value.usage.inputTokens + value.usage.outputTokens,
            reasoningTokens: value.usage.outputTokensDetails?.reasoningTokens,
            cachedInputTokens: value.usage.inputTokensDetails?.cachedTokens
        )

        let outputWarnings = value.warnings?.map { $0.toWarning() } ?? []
        let finishReason = mapOpenAIResponsesFinishReason(
            finishReason: value.incompleteDetails?.reason,
            hasFunctionCall: mapped.hasFunctionCall
        )

        return LanguageModelV3GenerateResult(
            content: mapped.content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3ResponseInfo(
                id: value.id,
                timestamp: value.createdAt.map { Date(timeIntervalSince1970: $0) },
                modelId: value.model,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings + outputWarnings
        )
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options)

        let url = config.url(.init(modelId: modelIdentifier.rawValue, path: "/responses"))
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
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

        let chunkStream = response.value
        let webSearchToolName = prepared.webSearchToolName ?? "web_search"
        let logprobsRequested: Bool = {
            guard let logprobs = prepared.openAIOptions?.logprobs else { return false }
            switch logprobs {
            case .bool(let flag):
                return flag
            case .number:
                return true
            }
        }()

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var logprobs: [JSONValue] = []
                var responseId: String?
                var serviceTier: String?
                var hasFunctionCall = false

                var ongoingToolCalls: [Int: ToolCallState] = [:]
                var activeReasoning: [String: ReasoningState] = [:]

                do {
                    for try await result in chunkStream {
                        switch result {
                        case .success(let chunk, _):
                            if options.includeRawChunks == true {
                                continuation.yield(.raw(rawValue: chunk.rawValue))
                            }

                            guard let type = chunk.type,
                                  let chunkObject = chunk.rawValue.objectValue else {
                                continue
                            }

                            switch type {
                            case "response.output_item.added":
                                try handleOutputItemAdded(
                                    chunkObject,
                                    webSearchToolName: webSearchToolName,
                                    ongoingToolCalls: &ongoingToolCalls,
                                    activeReasoning: &activeReasoning,
                                    continuation: continuation
                                )
                            case "response.output_item.done":
                                try handleOutputItemDone(
                                    chunkObject,
                                    webSearchToolName: webSearchToolName,
                                    ongoingToolCalls: &ongoingToolCalls,
                                    activeReasoning: &activeReasoning,
                                    hasFunctionCall: &hasFunctionCall,
                                    continuation: continuation
                                )
                            case "response.function_call_arguments.delta":
                                handleFunctionCallArgumentsDelta(
                                    chunkObject,
                                    ongoingToolCalls: &ongoingToolCalls,
                                    continuation: continuation
                                )
                            case "response.image_generation_call.partial_image":
                                handleImageGenerationPartial(
                                    chunkObject,
                                    continuation: continuation
                                )
                            case "response.code_interpreter_call_code.delta":
                                handleCodeInterpreterDelta(
                                    chunkObject,
                                    ongoingToolCalls: &ongoingToolCalls,
                                    continuation: continuation
                                )
                            case "response.code_interpreter_call_code.done":
                                handleCodeInterpreterDone(
                                    chunkObject,
                                    ongoingToolCalls: &ongoingToolCalls,
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
                                    finishReason = mapOpenAIResponsesFinishReason(
                                        finishReason: responseObject["incomplete_details"]?.objectValue?["reason"]?.stringValue,
                                        hasFunctionCall: hasFunctionCall
                                    )

                                    if let usageValue = responseObject["usage"], let usageObject = usageValue.objectValue {
                                        usage = makeUsage(from: usageObject)
                                    }

                                    if let tier = responseObject["service_tier"]?.stringValue {
                                        serviceTier = tier
                                    }

                                    if responseId == nil, let id = responseObject["id"]?.stringValue {
                                        responseId = id
                                    }
                                }
                            case "error":
                                finishReason = .error
                                continuation.yield(.error(error: chunk.rawValue))
                            default:
                                break
                            }
                        case .failure(let error, _):
                            finishReason = .error
                            continuation.yield(.error(error: .string(String(describing: error))))
                        }
                    }

                    let metadata = makeProviderMetadata(
                        responseId: responseId,
                        logprobs: logprobs,
                        serviceTier: serviceTier
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
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: requestBody),
            response: LanguageModelV3StreamResponseInfo(headers: response.responseHeaders)
        )
    }

    private struct PreparedRequest {
        let body: OpenAIResponsesRequestBody
        let warnings: [LanguageModelV3CallWarning]
        let webSearchToolName: String?
        let store: Bool
        let openAIOptions: OpenAIResponsesProviderOptions?
    }

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [LanguageModelV3CallWarning] = []

        func addUnsupportedSetting(_ name: String, details: String? = nil) {
            warnings.append(.unsupportedSetting(setting: name, details: details))
        }

        if options.topK != nil { addUnsupportedSetting("topK") }
        if options.seed != nil { addUnsupportedSetting("seed") }
        if options.presencePenalty != nil { addUnsupportedSetting("presencePenalty") }
        if options.frequencyPenalty != nil { addUnsupportedSetting("frequencyPenalty") }
        if options.stopSequences != nil { addUnsupportedSetting("stopSequences") }

        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAIResponsesProviderOptionsSchema
        )

        let store = openAIOptions?.store ?? true
        let modelConfig = getOpenAIResponsesModelConfig(for: modelIdentifier)
        let hasLocalShellTool = containsLocalShellTool(options.tools)

        let (input, inputWarnings) = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: options.prompt,
            systemMessageMode: modelConfig.systemMessageMode,
            fileIdPrefixes: config.fileIdPrefixes,
            store: store,
            hasLocalShellTool: hasLocalShellTool
        )
        warnings.append(contentsOf: inputWarnings)

        let strictJsonSchema = openAIOptions?.strictJsonSchema ?? false
        let webSearchToolName = findWebSearchToolName(options.tools)

        var includeSet: Set<OpenAIResponsesIncludeValue> = []
        if let includes = openAIOptions?.include {
            includeSet.formUnion(includes)
        }

        func addInclude(_ value: OpenAIResponsesIncludeValue) {
            includeSet.insert(value)
        }

        var topLogprobs: Int?
        if let logprobs = openAIOptions?.logprobs {
            switch logprobs {
            case .bool(let flag) where flag:
                topLogprobs = TOP_LOGPROBS_MAX
            case .bool:
                break
            case .number(let value):
                topLogprobs = value
            }
        }
        if topLogprobs != nil {
            addInclude(.messageOutputTextLogprobs)
        }

        if webSearchToolName != nil {
            addInclude(.webSearchCallActionSources)
        }
        if containsProviderTool(options.tools, id: "openai.code_interpreter") {
            addInclude(.codeInterpreterCallOutputs)
        }

        if store == false && modelConfig.isReasoningModel {
            addInclude(.reasoningEncryptedContent)
        }

        let preparedTools = try await prepareOpenAIResponsesTools(
            tools: options.tools,
            toolChoice: options.toolChoice,
            strictJsonSchema: strictJsonSchema
        )
        warnings.append(contentsOf: preparedTools.warnings)

        let textOptions = makeTextOptions(
            responseFormat: options.responseFormat,
            textVerbosity: openAIOptions?.textVerbosity,
            strictJsonSchema: strictJsonSchema
        )

        var reasoningValue: JSONValue?
        if modelConfig.isReasoningModel,
           openAIOptions?.reasoningEffort != nil || openAIOptions?.reasoningSummary != nil {
            var payload: [String: JSONValue] = [:]
            if let effort = openAIOptions?.reasoningEffort {
                payload["effort"] = .string(effort)
            }
            if let summary = openAIOptions?.reasoningSummary {
                payload["summary"] = .string(summary)
            }
            reasoningValue = .object(payload)
        } else {
            if openAIOptions?.reasoningEffort != nil {
                addUnsupportedSetting("reasoningEffort", details: "reasoningEffort is not supported for non-reasoning models")
            }
            if openAIOptions?.reasoningSummary != nil {
                addUnsupportedSetting("reasoningSummary", details: "reasoningSummary is not supported for non-reasoning models")
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
            store: store,
            user: openAIOptions?.user,
            instructions: openAIOptions?.instructions,
            serviceTier: openAIOptions?.serviceTier,
            include: includeSet.isEmpty ? nil : includeSet.map { $0.rawValue },
            promptCacheKey: openAIOptions?.promptCacheKey,
            safetyIdentifier: openAIOptions?.safetyIdentifier,
            topLogprobs: topLogprobs,
            reasoning: reasoningValue,
            truncation: modelConfig.requiredAutoTruncation ? "auto" : nil,
            tools: preparedTools.tools,
            toolChoice: preparedTools.toolChoice
        )

        if modelConfig.isReasoningModel {
            if body.temperature != nil {
                addUnsupportedSetting("temperature", details: "temperature is not supported for reasoning models")
                body.temperature = nil
            }
            if body.topP != nil {
                addUnsupportedSetting("topP", details: "topP is not supported for reasoning models")
                body.topP = nil
            }
        }

        if let serviceTier = body.serviceTier {
            switch serviceTier {
            case "flex" where !modelConfig.supportsFlexProcessing:
                addUnsupportedSetting("serviceTier", details: "flex processing is not available for this model")
                body.serviceTier = nil
            case "priority" where !modelConfig.supportsPriorityProcessing:
                addUnsupportedSetting("serviceTier", details: "priority processing is not available for this model")
                body.serviceTier = nil
            default:
                break
            }
        }

        return PreparedRequest(
            body: body,
            warnings: warnings,
            webSearchToolName: webSearchToolName,
            store: store,
            openAIOptions: openAIOptions
        )
    }

    private func makeTextOptions(
        responseFormat: LanguageModelV3ResponseFormat?,
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
                    if let name {
                        formatPayload["name"] = .string(name)
                    }
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

    private func containsLocalShellTool(_ tools: [LanguageModelV3Tool]?) -> Bool {
        guard let tools else { return false }
        return tools.contains { tool in
            if case .providerDefined(let providerTool) = tool {
                return providerTool.id == "openai.local_shell"
            }
            return false
        }
    }

    private func containsProviderTool(_ tools: [LanguageModelV3Tool]?, id: String) -> Bool {
        guard let tools else { return false }
        return tools.contains { tool in
            if case .providerDefined(let providerTool) = tool {
                return providerTool.id == id
            }
            return false
        }
    }

    private func findWebSearchToolName(_ tools: [LanguageModelV3Tool]?) -> String? {
        guard let tools else { return nil }
        for tool in tools {
            if case .providerDefined(let providerTool) = tool,
               providerTool.id == "openai.web_search" || providerTool.id == "openai.web_search_preview" {
                return providerTool.name
            }
        }
        return nil
    }

    private struct MappedResponse {
        let content: [LanguageModelV3Content]
        let logprobs: [JSONValue]
        let hasFunctionCall: Bool
    }

    private func mapResponseOutput(
        _ output: [JSONValue],
        webSearchToolName: String?,
        logprobsRequested: Bool
    ) throws -> MappedResponse {
        var content: [LanguageModelV3Content] = []
        var logprobs: [JSONValue] = []
        var hasFunctionCall = false

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
                    content.append(.reasoning(LanguageModelV3Reasoning(text: text, providerMetadata: metadata)))
                }

            case "message":
                guard let itemId = object["id"]?.stringValue,
                      let parts = object["content"]?.arrayValue else {
                    continue
                }

                let metadata = openAIProviderMetadata(["itemId": .string(itemId)])

                for part in parts {
                    guard let partObject = part.objectValue,
                          partObject["type"]?.stringValue == "output_text",
                          let text = partObject["text"]?.stringValue else {
                        continue
                    }

                    if logprobsRequested, let logprobValue = partObject["logprobs"], logprobValue != .null {
                        logprobs.append(logprobValue)
                    }

                    content.append(.text(LanguageModelV3Text(text: text, providerMetadata: metadata)))

                    if let annotations = partObject["annotations"]?.arrayValue {
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
                                let title = annotationObject["quote"]?.stringValue
                                    ?? annotationObject["filename"]?.stringValue
                                    ?? "Document"
                                let filename = annotationObject["filename"]?.stringValue
                                    ?? annotationObject["file_id"]?.stringValue
                                content.append(.source(.document(
                                    id: nextSourceId(),
                                    mediaType: "text/plain",
                                    title: title,
                                    filename: filename,
                                    providerMetadata: nil
                                )))
                            default:
                                break
                            }
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

                let providerMetadata = openAIProviderMetadata([
                    "itemId": object["id"]?.stringValue.map(JSONValue.string) ?? .null
                ])

                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    input: input,
                    providerExecuted: nil,
                    providerMetadata: providerMetadata
                )))

            case "web_search_call":
                guard let toolCallId = object["id"]?.stringValue else { continue }
                let action = object["action"] ?? .null
                let status = object["status"]?.stringValue ?? "unknown"

                let toolName = webSearchToolName ?? "web_search"
                let inputObject: JSONValue = .object(["action": action])
                let inputString = try jsonString(from: inputObject)

                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    input: inputString,
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                let resultValue: JSONValue = .object(["status": .string(status)])
                content.append(.toolResult(LanguageModelV3ToolResult(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    result: resultValue,
                    isError: nil,
                    providerExecuted: true,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "computer_call":
                guard let toolCallId = object["id"]?.stringValue else { continue }
                let status = object["status"]?.stringValue ?? "completed"

                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: "computer_use",
                    input: "",
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                let resultValue: JSONValue = .object([
                    "type": .string("computer_use_tool_result"),
                    "status": .string(status)
                ])
                content.append(.toolResult(LanguageModelV3ToolResult(
                    toolCallId: toolCallId,
                    toolName: "computer_use",
                    result: resultValue,
                    isError: nil,
                    providerExecuted: true,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "file_search_call":
                guard let toolCallId = object["id"]?.stringValue else { continue }

                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: "file_search",
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

                content.append(.toolResult(LanguageModelV3ToolResult(
                    toolCallId: toolCallId,
                    toolName: "file_search",
                    result: resultValue,
                    isError: nil,
                    providerExecuted: true,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "code_interpreter_call":
                guard let toolCallId = object["id"]?.stringValue,
                      let containerId = object["container_id"]?.stringValue else {
                    continue
                }
                let code = object["code"]?.stringValue ?? ""
                let outputs = object["outputs"] ?? .null

                let inputValue: JSONValue = .object([
                    "code": .string(code),
                    "containerId": .string(containerId)
                ])
                let inputString = try jsonString(from: inputValue)

                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: "code_interpreter",
                    input: inputString,
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                let resultValue: JSONValue = .object(["outputs": outputs])
                content.append(.toolResult(LanguageModelV3ToolResult(
                    toolCallId: toolCallId,
                    toolName: "code_interpreter",
                    result: resultValue,
                    isError: nil,
                    providerExecuted: true,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "image_generation_call":
                guard let toolCallId = object["id"]?.stringValue,
                      let resultString = object["result"]?.stringValue else {
                    continue
                }

                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: "image_generation",
                    input: "{}",
                    providerExecuted: true,
                    providerMetadata: nil
                )))

                let resultValue: JSONValue = .object(["result": .string(resultString)])
                content.append(.toolResult(LanguageModelV3ToolResult(
                    toolCallId: toolCallId,
                    toolName: "image_generation",
                    result: resultValue,
                    isError: nil,
                    providerExecuted: true,
                    preliminary: nil,
                    providerMetadata: nil
                )))

            case "local_shell_call":
                guard let toolCallId = object["call_id"]?.stringValue,
                      let action = object["action"],
                      let itemId = object["id"]?.stringValue else {
                    continue
                }

                let inputValue: JSONValue = .object(["action": action])
                let inputString = try jsonString(from: inputValue)
                let metadata = openAIProviderMetadata(["itemId": .string(itemId)])

                content.append(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: toolCallId,
                    toolName: "local_shell",
                    input: inputString,
                    providerExecuted: true,
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
        serviceTier: String?
    ) -> SharedV3ProviderMetadata? {
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
        return inner.isEmpty ? nil : ["openai": inner]
    }

    private func nextSourceId() -> String {
        config.generateId?() ?? generateID()
    }

    private func jsonString(from value: JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON value")
        }
        return string
    }

    private func makeUsage(from object: [String: JSONValue]) -> LanguageModelV3Usage {
        let inputTokens = object["input_tokens"]?.intValue
        let outputTokens = object["output_tokens"]?.intValue
        let totalTokens: Int?
        if let inputTokens, let outputTokens {
            totalTokens = inputTokens + outputTokens
        } else {
            totalTokens = nil
        }

        let reasoningTokens = object["output_tokens_details"]?.objectValue?["reasoning_tokens"]?.intValue
        let cachedTokens = object["input_tokens_details"]?.objectValue?["cached_tokens"]?.intValue

        return LanguageModelV3Usage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            reasoningTokens: reasoningTokens,
            cachedInputTokens: cachedTokens
        )
    }

    // MARK: - Streaming helpers

    private struct ToolCallState {
        let toolName: String
        let toolCallId: String
        let providerExecuted: Bool
        let codeInterpreter: CodeInterpreterState?
    }

    private struct CodeInterpreterState {
        let containerId: String
    }

    private struct ReasoningState {
        var encryptedContent: String?
        var summaryParts: [Int]
    }

    private struct ResponseMetadata {
        let id: String
        let modelId: String?
        let timestamp: Date?
        let serviceTier: String?
    }

    private func openAIProviderMetadata(_ items: [String: JSONValue]) -> SharedV3ProviderMetadata {
        var filtered: [String: JSONValue] = [:]
        for (key, value) in items {
            filtered[key] = value
        }
        return ["openai": filtered]
    }

    private func handleOutputItemAdded(
        _ chunk: [String: JSONValue],
        webSearchToolName: String,
        ongoingToolCalls: inout [Int: ToolCallState],
        activeReasoning: inout [String: ReasoningState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) throws {
        guard let outputIndex = chunk["output_index"]?.intValue,
              let item = chunk["item"]?.objectValue,
              let type = item["type"]?.stringValue else {
            return
        }

        switch type {
        case "function_call":
            guard let callId = item["call_id"]?.stringValue,
                  let name = item["name"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: name,
                toolCallId: callId,
                providerExecuted: false,
                codeInterpreter: nil
            )
            continuation.yield(.toolInputStart(id: callId, toolName: name, providerMetadata: nil, providerExecuted: nil))
        case "web_search_call":
            guard let callId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: webSearchToolName,
                toolCallId: callId,
                providerExecuted: true,
                codeInterpreter: nil
            )
            continuation.yield(.toolInputStart(id: callId, toolName: webSearchToolName, providerMetadata: nil, providerExecuted: true))
        case "computer_call":
            guard let callId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: "computer_use",
                toolCallId: callId,
                providerExecuted: true,
                codeInterpreter: nil
            )
            continuation.yield(.toolInputStart(id: callId, toolName: "computer_use", providerMetadata: nil, providerExecuted: true))
        case "code_interpreter_call":
            guard let callId = item["id"]?.stringValue,
                  let containerId = item["container_id"]?.stringValue else { return }
            let state = CodeInterpreterState(containerId: containerId)
            ongoingToolCalls[outputIndex] = ToolCallState(
                toolName: "code_interpreter",
                toolCallId: callId,
                providerExecuted: true,
                codeInterpreter: state
            )
            continuation.yield(.toolInputStart(id: callId, toolName: "code_interpreter", providerMetadata: nil, providerExecuted: true))
            let initial = "{\"containerId\":\"\(containerId)\",\"code\":\""
            continuation.yield(.toolInputDelta(id: callId, delta: initial, providerMetadata: nil))
        case "file_search_call":
            guard let callId = item["id"]?.stringValue else { return }
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: callId,
                toolName: "file_search",
                input: "{}",
                providerExecuted: true,
                providerMetadata: nil
            )))
        case "image_generation_call":
            guard let callId = item["id"]?.stringValue else { return }
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: callId,
                toolName: "image_generation",
                input: "{}",
                providerExecuted: true,
                providerMetadata: nil
            )))
        case "message":
            guard let id = item["id"]?.stringValue else { return }
            let metadata = openAIProviderMetadata(["itemId": .string(id)])
            continuation.yield(.textStart(id: id, providerMetadata: metadata))
        case "reasoning":
            guard let id = item["id"]?.stringValue else { return }
            let encrypted = item["encrypted_content"]?.stringValue
            activeReasoning[id] = ReasoningState(encryptedContent: encrypted, summaryParts: [0])
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
        ongoingToolCalls: inout [Int: ToolCallState],
        activeReasoning: inout [String: ReasoningState],
        hasFunctionCall: inout Bool,
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) throws {
        guard let outputIndex = chunk["output_index"]?.intValue,
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
            ongoingToolCalls[outputIndex] = nil
            continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
            let metadata = openAIProviderMetadata([
                "itemId": item["id"]?.stringValue.map(JSONValue.string) ?? .null
            ])
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: callId,
                toolName: name,
                input: arguments,
                providerExecuted: nil,
                providerMetadata: metadata
            )))
        case "web_search_call":
            guard let callId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil
            continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
            let action = item["action"] ?? .null
            let inputValue: JSONValue = .object(["action": action])
            let inputString = try jsonString(from: inputValue)
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: callId,
                toolName: webSearchToolName,
                input: inputString,
                providerExecuted: true,
                providerMetadata: nil
            )))
            let status = item["status"]?.stringValue ?? "unknown"
            let resultValue: JSONValue = .object(["status": .string(status)])
            continuation.yield(.toolResult(LanguageModelV3ToolResult(
                toolCallId: callId,
                toolName: webSearchToolName,
                result: resultValue,
                isError: nil,
                providerExecuted: true,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "computer_call":
            guard let callId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil
            continuation.yield(.toolInputEnd(id: callId, providerMetadata: nil))
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: callId,
                toolName: "computer_use",
                input: "",
                providerExecuted: true,
                providerMetadata: nil
            )))
            let status = item["status"]?.stringValue ?? "completed"
            let resultValue: JSONValue = .object([
                "type": .string("computer_use_tool_result"),
                "status": .string(status)
            ])
            continuation.yield(.toolResult(LanguageModelV3ToolResult(
                toolCallId: callId,
                toolName: "computer_use",
                result: resultValue,
                isError: nil,
                providerExecuted: true,
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
            continuation.yield(.toolResult(LanguageModelV3ToolResult(
                toolCallId: callId,
                toolName: "file_search",
                result: resultValue,
                isError: nil,
                providerExecuted: true,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "code_interpreter_call":
            guard let callId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil
            let resultValue: JSONValue = .object([
                "outputs": item["outputs"] ?? .null
            ])
            continuation.yield(.toolResult(LanguageModelV3ToolResult(
                toolCallId: callId,
                toolName: "code_interpreter",
                result: resultValue,
                isError: nil,
                providerExecuted: true,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "image_generation_call":
            guard let callId = item["id"]?.stringValue,
                  let resultString = item["result"]?.stringValue else { return }
            let resultValue: JSONValue = .object(["result": .string(resultString)])
            continuation.yield(.toolResult(LanguageModelV3ToolResult(
                toolCallId: callId,
                toolName: "image_generation",
                result: resultValue,
                isError: nil,
                providerExecuted: true,
                preliminary: nil,
                providerMetadata: nil
            )))
        case "local_shell_call":
            guard let callId = item["call_id"]?.stringValue,
                  let action = item["action"],
                  let itemId = item["id"]?.stringValue else { return }
            ongoingToolCalls[outputIndex] = nil
            let inputValue: JSONValue = .object(["action": action])
            let inputString = try jsonString(from: inputValue)
            let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: callId,
                toolName: "local_shell",
                input: inputString,
                providerExecuted: true,
                providerMetadata: metadata
            )))
        case "message":
            if let id = item["id"]?.stringValue {
                continuation.yield(.textEnd(id: id, providerMetadata: nil))
            }
        case "reasoning":
            guard let id = item["id"]?.stringValue,
                  let state = activeReasoning[id] else { return }
            let metadata = openAIProviderMetadata([
                "itemId": .string(id),
                "reasoningEncryptedContent": state.encryptedContent.map(JSONValue.string) ?? .null
            ])
            for summaryIndex in state.summaryParts {
                continuation.yield(.reasoningEnd(id: "\(id):\(summaryIndex)", providerMetadata: metadata))
            }
            activeReasoning[id] = nil
        default:
            break
        }
    }

    private func handleFunctionCallArgumentsDelta(
        _ chunk: [String: JSONValue],
        ongoingToolCalls: inout [Int: ToolCallState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        guard let outputIndex = chunk["output_index"]?.intValue,
              let delta = chunk["delta"]?.stringValue,
              let state = ongoingToolCalls[outputIndex] else {
            return
        }
        continuation.yield(.toolInputDelta(id: state.toolCallId, delta: delta, providerMetadata: nil))
    }

    private func handleImageGenerationPartial(
        _ chunk: [String: JSONValue],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        guard let toolCallId = chunk["item_id"]?.stringValue,
              let partial = chunk["partial_image_b64"]?.stringValue else {
            return
        }
        let resultValue: JSONValue = .object(["result": .string(partial)])
        continuation.yield(.toolResult(LanguageModelV3ToolResult(
            toolCallId: toolCallId,
            toolName: "image_generation",
            result: resultValue,
            isError: nil,
            providerExecuted: true,
            preliminary: true,
            providerMetadata: nil
        )))
    }

    private func handleCodeInterpreterDelta(
        _ chunk: [String: JSONValue],
        ongoingToolCalls: inout [Int: ToolCallState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        guard let outputIndex = chunk["output_index"]?.intValue,
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
        ongoingToolCalls: inout [Int: ToolCallState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        guard let outputIndex = chunk["output_index"]?.intValue,
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
            let inputString = try jsonString(from: inputValue)
            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                toolCallId: state.toolCallId,
                toolName: "code_interpreter",
                input: inputString,
                providerExecuted: true,
                providerMetadata: nil
            )))
        } catch {
            continuation.yield(.error(error: .string(String(describing: error))))
        }

        ongoingToolCalls[outputIndex] = nil
    }

    private func handleReasoningSummaryPartAdded(
        _ chunk: [String: JSONValue],
        activeReasoning: inout [String: ReasoningState],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        guard let itemId = chunk["item_id"]?.stringValue,
              var state = activeReasoning[itemId],
              let summaryIndex = chunk["summary_index"]?.intValue,
              summaryIndex >= 0 else {
            return
        }

        if !state.summaryParts.contains(summaryIndex) {
            state.summaryParts.append(summaryIndex)
            activeReasoning[itemId] = state
            let metadata = openAIProviderMetadata([
                "itemId": .string(itemId),
                "reasoningEncryptedContent": state.encryptedContent.map(JSONValue.string) ?? .null
            ])
            continuation.yield(.reasoningStart(id: "\(itemId):\(summaryIndex)", providerMetadata: metadata))
        }
    }

    private func handleReasoningSummaryTextDelta(
        _ chunk: [String: JSONValue],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        guard let itemId = chunk["item_id"]?.stringValue,
              let summaryIndex = chunk["summary_index"]?.intValue,
              let delta = chunk["delta"]?.stringValue else {
            return
        }
        let metadata = openAIProviderMetadata(["itemId": .string(itemId)])
        continuation.yield(.reasoningDelta(id: "\(itemId):\(summaryIndex)", delta: delta, providerMetadata: metadata))
    }

    private func handleTextDelta(
        _ chunk: [String: JSONValue],
        logprobsRequested: Bool,
        collectedLogprobs: inout [JSONValue],
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
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
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) {
        guard let annotation = chunk["annotation"]?.objectValue,
              let type = annotation["type"]?.stringValue else {
            return
        }

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
            let title = annotation["quote"]?.stringValue
                ?? annotation["filename"]?.stringValue
                ?? "Document"
            let filename = annotation["filename"]?.stringValue
                ?? annotation["file_id"]?.stringValue
            continuation.yield(.source(.document(
                id: nextSourceId(),
                mediaType: "text/plain",
                title: title,
                filename: filename,
                providerMetadata: nil
            )))
        default:
            break
        }
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

    var intValue: Int? {
        guard let number = numberValue else { return nil }
        return Int(number)
    }
}
