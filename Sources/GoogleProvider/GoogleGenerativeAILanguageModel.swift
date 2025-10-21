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
        public let headers: @Sendable () -> [String: String?]
        public let fetch: FetchFunction?
        public let generateId: @Sendable () -> String
        public let supportedUrls: @Sendable () -> [String: [NSRegularExpression]]

        public init(
            provider: String,
            baseURL: String,
            headers: @escaping @Sendable () -> [String: String?],
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
        let warnings: [LanguageModelV3CallWarning]
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
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

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
            generateId: config.generateId
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
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

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
                var finishReason: LanguageModelV3FinishReason = .unknown
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
                        case .failure(let error, _):
                            finishReason = .error
                            continuation.yield(.error(error: .string(String(describing: error))))
                        case .success(let chunk, _):
                            if let usageMetadata = chunk.usageMetadata {
                                usage = LanguageModelV3Usage(
                                    inputTokens: usageMetadata.promptTokenCount,
                                    outputTokens: usageMetadata.candidatesTokenCount,
                                    totalTokens: usageMetadata.totalTokenCount,
                                    reasoningTokens: usageMetadata.thoughtsTokenCount,
                                    cachedInputTokens: usageMetadata.cachedContentTokenCount
                                )
                            }

                            guard let candidate = chunk.candidates.first else { continue }

                            if let parts = candidate.content?.parts {
                                handleStreamingParts(
                                    parts: parts,
                                    continuation: continuation,
                                    currentTextBlockId: &currentTextBlockId,
                                    currentReasoningBlockId: &currentReasoningBlockId,
                                    blockCounter: &blockCounter,
                                    lastCodeExecutionToolCallId: &lastCodeExecutionToolCallId,
                                    hasToolCalls: &hasToolCalls,
                                    generateId: config.generateId
                                )

                                for inlineData in parts.compactMap({ $0.inlineData }) {
                                    continuation.yield(.file(LanguageModelV3File(mediaType: inlineData.mimeType, data: .base64(inlineData.data))))
                                }

                                for toolCall in getToolCallsFromParts(parts: parts, generateId: config.generateId) {
                                    continuation.yield(.toolInputStart(id: toolCall.toolCallId, toolName: toolCall.toolName, providerMetadata: toolCall.providerMetadata, providerExecuted: nil))
                                    continuation.yield(.toolInputDelta(id: toolCall.toolCallId, delta: toolCall.args, providerMetadata: toolCall.providerMetadata))
                                    continuation.yield(.toolInputEnd(id: toolCall.toolCallId, providerMetadata: toolCall.providerMetadata))
                                    continuation.yield(.toolCall(LanguageModelV3ToolCall(toolCallId: toolCall.toolCallId, toolName: toolCall.toolName, input: toolCall.args, providerMetadata: toolCall.providerMetadata)))
                                    hasToolCalls = true
                                }

                            }

                            // Источники могут приходить даже когда parts отсутствуют — обрабатываем независимо
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
                                finishReason = mapGoogleGenerativeAIFinishReason(
                                    finishReason: finish,
                                    hasToolCalls: hasToolCalls
                                )

                                providerMetadata = makeProviderMetadata(
                                    promptFeedback: chunk.promptFeedback,
                                    groundingMetadata: candidate.groundingMetadata,
                                    urlContextMetadata: candidate.urlContextMetadata,
                                    safetyRatings: candidate.safetyRatings,
                                    usageMetadata: chunk.usageMetadata
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
        var warnings: [LanguageModelV3CallWarning] = []

        let googleOptions = try await parseProviderOptions(
            provider: "google",
            providerOptions: options.providerOptions,
            schema: googleGenerativeAIProviderOptionsSchema
        )

        if googleOptions?.thinkingConfig?.includeThoughts == true,
           !config.provider.hasPrefix("google.vertex.") {
            warnings.append(.other(message: "The 'includeThoughts' option is only supported with the Google Vertex provider and might not be supported with the current provider (\(config.provider))."))
        }

        let isGemmaModel = modelIdentifier.rawValue.lowercased().hasPrefix("gemma-")
        let convertedPrompt = try convertToGoogleGenerativeAIMessages(
            options.prompt,
            options: GoogleGenerativeAIMessagesOptions(isGemmaModel: isGemmaModel)
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
        if let value = options.stopSequences, !value.isEmpty {
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

        if let modalities = googleOptions?.responseModalities, !modalities.isEmpty {
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
            if !thinkingJSON.isEmpty {
                generationConfig["thinkingConfig"] = .object(thinkingJSON)
            }
        }

        if let mediaResolution = googleOptions?.mediaResolution {
            generationConfig["mediaResolution"] = .string(mediaResolution.rawValue)
        }

        var body: [String: JSONValue] = [
            "contents": promptJSON.contents
        ]

        if let systemInstruction = promptJSON.systemInstruction, !isGemmaModel {
            body["systemInstruction"] = systemInstruction
        }

        // Always include generationConfig, even if empty (matches upstream behavior)
        body["generationConfig"] = .object(generationConfig)

        if let safetySettings = googleOptions?.safetySettings, !safetySettings.isEmpty {
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

        if let labels = googleOptions?.labels, !labels.isEmpty {
            body["labels"] = .object(labels.mapValues { .string($0) })
        }

        if let tools = preparedTools.tools {
            body["tools"] = tools
        }
        if let toolConfig = preparedTools.toolConfig {
            body["toolConfig"] = toolConfig
        }

        return PreparedRequest(body: body, warnings: warnings)
    }
}

// MARK: - Mapping Helpers

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

    let candidates: [Candidate]
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
    generateId: @escaping @Sendable () -> String
) -> (
    content: [LanguageModelV3Content],
    finishReason: LanguageModelV3FinishReason,
    usage: LanguageModelV3Usage,
    providerMetadata: SharedV3ProviderMetadata?
) {
    guard let candidate = response.candidates.first else {
        return (
            content: [],
            finishReason: .unknown,
            usage: LanguageModelV3Usage(
                inputTokens: usageMetadata?.promptTokenCount,
                outputTokens: usageMetadata?.candidatesTokenCount,
                totalTokens: usageMetadata?.totalTokenCount,
                reasoningTokens: usageMetadata?.thoughtsTokenCount,
                cachedInputTokens: usageMetadata?.cachedContentTokenCount
            ),
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
                            providerMetadata: metadataFromThoughtSignature(part.thoughtSignature)
                        )
                    )
                )
                hasToolCalls = true
            } else if let result = part.codeExecutionResult, let toolCallId = lastCodeExecutionToolCallId {
                // Use actual values without defaults - omit keys if nil
                var resultDict: [String: JSONValue] = [:]
                if let outcome = result.outcome {
                    resultDict["outcome"] = .string(outcome)
                }
                if let output = result.output {
                    resultDict["output"] = .string(output)
                }
                let resultObject: JSONValue = .object(resultDict)
                content.append(
                    .toolResult(
                        LanguageModelV3ToolResult(
                            toolCallId: toolCallId,
                            toolName: "code_execution",
                            result: resultObject,
                            providerExecuted: true,
                            providerMetadata: metadataFromThoughtSignature(part.thoughtSignature)
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
                            providerMetadata: metadataFromThoughtSignature(part.thoughtSignature)
                        )
                    )
                )
                hasToolCalls = true
            } else if let inlineData = part.inlineData {
                content.append(
                    .file(
                        LanguageModelV3File(
                            mediaType: inlineData.mimeType,
                            data: .base64(inlineData.data)
                        )
                    )
                )
            } else if let text = part.text, !text.isEmpty {
                let providerMetadata = metadataFromThoughtSignature(part.thoughtSignature)
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
            }
        }
    }

    if let sources = extractSources(
        groundingMetadata: candidate.groundingMetadata,
        generateId: generateId
    ) {
        content.append(contentsOf: sources.map(LanguageModelV3Content.source))
    }

    let usage = LanguageModelV3Usage(
        inputTokens: usageMetadata?.promptTokenCount,
        outputTokens: usageMetadata?.candidatesTokenCount,
        totalTokens: usageMetadata?.totalTokenCount,
        reasoningTokens: usageMetadata?.thoughtsTokenCount,
        cachedInputTokens: usageMetadata?.cachedContentTokenCount
    )

    let finishReason = mapGoogleGenerativeAIFinishReason(
        finishReason: candidate.finishReason,
        hasToolCalls: hasToolCalls
    )

    let providerMetadata = makeProviderMetadata(
        promptFeedback: response.promptFeedback,
        groundingMetadata: candidate.groundingMetadata,
        urlContextMetadata: candidate.urlContextMetadata,
        safetyRatings: candidate.safetyRatings,
        usageMetadata: usageMetadata
    )

    return (
        content: content,
        finishReason: finishReason,
        usage: usage,
        providerMetadata: providerMetadata
    )
}

