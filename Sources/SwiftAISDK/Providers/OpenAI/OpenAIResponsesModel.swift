import Foundation
import AISDKProvider
import AISDKProviderUtils

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
        get async throws { [:] }
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

        let content = value.output.flatMap { extractContent(from: $0) }

        let usage = LanguageModelV3Usage(
            inputTokens: value.usage?.inputTokens,
            outputTokens: value.usage?.outputTokens,
            totalTokens: value.usage?.totalTokens
        )

        let outputWarnings = value.warnings?.map { $0.toWarning() } ?? []
        let finishReason = mapOpenAIResponsesFinishReason(value.finishReason)

        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: nil,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3ResponseInfo(
                id: value.id,
                timestamp: nil,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: nil
            ),
            warnings: prepared.warnings + outputWarnings
        )
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        throw UnsupportedFunctionalityError(functionality: "OpenAI responses streaming not yet implemented")
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
    private func extractContent(from item: JSONValue) -> [LanguageModelV3Content] {
        guard case .object(let object) = item,
              let typeValue = object["type"],
              case .string(let type) = typeValue else {
            return []
        }

        switch type {
        case "message":
            guard let contentValue = object["content"], case .array(let parts) = contentValue else { return [] }
            var results: [LanguageModelV3Content] = []
            for part in parts {
                guard case .object(let partObject) = part,
                      let partTypeValue = partObject["type"],
                      case .string(let partType) = partTypeValue,
                      partType == "output_text",
                      let textValue = partObject["text"],
                      case .string(let text) = textValue else {
                    continue
                }
                results.append(.text(LanguageModelV3Text(text: text, providerMetadata: nil)))
            }
            return results
        default:
            return []
        }
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
}
