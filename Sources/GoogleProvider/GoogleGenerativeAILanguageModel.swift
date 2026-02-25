import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias GroundingMetadataSchema = JSONValue
public typealias UrlContextMetadataSchema = JSONValue
public typealias SafetyRatingSchema = JSONValue

public struct GoogleGenerativeAISharedMetadata: Sendable, Equatable {
    public let promptFeedback: JSONValue?
    public let groundingMetadata: GroundingMetadataSchema?
    public let urlContextMetadata: UrlContextMetadataSchema?
    public let safetyRatings: [SafetyRatingSchema]?
    public let usageMetadata: JSONValue?

    public init(
        promptFeedback: JSONValue? = nil,
        groundingMetadata: GroundingMetadataSchema? = nil,
        urlContextMetadata: UrlContextMetadataSchema? = nil,
        safetyRatings: [SafetyRatingSchema]? = nil,
        usageMetadata: JSONValue? = nil
    ) {
        self.promptFeedback = promptFeedback
        self.groundingMetadata = groundingMetadata
        self.urlContextMetadata = urlContextMetadata
        self.safetyRatings = safetyRatings
        self.usageMetadata = usageMetadata
    }
}

public final class GoogleGenerativeAILanguageModel: LanguageModelV3 {
    public struct Config: Sendable {
        public let provider: String
        public let baseURL: String
        public let headers: @Sendable () throws -> [String: String?]
        public let fetch: FetchFunction?
        public let generateId: @Sendable () -> String
        public let supportedUrls: @Sendable () -> [String: [NSRegularExpression]]

        public init(
            provider: String,
            baseURL: String,
            headers: @escaping @Sendable () throws -> [String: String?],
            fetch: FetchFunction?,
            generateId: @escaping @Sendable () -> String,
            supportedUrls: @escaping @Sendable () -> [String: [NSRegularExpression]]
        ) {
            self.provider = provider
            self.baseURL = baseURL
            self.headers = headers
            self.fetch = fetch
            self.generateId = generateId
            self.supportedUrls = supportedUrls
        }
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
        let providerOptionsName: String
    }

    private let modelIdentifier: GoogleGenerativeAIModelId
    private let config: Config