private func metadataFromThoughtSignature(_ signature: String?) -> SharedV3ProviderMetadata? {
    guard let signature else { return nil }
    return ["google": ["thoughtSignature": .string(signature)]]
}

private func makeProviderMetadata(
    promptFeedback: JSONValue?,
    groundingMetadata: JSONValue?,
    urlContextMetadata: JSONValue?,
    safetyRatings: JSONValue?,
    usageMetadata: GoogleGenerativeAIResponse.UsageMetadata?
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
    } else {
        metadata["usageMetadata"] = .null
    }

    return metadata.isEmpty ? nil : ["google": metadata]
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
        guard case .object(let chunkObject) = chunk,
              let webValue = chunkObject["web"],
              case .object(let webObject) = webValue,
              let uriValue = webObject["uri"],
              case .string(let uri) = uriValue else {
            continue
        }

        let title: String?
        if let titleValue = webObject["title"], case .string(let t) = titleValue {
            title = t
        } else {
            title = nil
        }

        sources.append(
            .url(
                id: generateId(),
                url: uri,
                title: title,
                providerMetadata: nil
            )
        )
    }

    return sources.isEmpty ? nil : sources
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
                return .object([
                    "inlineData": .object([
                        "mimeType": .string(data.mimeType),
                        "data": .string(data.data)
                    ])
                ])
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
    generateId: @escaping @Sendable () -> String
) -> [ToolCallDelta] {
    parts.compactMap { part in
        guard let functionCall = part.functionCall, let args = functionCall.args else {
            return nil
        }

        return ToolCallDelta(
            toolCallId: generateId(),
            toolName: functionCall.name,
            args: stringifyJSONValue(args),
            providerMetadata: metadataFromThoughtSignature(part.thoughtSignature)
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
    generateId: @escaping @Sendable () -> String
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
                        providerMetadata: metadataFromThoughtSignature(part.thoughtSignature)
                    )
                )
            )
            hasToolCalls = true
        } else if let result = part.codeExecutionResult, let toolCallId = lastCodeExecutionToolCallId {
            // Use actual values without defaults - omit keys if nil
            var resultDict: [String: JSONValue] = [:]
            if let outcome = result.outcome {
                resultDict["outcome"] = .string(outcome)
            }
            if let output = result.output {
                resultDict["output"] = .string(output)
            }
            let resultObject: JSONValue = .object(resultDict)
            continuation.yield(
                .toolResult(
                    LanguageModelV3ToolResult(
                        toolCallId: toolCallId,
                        toolName: "code_execution",
                        result: resultObject,
                        providerExecuted: true,
                        providerMetadata: metadataFromThoughtSignature(part.thoughtSignature)
                    )
                )
            )
            lastCodeExecutionToolCallId = nil
        } else if let text = part.text, !text.isEmpty {
            let providerMetadata = metadataFromThoughtSignature(part.thoughtSignature)
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