    public init(modelId: GoogleGenerativeAIModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            config.supportedUrls()
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/\(getGoogleModelPath(modelIdentifier.rawValue)):generateContent",
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: googleFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleGenerativeAIResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let mapping = mapGenerateResponse(
            response: response.value,
            rawResponse: response.rawValue,
            usageMetadata: response.value.usageMetadata,
            generateId: config.generateId,
            providerOptionsName: prepared.providerOptionsName
        )

        return LanguageModelV3GenerateResult(
            content: mapping.content,
            finishReason: mapping.finishReason,
            usage: mapping.usage,
            providerMetadata: mapping.providerMetadata,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3ResponseInfo(
                id: nil,
                timestamp: nil,
                modelId: nil,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/\(getGoogleModelPath(modelIdentifier.rawValue)):streamGenerateContent?alt=sse",
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: googleFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: googleGenerativeAIChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .init(unified: .other, raw: nil)
                var usage = LanguageModelV3Usage()
                var providerMetadata: SharedV3ProviderMetadata? = nil
                var hasToolCalls = false
                var currentTextBlockId: String? = nil
                var currentReasoningBlockId: String? = nil
                var blockCounter = 0
                var emittedSourceURLs = Set<String>()
                var lastCodeExecutionToolCallId: String? = nil

                do {
                    for try await parseResult in response.value {
                        if options.includeRawChunks == true, let raw = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch parseResult {
                        case .failure:
                            continuation.yield(.error(error: parseResult.streamErrorPayload))
                        case .success(let chunk, _):
                            if let usageMetadata = chunk.usageMetadata {
                                usage = convertGoogleGenerativeAIUsage(usageMetadata)
                            }

                            guard let candidate = chunk.candidates?.first else { continue }

                            if let parts = candidate.content?.parts {
                                handleStreamingParts(
                                    parts: parts,
                                    continuation: continuation,
                                    currentTextBlockId: &currentTextBlockId,
                                    currentReasoningBlockId: &currentReasoningBlockId,
                                    blockCounter: &blockCounter,
                                    lastCodeExecutionToolCallId: &lastCodeExecutionToolCallId,
                                    hasToolCalls: &hasToolCalls,
                                    generateId: config.generateId,
                                    providerOptionsName: prepared.providerOptionsName
                                )

                                for toolCall in getToolCallsFromParts(
                                    parts: parts,
                                    generateId: config.generateId,
                                    providerOptionsName: prepared.providerOptionsName
                                ) {
                                    continuation.yield(.toolInputStart(
                                        id: toolCall.toolCallId,
                                        toolName: toolCall.toolName,
                                        providerMetadata: toolCall.providerMetadata,
                                        providerExecuted: nil,
                                        dynamic: nil,
                                        title: nil
                                    ))
                                    continuation.yield(.toolInputDelta(id: toolCall.toolCallId, delta: toolCall.args, providerMetadata: toolCall.providerMetadata))
                                    continuation.yield(.toolInputEnd(id: toolCall.toolCallId, providerMetadata: toolCall.providerMetadata))
                                    continuation.yield(.toolCall(LanguageModelV3ToolCall(toolCallId: toolCall.toolCallId, toolName: toolCall.toolName, input: toolCall.args, providerMetadata: toolCall.providerMetadata)))
                                    hasToolCalls = true
                                }

                            }

                            // Sources can arrive even when parts are missing — handle independently.
                            if let sources = extractSources(
                                groundingMetadata: candidate.groundingMetadata,
                                generateId: config.generateId
                            ) {
                                for source in sources {
                                    if case let .url(_, url, _, _) = source, emittedSourceURLs.contains(url) {
                                        continue
                                    }
                                    if case let .url(_, url, _, _) = source {
                                        emittedSourceURLs.insert(url)
                                    }
                                    continuation.yield(.source(source))
                                }
                            }

                            if let finish = candidate.finishReason {
                                finishReason = LanguageModelV3FinishReason(
                                    unified: mapGoogleGenerativeAIFinishReason(
                                        finishReason: finish,
                                        hasToolCalls: hasToolCalls
                                    ),
                                    raw: finish
                                )

                                providerMetadata = makeProviderMetadata(
                                    promptFeedback: chunk.promptFeedback,
                                    groundingMetadata: candidate.groundingMetadata,
                                    urlContextMetadata: candidate.urlContextMetadata,
                                    safetyRatings: candidate.safetyRatings,
                                    usageMetadata: chunk.usageMetadata,
                                    providerOptionsName: prepared.providerOptionsName,
                                    omitMissingUsageMetadata: true
                                )
                            }
                        }
                    }

                    if let id = currentTextBlockId {
                        continuation.yield(.textEnd(id: id, providerMetadata: nil))
                    }

                    if let id = currentReasoningBlockId {
                        continuation.yield(.reasoningEnd(id: id, providerMetadata: nil))
                    }

                    continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3StreamResponseInfo(headers: response.responseHeaders)
        )
    }

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        let providerOptionsName = providerOptionsNamespace(for: config.provider)
        var googleOptions = try await parseProviderOptions(
            provider: providerOptionsName,
            providerOptions: options.providerOptions,
            schema: googleGenerativeAIProviderOptionsSchema
        )

        if googleOptions == nil && providerOptionsName != "google" {
            googleOptions = try await parseProviderOptions(
                provider: "google",
                providerOptions: options.providerOptions,
                schema: googleGenerativeAIProviderOptionsSchema
            )
        }

        if options.tools?.contains(where: { tool in
            guard case .provider(let providerTool) = tool else { return false }
            return providerTool.id == "google.vertex_rag_store"
        }) == true,
           !config.provider.hasPrefix("google.vertex.") {
            warnings.append(.other(message: "The 'vertex_rag_store' tool is only supported with the Google Vertex provider and might not be supported or could behave unexpectedly with the current Google provider (\(config.provider))."))
        }

        let isGemmaModel = modelIdentifier.rawValue.lowercased().hasPrefix("gemma-")
        let convertedPrompt = try convertToGoogleGenerativeAIMessages(
            options.prompt,
            options: GoogleGenerativeAIMessagesOptions(
                isGemmaModel: isGemmaModel,
                providerOptionsName: providerOptionsName
            )
        )

        let promptJSON = try encodePrompt(convertedPrompt)

        let preparedTools = prepareGoogleTools(
            tools: options.tools,
            toolChoice: options.toolChoice,
            modelId: modelIdentifier
        )
        warnings.append(contentsOf: preparedTools.toolWarnings)

        var generationConfig: [String: JSONValue] = [:]
        if let value = options.maxOutputTokens { generationConfig["maxOutputTokens"] = .number(Double(value)) }
        if let value = options.temperature { generationConfig["temperature"] = .number(value) }
        if let value = options.topK { generationConfig["topK"] = .number(Double(value)) }
        if let value = options.topP { generationConfig["topP"] = .number(value) }
        if let value = options.frequencyPenalty { generationConfig["frequencyPenalty"] = .number(value) }
        if let value = options.presencePenalty { generationConfig["presencePenalty"] = .number(value) }
        if let value = options.seed { generationConfig["seed"] = .number(Double(value)) }
        if let value = options.stopSequences {
            generationConfig["stopSequences"] = .array(value.map { .string($0) })
        }

        if case let .json(schema, _, _) = options.responseFormat {
            generationConfig["responseMimeType"] = .string("application/json")
            if let schema,
               (googleOptions?.structuredOutputs ?? true),
               let openAPISchema = convertJSONSchemaToOpenAPISchema(schema),
               let schemaJSON = try? jsonValue(from: openAPISchema) {
                generationConfig["responseSchema"] = schemaJSON
            }
        }

        if googleOptions?.audioTimestamp == true {
            generationConfig["audioTimestamp"] = .bool(true)
        }

        if let modalities = googleOptions?.responseModalities {
            generationConfig["responseModalities"] = .array(modalities.map { .string($0.rawValue) })
        }

        if let thinking = googleOptions?.thinkingConfig {
            var thinkingJSON: [String: JSONValue] = [:]
            if let includeThoughts = thinking.includeThoughts {
                thinkingJSON["includeThoughts"] = .bool(includeThoughts)
            }
            if let budget = thinking.thinkingBudget {
                thinkingJSON["thinkingBudget"] = .number(budget)
            }
            if let thinkingLevel = thinking.thinkingLevel {
                thinkingJSON["thinkingLevel"] = .string(thinkingLevel.rawValue)
            }
            if !thinkingJSON.isEmpty {
                generationConfig["thinkingConfig"] = .object(thinkingJSON)
            }
        }

        if let mediaResolution = googleOptions?.mediaResolution {
            generationConfig["mediaResolution"] = .string(mediaResolution.rawValue)
        }

        if let imageConfig = googleOptions?.imageConfig {
            var configObject: [String: JSONValue] = [:]
            if let aspectRatio = imageConfig.aspectRatio {
                configObject["aspectRatio"] = .string(aspectRatio.rawValue)
            }
            if let imageSize = imageConfig.imageSize {
                configObject["imageSize"] = .string(imageSize.rawValue)
            }
            if !configObject.isEmpty {
                generationConfig["imageConfig"] = .object(configObject)
            }
        }

        var body: [String: JSONValue] = [
            "contents": promptJSON.contents
        ]

        if let systemInstruction = promptJSON.systemInstruction, !isGemmaModel {
            body["systemInstruction"] = systemInstruction
        }

        // Always include generationConfig, even if empty (matches upstream behavior)
        body["generationConfig"] = .object(generationConfig)

        if let safetySettings = googleOptions?.safetySettings {
            body["safetySettings"] = .array(safetySettings.map { setting in
                .object([
                    "category": .string(setting.category.rawValue),
                    "threshold": .string(setting.threshold.rawValue)
                ])
            })
        }

        if let cachedContent = googleOptions?.cachedContent {
            body["cachedContent"] = .string(cachedContent)
        }

        if let labels = googleOptions?.labels {
            body["labels"] = .object(labels.mapValues { .string($0) })
        }

        if let tools = preparedTools.tools {
            body["tools"] = tools
        }
        if let toolConfig = mergeToolConfig(
            toolConfig: preparedTools.toolConfig,
            retrievalConfig: googleOptions?.retrievalConfig
        ) {
            body["toolConfig"] = toolConfig
        }

        return PreparedRequest(
            body: body,
            warnings: warnings,
            providerOptionsName: providerOptionsName
        )
    }
}

// MARK: - Mapping Helpers

private func providerOptionsNamespace(for provider: String) -> String {
    provider.contains("vertex") ? "vertex" : "google"
}

private func mergeToolConfig(
    toolConfig: JSONValue?,
    retrievalConfig: GoogleGenerativeAIRetrievalConfig?
) -> JSONValue? {
    guard let retrievalConfig else { return toolConfig }

    var merged: [String: JSONValue] = [:]
    if let toolConfig, case .object(let toolConfigObject) = toolConfig {
        merged = toolConfigObject
    }
    merged["retrievalConfig"] = retrievalConfigToJSONValue(retrievalConfig)
    return .object(merged)
}

private func retrievalConfigToJSONValue(_ retrievalConfig: GoogleGenerativeAIRetrievalConfig) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let latLng = retrievalConfig.latLng {
        object["latLng"] = .object([
            "latitude": .number(latLng.latitude),
            "longitude": .number(latLng.longitude)
        ])
    }
    return .object(object)
}

private struct GoogleGenerativeAIResponse: Codable {
    struct Candidate: Codable {
        struct Content: Codable {
            let parts: [Part]?
        }

        struct Part: Codable {
            struct InlineData: Codable {
                let mimeType: String
                let data: String
            }

            struct FunctionCall: Codable {
                let name: String
                let args: JSONValue?
            }

            struct FunctionResponse: Codable {
                let name: String
                let response: JSONValue?
            }

            struct ExecutableCode: Codable {
                let language: String?
                let code: String?
            }

            struct CodeExecutionResult: Codable {
                let outcome: String?
                let output: String?
            }

            let inlineData: InlineData?
            let functionCall: FunctionCall?
            let functionResponse: FunctionResponse?
            let executableCode: ExecutableCode?
            let codeExecutionResult: CodeExecutionResult?
            let text: String?
            let thought: Bool?
            let thoughtSignature: String?
        }

        let content: Content?
        let finishReason: String?
        let safetyRatings: JSONValue?
        let groundingMetadata: JSONValue?
        let urlContextMetadata: JSONValue?
    }

    struct UsageMetadata: Codable {
        let cachedContentTokenCount: Int?
        let thoughtsTokenCount: Int?
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?
        let trafficType: String?
    }

    let candidates: [Candidate]
    let usageMetadata: UsageMetadata?
    let promptFeedback: JSONValue?
}

private struct GoogleGenerativeAIChunk: Codable {
    struct Candidate: Codable {
        typealias Part = GoogleGenerativeAIResponse.Candidate.Part

        struct Content: Codable {
            let parts: [Part]?
        }

        let content: Content?
        let finishReason: String?
        let safetyRatings: JSONValue?
        let groundingMetadata: JSONValue?
        let urlContextMetadata: JSONValue?
    }

    let candidates: [Candidate]?
    let usageMetadata: GoogleGenerativeAIResponse.UsageMetadata?
    let promptFeedback: JSONValue?
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let googleGenerativeAIResponseSchema = FlexibleSchema(
    Schema<GoogleGenerativeAIResponse>.codable(
        GoogleGenerativeAIResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let googleGenerativeAIChunkSchema = FlexibleSchema(
    Schema<GoogleGenerativeAIChunk>.codable(
        GoogleGenerativeAIChunk.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private func mapGenerateResponse(
    response: GoogleGenerativeAIResponse,
    rawResponse: Any?,
    usageMetadata: GoogleGenerativeAIResponse.UsageMetadata?,
    generateId: @escaping @Sendable () -> String,
    providerOptionsName: String
) -> (
    content: [LanguageModelV3Content],
    finishReason: LanguageModelV3FinishReason,
    usage: LanguageModelV3Usage,
    providerMetadata: SharedV3ProviderMetadata?
) {
    guard let candidate = response.candidates.first else {
        return (
            content: [],
            finishReason: .init(unified: .other, raw: nil),
            usage: convertGoogleGenerativeAIUsage(usageMetadata),
            providerMetadata: nil
        )
    }

    var hasToolCalls = false
    var lastCodeExecutionToolCallId: String? = nil
    var content: [LanguageModelV3Content] = []

    if let parts = candidate.content?.parts {
        for part in parts {
            if let executableCode = part.executableCode, let code = executableCode.code {
                let toolCallId = generateId()
                lastCodeExecutionToolCallId = toolCallId

                // Serialize executableCode as-is without adding defaults
                var argsDict: [String: JSONValue] = ["code": .string(code)]
                if let language = executableCode.language {
                    argsDict["language"] = .string(language)
                }
                let argsObject: JSONValue = .object(argsDict)

                content.append(
                    .toolCall(
                        LanguageModelV3ToolCall(
                            toolCallId: toolCallId,
                            toolName: "code_execution",
                            input: stringifyJSONValue(argsObject),
                            providerExecuted: true,
                            providerMetadata: metadataFromThoughtSignature(
                                part.thoughtSignature,
                                providerOptionsName: providerOptionsName
                            )
                        )
                    )
                )
            } else if let result = part.codeExecutionResult, let toolCallId = lastCodeExecutionToolCallId {
                // Match upstream: include empty string when output is missing.
                var resultDict: [String: JSONValue] = [:]
                if let outcome = result.outcome {
                    resultDict["outcome"] = .string(outcome)
                }
                resultDict["output"] = .string(result.output ?? "")
                let resultObject: JSONValue = .object(resultDict)
                content.append(
                    .toolResult(
                        LanguageModelV3ToolResult(
                            toolCallId: toolCallId,
                            toolName: "code_execution",
                            result: resultObject,
                            providerMetadata: metadataFromThoughtSignature(
                                part.thoughtSignature,
                                providerOptionsName: providerOptionsName
                            )
                        )
                    )
                )
                lastCodeExecutionToolCallId = nil
            } else if let functionCall = part.functionCall, let args = functionCall.args {
                let toolCallId = generateId()
                content.append(
                    .toolCall(
                        LanguageModelV3ToolCall(
                            toolCallId: toolCallId,
                            toolName: functionCall.name,
                            input: stringifyJSONValue(args),
                            providerMetadata: metadataFromThoughtSignature(
                                part.thoughtSignature,
                                providerOptionsName: providerOptionsName
                            )
                        )
                    )
                )
                hasToolCalls = true
            } else if let text = part.text {
                let providerMetadata = metadataFromThoughtSignature(
                    part.thoughtSignature,
                    providerOptionsName: providerOptionsName
                )

                if text.isEmpty {
                    updateLastContentProviderMetadata(
                        content: &content,
                        providerMetadata: providerMetadata
                    )
                    continue
                }

                if part.thought == true {
                    content.append(
                        .reasoning(
                            LanguageModelV3Reasoning(text: text, providerMetadata: providerMetadata)
                        )
                    )
                } else {
                    content.append(
                        .text(
                            LanguageModelV3Text(text: text, providerMetadata: providerMetadata)
                        )
                    )
                }
            } else if let inlineData = part.inlineData {
                content.append(
                    .file(
                        LanguageModelV3File(
                            mediaType: inlineData.mimeType,
                            data: .base64(inlineData.data)
                        )
                    )
                )
            }
        }
    }

    if let sources = extractSources(
        groundingMetadata: candidate.groundingMetadata,
        generateId: generateId
    ) {
        content.append(contentsOf: sources.map(LanguageModelV3Content.source))
    }

    let usage = convertGoogleGenerativeAIUsage(usageMetadata)

    let rawFinishReason = candidate.finishReason
    let finishReason = LanguageModelV3FinishReason(
        unified: mapGoogleGenerativeAIFinishReason(
            finishReason: rawFinishReason,
            hasToolCalls: hasToolCalls
        ),
        raw: rawFinishReason
    )

    let providerMetadata = makeProviderMetadata(
        promptFeedback: response.promptFeedback,
        groundingMetadata: candidate.groundingMetadata,
        urlContextMetadata: candidate.urlContextMetadata,
        safetyRatings: candidate.safetyRatings,
        usageMetadata: usageMetadata,
        providerOptionsName: providerOptionsName
    )

    return (
        content: content,
        finishReason: finishReason,
        usage: usage,
        providerMetadata: providerMetadata
    )
}

private func convertGoogleGenerativeAIUsage(_ usage: GoogleGenerativeAIResponse.UsageMetadata?) -> LanguageModelV3Usage {
    // Port of `packages/google/src/convert-google-generative-ai-usage.ts`
    guard let usage else {
        return LanguageModelV3Usage()
    }

    let promptTokens = usage.promptTokenCount ?? 0
    let candidatesTokens = usage.candidatesTokenCount ?? 0
    let cachedContentTokens = usage.cachedContentTokenCount ?? 0
    let thoughtsTokens = usage.thoughtsTokenCount ?? 0

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: promptTokens,
            noCache: promptTokens - cachedContentTokens,
            cacheRead: cachedContentTokens,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: candidatesTokens + thoughtsTokens,
            text: candidatesTokens,
            reasoning: thoughtsTokens
        ),
        raw: try? JSONEncoder().encodeToJSONValue(usage)
    )
}

private func metadataFromThoughtSignature(
    _ signature: String?,
    providerOptionsName: String
) -> SharedV3ProviderMetadata? {
    guard let signature else { return nil }
    return [providerOptionsName: ["thoughtSignature": .string(signature)]]
}

private func updateLastContentProviderMetadata(
    content: inout [LanguageModelV3Content],
    providerMetadata: SharedV3ProviderMetadata?
) {
    guard let providerMetadata, !content.isEmpty else { return }

    let lastIndex = content.count - 1
    switch content[lastIndex] {
    case .text(let text):
        content[lastIndex] = .text(
            LanguageModelV3Text(
                text: text.text,
                providerMetadata: providerMetadata
            )
        )
    case .reasoning(let reasoning):
        content[lastIndex] = .reasoning(
            LanguageModelV3Reasoning(
                text: reasoning.text,
                providerMetadata: providerMetadata
            )
        )
    case .toolCall(let toolCall):
        content[lastIndex] = .toolCall(
            LanguageModelV3ToolCall(
                toolCallId: toolCall.toolCallId,
                toolName: toolCall.toolName,
                input: toolCall.input,
                providerExecuted: toolCall.providerExecuted,
                dynamic: toolCall.dynamic,
                providerMetadata: providerMetadata
            )
        )
    case .toolResult(let toolResult):
        content[lastIndex] = .toolResult(
            LanguageModelV3ToolResult(
                toolCallId: toolResult.toolCallId,
                toolName: toolResult.toolName,
                result: toolResult.result,
                isError: toolResult.isError,
                preliminary: toolResult.preliminary,
                dynamic: toolResult.dynamic,
                providerMetadata: providerMetadata
            )
        )
    case .source(let source):
        switch source {
        case let .url(id, url, title, _):
            content[lastIndex] = .source(
                .url(
                    id: id,
                    url: url,
                    title: title,
                    providerMetadata: providerMetadata
                )
            )
        case let .document(id, mediaType, title, filename, _):
            content[lastIndex] = .source(
                .document(
                    id: id,
                    mediaType: mediaType,
                    title: title,
                    filename: filename,
                    providerMetadata: providerMetadata
                )
            )
        }
    case .file, .toolApprovalRequest:
        break
    }
}

private func makeProviderMetadata(
    promptFeedback: JSONValue?,
    groundingMetadata: JSONValue?,
    urlContextMetadata: JSONValue?,
    safetyRatings: JSONValue?,
    usageMetadata: GoogleGenerativeAIResponse.UsageMetadata?,
    providerOptionsName: String,
    omitMissingUsageMetadata: Bool = false
) -> SharedV3ProviderMetadata? {
    var metadata: [String: JSONValue] = [:]

    if let promptFeedback {
        metadata["promptFeedback"] = promptFeedback
    } else {
        metadata["promptFeedback"] = .null
    }

    if let groundingMetadata {
        metadata["groundingMetadata"] = groundingMetadata
    } else {
        metadata["groundingMetadata"] = .null
    }

    if let urlContextMetadata {
        metadata["urlContextMetadata"] = urlContextMetadata
    } else {
        metadata["urlContextMetadata"] = .null
    }

    if let safetyRatings {
        metadata["safetyRatings"] = safetyRatings
    } else {
        metadata["safetyRatings"] = .null
    }

    if let usageMetadata, let usageJSON = try? JSONEncoder().encodeToJSONValue(usageMetadata) {
        metadata["usageMetadata"] = usageJSON
    } else if !omitMissingUsageMetadata {
        metadata["usageMetadata"] = .null
    }

    return metadata.isEmpty ? nil : [providerOptionsName: metadata]
}

private func extractSources(
    groundingMetadata: JSONValue?,
    generateId: @escaping @Sendable () -> String
) -> [LanguageModelV3Source]? {
    guard let groundingMetadata,
          case .object(let object) = groundingMetadata,
          let chunksValue = object["groundingChunks"],
          case .array(let chunks) = chunksValue else {
        return nil
    }

    var sources: [LanguageModelV3Source] = []

    for chunk in chunks {
        guard case .object(let chunkObject) = chunk else {
            continue
        }

        if let source = extractWebSource(from: chunkObject, generateId: generateId) {
            sources.append(source)
        } else if let source = extractRetrievedContextSource(from: chunkObject, generateId: generateId) {
            sources.append(source)
        } else if let source = extractMapsSource(from: chunkObject, generateId: generateId) {
            sources.append(source)
        }
    }

    return sources.isEmpty ? nil : sources
}

private func extractWebSource(
    from chunkObject: [String: JSONValue],
    generateId: @escaping @Sendable () -> String
) -> LanguageModelV3Source? {
    guard let webValue = chunkObject["web"],
          case .object(let webObject) = webValue,
          let uri = jsonString(webObject["uri"]) else {
        return nil
    }

    return .url(
        id: generateId(),
        url: uri,
        title: jsonString(webObject["title"]),
        providerMetadata: nil
    )
}

private func extractRetrievedContextSource(
    from chunkObject: [String: JSONValue],
    generateId: @escaping @Sendable () -> String
) -> LanguageModelV3Source? {
    guard let retrievedContextValue = chunkObject["retrievedContext"],
          case .object(let retrievedContextObject) = retrievedContextValue else {
        return nil
    }

    let uri = jsonString(retrievedContextObject["uri"])
    let fileSearchStore = jsonString(retrievedContextObject["fileSearchStore"])
    let title = jsonString(retrievedContextObject["title"])

    if let uri {
        if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
            return .url(
                id: generateId(),
                url: uri,
                title: title,
                providerMetadata: nil
            )
        }

        let metadata = documentMetadata(from: uri)
        return .document(
            id: generateId(),
            mediaType: metadata.mediaType,
            title: title ?? "Unknown Document",
            filename: metadata.filename,
            providerMetadata: nil
        )
    }

    if let fileSearchStore {
        return .document(
            id: generateId(),
            mediaType: "application/octet-stream",
            title: title ?? "Unknown Document",
            filename: lastPathComponent(of: fileSearchStore),
            providerMetadata: nil
        )
    }

    return nil
}

private func extractMapsSource(
    from chunkObject: [String: JSONValue],
    generateId: @escaping @Sendable () -> String
) -> LanguageModelV3Source? {
    guard let mapsValue = chunkObject["maps"],
          case .object(let mapsObject) = mapsValue,
          let uri = jsonString(mapsObject["uri"]) else {
        return nil
    }

    return .url(
        id: generateId(),
        url: uri,
        title: jsonString(mapsObject["title"]),
        providerMetadata: nil
    )
}

private func documentMetadata(from uri: String) -> (mediaType: String, filename: String?) {
    if uri.hasSuffix(".pdf") {
        return ("application/pdf", lastPathComponent(of: uri))
    }

    if uri.hasSuffix(".txt") {
        return ("text/plain", lastPathComponent(of: uri))
    }

    if uri.hasSuffix(".docx") {
        return ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", lastPathComponent(of: uri))
    }

    if uri.hasSuffix(".doc") {
        return ("application/msword", lastPathComponent(of: uri))
    }

    if uri.hasSuffix(".md") || uri.hasSuffix(".markdown") {
        return ("text/markdown", lastPathComponent(of: uri))
    }

    return ("application/octet-stream", lastPathComponent(of: uri))
}

private func lastPathComponent(of path: String) -> String? {
    path.components(separatedBy: "/").last
}

private func jsonString(_ value: JSONValue?) -> String? {
    guard case .string(let string) = value else { return nil }
    return string
}

// MARK: - Prompt Encoding

private func encodePrompt(_ prompt: GoogleGenerativeAIPrompt) throws -> (systemInstruction: JSONValue?, contents: JSONValue) {
    let systemInstruction = prompt.systemInstruction.flatMap { instruction -> JSONValue in
        let parts = instruction.parts.map { part in
            JSONValue.object(["text": .string(part.text)])
        }
        return .object(["parts": .array(parts)])
    }

    let contents = prompt.contents.map { content -> JSONValue in
        let parts = content.parts.map { part -> JSONValue in
            switch part {
            case .text(let text):
                var object: [String: JSONValue] = ["text": .string(text.text)]
                if let thought = text.thought {
                    object["thought"] = .bool(thought)
                }
                if let signature = text.thoughtSignature {
                    object["thoughtSignature"] = .string(signature)
                }
                return .object(object)
            case .inlineData(let data):
                var object: [String: JSONValue] = [
                    "inlineData": .object([
                        "mimeType": .string(data.mimeType),
                        "data": .string(data.data)
                    ])
                ]
                if let signature = data.thoughtSignature {
                    object["thoughtSignature"] = .string(signature)
                }
                return .object(object)
            case .functionCall(let call):
                var inner: [String: JSONValue] = [
                    "name": .string(call.name)
                ]
                inner["args"] = call.arguments
                var object: [String: JSONValue] = ["functionCall": .object(inner)]
                if let signature = call.thoughtSignature {
                    object["thoughtSignature"] = .string(signature)
                }
                return .object(object)
            case .functionResponse(let response):
                let responseObject = JSONValue.object([
                    "name": .string(response.name),
                    "response": response.response
                ])
                return .object([
                    "functionResponse": responseObject
                ])
            case .fileData(let file):
                return .object([
                    "fileData": .object([
                        "mimeType": .string(file.mimeType),
                        "fileUri": .string(file.fileURI)
                    ])
                ])
            }
        }

        return .object([
            "role": .string(content.role == .user ? "user" : "model"),
            "parts": .array(parts)
        ])
    }

    return (systemInstruction, .array(contents))
}

// MARK: - Streaming Helpers

private struct ToolCallDelta {
    let toolCallId: String
    let toolName: String
    let args: String
    let providerMetadata: SharedV3ProviderMetadata?
}

private func getToolCallsFromParts(
    parts: [GoogleGenerativeAIResponse.Candidate.Part],
    generateId: @escaping @Sendable () -> String,
    providerOptionsName: String
) -> [ToolCallDelta] {
    parts.compactMap { part in
        guard let functionCall = part.functionCall, let args = functionCall.args else {
            return nil
        }

        return ToolCallDelta(
            toolCallId: generateId(),
            toolName: functionCall.name,
            args: stringifyJSONValue(args),
            providerMetadata: metadataFromThoughtSignature(
                part.thoughtSignature,
                providerOptionsName: providerOptionsName
            )
        )
    }
}

private func handleStreamingParts(
    parts: [GoogleGenerativeAIResponse.Candidate.Part],
    continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation,
    currentTextBlockId: inout String?,
    currentReasoningBlockId: inout String?,
    blockCounter: inout Int,
    lastCodeExecutionToolCallId: inout String?,
    hasToolCalls: inout Bool,
    generateId: @escaping @Sendable () -> String,
    providerOptionsName: String
) {
    for part in parts {
        if let executableCode = part.executableCode, let code = executableCode.code {
            let toolCallId = generateId()
            lastCodeExecutionToolCallId = toolCallId

            // Serialize executableCode as-is without adding defaults
            var argsDict: [String: JSONValue] = ["code": .string(code)]
            if let language = executableCode.language {
                argsDict["language"] = .string(language)
            }
            let argsObject: JSONValue = .object(argsDict)

            continuation.yield(
                .toolCall(
                    LanguageModelV3ToolCall(
                        toolCallId: toolCallId,
                        toolName: "code_execution",
                        input: stringifyJSONValue(argsObject),
                        providerExecuted: true,
                        providerMetadata: metadataFromThoughtSignature(
                                part.thoughtSignature,
                                providerOptionsName: providerOptionsName
                            )
                    )
                )
            )
        } else if let result = part.codeExecutionResult, let toolCallId = lastCodeExecutionToolCallId {
            // Match upstream: include empty string when output is missing.
            var resultDict: [String: JSONValue] = [:]
            if let outcome = result.outcome {
                resultDict["outcome"] = .string(outcome)
            }
            resultDict["output"] = .string(result.output ?? "")
            let resultObject: JSONValue = .object(resultDict)
            continuation.yield(
                .toolResult(
                    LanguageModelV3ToolResult(
                        toolCallId: toolCallId,
                        toolName: "code_execution",
                        result: resultObject,
                        providerMetadata: metadataFromThoughtSignature(
                            part.thoughtSignature,
                            providerOptionsName: providerOptionsName
                        )
                    )
                )
            )
            lastCodeExecutionToolCallId = nil
        } else if let text = part.text {
            let providerMetadata = metadataFromThoughtSignature(
                part.thoughtSignature,
                providerOptionsName: providerOptionsName
            )

            if text.isEmpty {
                if providerMetadata != nil, let currentTextBlockId {
                    continuation.yield(
                        .textDelta(
                            id: currentTextBlockId,
                            delta: "",
                            providerMetadata: providerMetadata
                        )
                    )
                }
                continue
            }

            if part.thought == true {
                if let id = currentTextBlockId {
                    continuation.yield(.textEnd(id: id, providerMetadata: nil))
                    currentTextBlockId = nil
                }
                if currentReasoningBlockId == nil {
                    currentReasoningBlockId = String(blockCounter)
                    blockCounter += 1
                    continuation.yield(.reasoningStart(id: currentReasoningBlockId!, providerMetadata: providerMetadata))
                }
                continuation.yield(.reasoningDelta(id: currentReasoningBlockId!, delta: text, providerMetadata: providerMetadata))
            } else {
                if let id = currentReasoningBlockId {
                    continuation.yield(.reasoningEnd(id: id, providerMetadata: nil))
                    currentReasoningBlockId = nil
                }
                if currentTextBlockId == nil {
                    currentTextBlockId = String(blockCounter)
                    blockCounter += 1
                    continuation.yield(.textStart(id: currentTextBlockId!, providerMetadata: providerMetadata))
                }
                continuation.yield(.textDelta(id: currentTextBlockId!, delta: text, providerMetadata: providerMetadata))
            }
        } else if let inlineData = part.inlineData {
            continuation.yield(
                .file(
                    LanguageModelV3File(
                        mediaType: inlineData.mimeType,
                        data: .base64(inlineData.data)
                    )
                )
            )
        }
    }
}

// MARK: - Utilities

private extension ParseJSONResult where Output == GoogleGenerativeAIChunk {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }

    var streamErrorPayload: JSONValue {
        switch self {
        case .failure(let error, let raw):
            if let raw, let value = try? jsonValue(from: raw) {
                return value
            }
            return .string(String(describing: error))
        case .success:
            return .string("Unknown stream parsing error")
        }
    }
}

private func stringifyJSONValue(_ value: JSONValue) -> String {
    if let data = try? JSONEncoder().encode(value),
       let string = String(data: data, encoding: .utf8) {
        return string
    }
    return "null"
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}

// MARK: - Schema Validation Functions

/**
 Returns a schema for validating grounding metadata.

 Port of `@ai-sdk/google/src/google-generative-ai-language-model.ts` getGroundingMetadataSchema().

 Used to validate grounding metadata from Google Generative AI responses containing
 web search results or Vertex AI Search results.
 */
public func getGroundingMetadataSchema() -> Schema<JSONValue> {
    let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "webSearchQueries": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")])
            ]),
            "retrievalQueries": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")])
            ]),
            "searchEntryPoint": .object([
                "type": .string("object"),
                "properties": .object([
                    "renderedContent": .object(["type": .string("string")])
                ])
            ]),
            "groundingChunks": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "web": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "uri": .object(["type": .string("string")]),
                                "title": .object(["type": .string("string")])
                            ])
                        ]),
                        "retrievedContext": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "uri": .object(["type": .string("string")]),
                                "title": .object(["type": .string("string")])
                            ])
                        ])
                    ])
                ])
            ]),
            "groundingSupports": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "segment": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "startIndex": .object(["type": .string("number")]),
                                "endIndex": .object(["type": .string("number")]),
                                "text": .object(["type": .string("string")])
                            ])
                        ]),
                        "segment_text": .object(["type": .string("string")]),
                        "groundingChunkIndices": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("number")])
                        ]),
                        "supportChunkIndices": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("number")])
                        ]),
                        "confidenceScores": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("number")])
                        ]),
                        "confidenceScore": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("number")])
                        ])
                    ])
                ])
            ]),
            "retrievalMetadata": .object([
                "anyOf": .array([
                    .object([
                        "type": .string("object"),
                        "properties": .object([
                            "webDynamicRetrievalScore": .object(["type": .string("number")])
                        ])
                    ]),
                    .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
                ])
            ])
        ]),
        "additionalProperties": .bool(true)
    ])

    return jsonSchema(schema)
}

/**
 Returns a schema for validating URL context metadata.

 Port of `@ai-sdk/google/src/google-generative-ai-language-model.ts` getUrlContextMetadataSchema().

 Used to validate URL context metadata from Google Generative AI responses.
 Reference: https://ai.google.dev/api/generate-content#UrlRetrievalMetadata
 */
public func getUrlContextMetadataSchema() -> Schema<JSONValue> {
    let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "urlMetadata": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "retrievedUrl": .object(["type": .string("string")]),
                        "urlRetrievalStatus": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("retrievedUrl"), .string("urlRetrievalStatus")])
                ])
            ])
        ]),
        "required": .array([.string("urlMetadata")]),
        "additionalProperties": .bool(true)
    ])

    return jsonSchema(schema)
}
