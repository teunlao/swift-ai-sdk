import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-chat-language-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class BedrockChatLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        let baseURL: @Sendable () -> String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let generateId: @Sendable () -> String
    }

    private struct PreparedRequest {
        let command: [String: JSONValue]
        let warnings: [LanguageModelV3CallWarning]
        let usesJsonResponseTool: Bool
        let betas: Set<String>
    }

    private let modelIdentifier: BedrockChatModelId
    private let config: Config

    init(modelId: BedrockChatModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v3" }
    public var provider: String { "amazon-bedrock" }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        [:]
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let url = chatURL(for: modelIdentifier.rawValue, path: "converse")
        let response = try await postJsonToAPI(
            url: url,
            headers: mergeHeaders(betas: prepared.betas, overrides: options.headers),
            body: JSONValue.object(prepared.command),
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockGenerateResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let content = mapGenerateContent(
            response: response.value,
            usesJsonResponseTool: prepared.usesJsonResponseTool
        )

        let usage = LanguageModelV3Usage(
            inputTokens: response.value.usage?.inputTokens,
            outputTokens: response.value.usage?.outputTokens,
            totalTokens: response.value.usage?.totalTokens,
            reasoningTokens: nil,
            cachedInputTokens: response.value.usage?.cacheReadInputTokens
        )

        let providerMetadata = buildProviderMetadata(
            trace: response.value.trace,
            cacheWriteTokens: response.value.usage?.cacheWriteInputTokens,
            usesJsonResponseTool: prepared.usesJsonResponseTool
        )

        let result = LanguageModelV3GenerateResult(
            content: content,
            finishReason: mapBedrockFinishReason(response.value.stopReason),
            usage: usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV3RequestInfo(body: prepared.command),
            response: LanguageModelV3ResponseInfo(
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )

        return result
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options)
        let url = chatURL(for: modelIdentifier.rawValue, path: "converse-stream")
        let streamResponse = try await postJsonToAPI(
            url: url,
            headers: mergeHeaders(betas: prepared.betas, overrides: options.headers),
            body: JSONValue.object(prepared.command),
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createBedrockEventStreamResponseHandler(chunkSchema: bedrockStreamSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .unknown
                var usage = LanguageModelV3Usage()
                var providerMetadataPayload: [String: JSONValue] = [:]
                var contentBlocks: [Int: ContentBlockState] = [:]

                do {
                    for try await chunkResult in streamResponse.value {
                        if options.includeRawChunks == true, let raw = chunkResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch chunkResult {
                        case .failure(let error, let raw):
                            let errorJSON = raw.flatMap { try? jsonValue(from: $0) } ?? .string(String(describing: error))
                            continuation.yield(.error(error: errorJSON))
                            finishReason = .error
                            continue

                        case .success(let chunk, _):
                            if let errorPayload = chunk.firstError {
                                continuation.yield(.error(error: .object(errorPayload)))
                                finishReason = .error
                                continue
                            }

                            if let metadata = chunk.metadata {
                                if let usageMetrics = metadata.usage {
                                    let inputTokens = usageMetrics.inputTokens ?? usage.inputTokens
                                    let outputTokens = usageMetrics.outputTokens ?? usage.outputTokens
                                    let cachedInputTokens = usageMetrics.cacheReadInputTokens ?? usage.cachedInputTokens

                                    let totalTokens: Int?
                                    if let inputTokens, let outputTokens {
                                        totalTokens = inputTokens + outputTokens
                                    } else if let inputTokens {
                                        totalTokens = inputTokens
                                    } else if let outputTokens {
                                        totalTokens = outputTokens
                                    } else {
                                        totalTokens = usage.totalTokens
                                    }

                                    usage = LanguageModelV3Usage(
                                        inputTokens: inputTokens,
                                        outputTokens: outputTokens,
                                        totalTokens: totalTokens,
                                        reasoningTokens: usage.reasoningTokens,
                                        cachedInputTokens: cachedInputTokens
                                    )

                                    if let cacheWrite = usageMetrics.cacheWriteInputTokens {
                                        providerMetadataPayload["usage"] = .object([
                                            "cacheWriteInputTokens": .number(Double(cacheWrite))
                                        ])
                                    }
                                }

                                if let trace = metadata.trace {
                                    providerMetadataPayload["trace"] = trace
                                }
                            }

                            if let messageStop = chunk.messageStop {
                                finishReason = mapBedrockFinishReason(messageStop.stopReason)
                                if let additional = messageStop.additionalModelResponseFields, !additional.isEmpty {
                                    providerMetadataPayload["additionalModelResponseFields"] = .object(additional)
                                }
                            }

                            if let contentStart = chunk.contentBlockStart {
                                let blockIndex = contentStart.contentBlockIndex
                                if let toolUse = contentStart.start?.toolUse {
                                    let toolCallId = toolUse.toolUseId ?? config.generateId()
                                    let toolName = toolUse.name ?? "tool-\(config.generateId())"
                                    contentBlocks[blockIndex] = .toolCall(
                                        ToolBlockState(
                                            id: toolCallId,
                                            name: toolName,
                                            buffer: ""
                                        )
                                    )

                                    if !prepared.usesJsonResponseTool {
                                        continuation.yield(.toolInputStart(
                                            id: toolCallId,
                                            toolName: toolName,
                                            providerMetadata: nil,
                                            providerExecuted: nil
                                        ))
                                    }
                                } else {
                                    contentBlocks[blockIndex] = .text
                                    if !prepared.usesJsonResponseTool {
                                        continuation.yield(.textStart(id: String(blockIndex), providerMetadata: nil))
                                    }
                                }
                            }

                            if let delta = chunk.contentBlockDelta {
                                let blockIndex = delta.contentBlockIndex
                                if let reasoning = delta.delta?.reasoningContent {
                                    let shouldEmitStart: Bool
                                    if case .reasoning(let started) = contentBlocks[blockIndex] {
                                        shouldEmitStart = !started
                                    } else {
                                        shouldEmitStart = true
                                    }

                                    if shouldEmitStart {
                                        var reasoningState = ContentBlockState.reasoning(started: false)
                                        reasoningState.markStarted()
                                        contentBlocks[blockIndex] = reasoningState
                                        continuation.yield(.reasoningStart(id: String(blockIndex), providerMetadata: nil))
                                    } else if var existing = contentBlocks[blockIndex] {
                                        existing.markStarted()
                                        contentBlocks[blockIndex] = existing
                                    }

                                    if let text = reasoning.text, !text.isEmpty {
                                        continuation.yield(.reasoningDelta(id: String(blockIndex), delta: text, providerMetadata: nil))
                                    } else if let signature = reasoning.signature {
                                        let metadata: SharedV3ProviderMetadata = [
                                            "bedrock": ["signature": .string(signature)]
                                        ]
                                        continuation.yield(.reasoningDelta(id: String(blockIndex), delta: "", providerMetadata: metadata))
                                    } else if let data = reasoning.data {
                                        let metadata: SharedV3ProviderMetadata = [
                                            "bedrock": ["redactedData": .string(data)]
                                        ]
                                        continuation.yield(.reasoningDelta(id: String(blockIndex), delta: "", providerMetadata: metadata))
                                    }
                                }

                                if let textDelta = delta.delta?.text, !textDelta.isEmpty {
                                    if contentBlocks[blockIndex] == nil {
                                        contentBlocks[blockIndex] = .text
                                        if !prepared.usesJsonResponseTool {
                                            continuation.yield(.textStart(id: String(blockIndex), providerMetadata: nil))
                                        }
                                    }

                                    if !prepared.usesJsonResponseTool {
                                        continuation.yield(.textDelta(id: String(blockIndex), delta: textDelta, providerMetadata: nil))
                                    }
                                }

                                if let toolDelta = delta.delta?.toolUse, var state = contentBlocks[blockIndex], state.isToolCall {
                                    let deltaText = toolDelta.input ?? ""
                                    state.append(delta: deltaText)
                                    contentBlocks[blockIndex] = state
                                    if !prepared.usesJsonResponseTool {
                                        continuation.yield(.toolInputDelta(id: state.id, delta: deltaText, providerMetadata: nil))
                                    }
                                }
                            }

                            if let stop = chunk.contentBlockStop {
                                let blockIndex = stop.contentBlockIndex
                                guard let state = contentBlocks.removeValue(forKey: blockIndex) else { continue }

                                switch state {
                                case .text:
                                    if !prepared.usesJsonResponseTool {
                                        continuation.yield(.textEnd(id: String(blockIndex), providerMetadata: nil))
                                    }
                                case .reasoning:
                                    continuation.yield(.reasoningEnd(id: String(blockIndex), providerMetadata: nil))
                                case .toolCall(let toolState):
                                    if prepared.usesJsonResponseTool {
                                        if !toolState.buffer.isEmpty {
                                            continuation.yield(.textStart(id: String(blockIndex), providerMetadata: nil))
                                            continuation.yield(.textDelta(id: String(blockIndex), delta: toolState.buffer, providerMetadata: nil))
                                            continuation.yield(.textEnd(id: String(blockIndex), providerMetadata: nil))
                                        }
                                    } else {
                                        continuation.yield(.toolInputEnd(id: toolState.id, providerMetadata: nil))
                                        continuation.yield(.toolCall(LanguageModelV3ToolCall(
                                            toolCallId: toolState.id,
                                            toolName: toolState.name,
                                            input: toolState.buffer
                                        )))
                                    }
                                }
                            }
                        }
                    }

                    if prepared.usesJsonResponseTool {
                        providerMetadataPayload["isJsonResponseFromTool"] = .bool(true)
                    }

                    let providerMetadata = providerMetadataPayload.isEmpty ? nil : ["bedrock": providerMetadataPayload]

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: usage,
                        providerMetadata: providerMetadata
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: prepared.command),
            response: LanguageModelV3StreamResponseInfo(headers: streamResponse.responseHeaders)
        )
    }

    // MARK: - Preparation

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [LanguageModelV3CallWarning] = []

        let bedrockOptions = try await parseProviderOptions(
            provider: "bedrock",
            providerOptions: options.providerOptions,
            schema: bedrockProviderOptionsSchema
        )

        if options.frequencyPenalty != nil {
            warnings.append(.unsupportedSetting(setting: "frequencyPenalty", details: nil))
        }

        if options.presencePenalty != nil {
            warnings.append(.unsupportedSetting(setting: "presencePenalty", details: nil))
        }

        if options.seed != nil {
            warnings.append(.unsupportedSetting(setting: "seed", details: nil))
        }

        if let responseFormat = options.responseFormat,
           case .json(_, _, _) = responseFormat,
           options.tools != nil && !(options.tools?.isEmpty ?? true) {
            warnings.append(.other(message: "JSON response format does not support tools. The provided tools are ignored."))
        }

        var jsonResponseTool: LanguageModelV3Tool?
        if let responseFormat = options.responseFormat,
           case .json(let schema, _, _) = responseFormat {
            let effectiveSchema = schema ?? .object([
                "type": .string("object"),
                "additionalProperties": .bool(true)
            ])

            jsonResponseTool = .function(LanguageModelV3FunctionTool(
                name: "json",
                inputSchema: effectiveSchema,
                description: "Respond with a JSON object."
            ))
        }

        var tools: [LanguageModelV3Tool]? = options.tools
        var toolChoice = options.toolChoice
        var usesJsonResponseTool = false
        if let jsonResponseTool {
            usesJsonResponseTool = true
            if tools == nil { tools = [] }
            tools?.insert(jsonResponseTool, at: 0)
            toolChoice = .tool(toolName: "json")
        }

        let preparedTools = await prepareBedrockTools(
            tools: tools,
            toolChoice: toolChoice,
            modelId: modelIdentifier.rawValue
        )

        warnings.append(contentsOf: preparedTools.warnings)

        let hasAnyTools = (preparedTools.toolConfig["tools"] != nil) || preparedTools.additionalTools != nil

        let prompt = hasAnyTools ? options.prompt : stripToolContent(from: options.prompt, warnings: &warnings)

        let bedrockMessages = try await convertToBedrockChatMessages(prompt)

        var inferenceConfig: [String: JSONValue] = [:]
        if let maxOutputTokens = options.maxOutputTokens {
            inferenceConfig["maxTokens"] = .number(Double(maxOutputTokens))
        }
        if let temperature = options.temperature {
            inferenceConfig["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            inferenceConfig["topP"] = .number(topP)
        }
        if let topK = options.topK {
            inferenceConfig["topK"] = .number(Double(topK))
        }
        if let stopSequences = options.stopSequences, !stopSequences.isEmpty {
            inferenceConfig["stopSequences"] = .array(stopSequences.map { .string($0) })
        }

        var additionalModelRequestFields = bedrockOptions?.additionalModelRequestFields ?? [:]

        if bedrockOptions?.reasoningConfig?.type == .enabled {
            let budget = bedrockOptions?.reasoningConfig?.budgetTokens
            if let budget {
                if let existing = inferenceConfig["maxTokens"], case .number(let value) = existing {
                    inferenceConfig["maxTokens"] = .number(value + Double(budget))
                } else {
                    inferenceConfig["maxTokens"] = .number(Double(budget + 4096))
                }

                additionalModelRequestFields["thinking"] = .object([
                    "type": .string("enabled"),
                    "budget_tokens": .number(Double(budget))
                ])
            }

            if inferenceConfig.removeValue(forKey: "temperature") != nil {
                warnings.append(.unsupportedSetting(setting: "temperature", details: "temperature is not supported when thinking is enabled"))
            }
            if inferenceConfig.removeValue(forKey: "topP") != nil {
                warnings.append(.unsupportedSetting(setting: "topP", details: "topP is not supported when thinking is enabled"))
            }
            if inferenceConfig.removeValue(forKey: "topK") != nil {
                warnings.append(.unsupportedSetting(setting: "topK", details: "topK is not supported when thinking is enabled"))
            }
        }

        var command: [String: JSONValue] = [
            "messages": .array(bedrockMessages.messages)
        ]

        if !bedrockMessages.system.isEmpty {
            command["system"] = .array(bedrockMessages.system)
        }
        if !inferenceConfig.isEmpty {
            command["inferenceConfig"] = .object(inferenceConfig)
        }
        if !additionalModelRequestFields.isEmpty {
            command["additionalModelRequestFields"] = .object(additionalModelRequestFields)
        }
        if let guardrailConfig = bedrockOptions?.guardrailConfig {
            command["guardrailConfig"] = guardrailConfig
        }
        if !preparedTools.toolConfig.isEmpty {
            command["toolConfig"] = .object(preparedTools.toolConfig)
        }
        if let extra = preparedTools.additionalTools {
            for (key, value) in extra {
                command[key] = value
            }
        }

        return PreparedRequest(
            command: command,
            warnings: warnings,
            usesJsonResponseTool: usesJsonResponseTool,
            betas: preparedTools.betas
        )
    }

    private func stripToolContent(from prompt: LanguageModelV3Prompt, warnings: inout [LanguageModelV3CallWarning]) -> LanguageModelV3Prompt {
        var modified: LanguageModelV3Prompt = []
        var removed = false

        for message in prompt {
            switch message {
            case .tool:
                removed = true
                continue
            case .assistant(let parts, let providerOptions):
                let filteredParts = parts.filter { part in
                    switch part {
                    case .toolCall, .toolResult:
                        removed = true
                        return false
                    default:
                        return true
                    }
                }
                if filteredParts.isEmpty {
                    continue
                }
                modified.append(.assistant(content: filteredParts, providerOptions: providerOptions))
            default:
                modified.append(message)
            }
        }

        if removed {
            warnings.append(.unsupportedSetting(
                setting: "toolContent",
                details: "Tool calls and results removed from conversation because Bedrock does not support tool content without active tools."
            ))
        }

        return modified
    }

    // MARK: - Helpers

    private func chatURL(for modelId: String, path: String) -> String {
        let encoded = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
        return "\(config.baseURL())/model/\(encoded)/\(path)"
    }

    private func mergeHeaders(betas: Set<String>, overrides: [String: String]?) -> [String: String] {
        var betaHeaders: [String: String?] = config.headers()
        if !betas.isEmpty {
            betaHeaders["anthropic-beta"] = betas.sorted().joined(separator: ",")
        }

        let merged = combineHeaders(
            betaHeaders,
            overrides?.mapValues { Optional($0) }
        )
        return merged.compactMapValues { $0 }
    }

    private func mapGenerateContent(
        response: BedrockGenerateResponse,
        usesJsonResponseTool: Bool
    ) -> [LanguageModelV3Content] {
        var items: [LanguageModelV3Content] = []

        for part in response.output.message.content {
            if let text = part.text, !usesJsonResponseTool {
                items.append(.text(LanguageModelV3Text(text: text)))
            }

            if let reasoning = part.reasoningContent {
                if let text = reasoning.reasoningText?.text {
                    var providerMetadata: SharedV3ProviderMetadata? = nil
                    if let signature = reasoning.reasoningText?.signature {
                        providerMetadata = ["bedrock": ["signature": .string(signature)]]
                    }
                    items.append(.reasoning(LanguageModelV3Reasoning(text: text, providerMetadata: providerMetadata)))
                } else if let redacted = reasoning.redactedReasoning?.data {
                    let metadata: SharedV3ProviderMetadata = ["bedrock": ["redactedData": .string(redacted)]]
                    items.append(.reasoning(LanguageModelV3Reasoning(text: "", providerMetadata: metadata)))
                }
            }

            if let toolUse = part.toolUse {
                let id = toolUse.toolUseId ?? config.generateId()
                let name = toolUse.name ?? "tool-\(config.generateId())"
                let inputJSON = (try? canonicalJSONString(from: toolUse.input ?? .object([:]))) ?? "{}"

                if usesJsonResponseTool {
                    items.append(.text(LanguageModelV3Text(text: inputJSON)))
                } else {
                    items.append(.toolCall(LanguageModelV3ToolCall(
                        toolCallId: id,
                        toolName: name,
                        input: inputJSON
                    )))
                }
            }
        }

        return items
    }

    private func buildProviderMetadata(
        trace: JSONValue?,
        cacheWriteTokens: Int?,
        usesJsonResponseTool: Bool
    ) -> SharedV3ProviderMetadata? {
        var metadata: [String: JSONValue] = [:]
        if let trace {
            metadata["trace"] = trace
        }
        if let cacheWriteTokens {
            metadata["usage"] = .object([
                "cacheWriteInputTokens": .number(Double(cacheWriteTokens))
            ])
        }
        if usesJsonResponseTool {
            metadata["isJsonResponseFromTool"] = .bool(true)
        }
        return metadata.isEmpty ? nil : ["bedrock": metadata]
    }

    private func canonicalJSONString(from value: JSONValue) throws -> String {
        let anyValue = jsonValueToFoundation(value)
        let data = try JSONSerialization.data(withJSONObject: anyValue, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(anyValue, EncodingError.Context(codingPath: [], debugDescription: "Unable to encode JSON value to string."))
        }
        return string
    }
}

// MARK: - Content Block State

private enum ContentBlockState {
    case text
    case reasoning(started: Bool)
    case toolCall(ToolBlockState)

    var isToolCall: Bool {
        if case .toolCall = self { return true }
        return false
    }

    var id: String {
        switch self {
        case .toolCall(let state):
            return state.id
        case .text, .reasoning:
            return ""
        }
    }

    mutating func markStarted() {
        if case .reasoning = self {
            self = .reasoning(started: true)
        }
    }

    var started: Bool {
        if case .reasoning(let started) = self {
            return started
        }
        return false
    }

    mutating func append(delta: String) {
        if case .toolCall(var state) = self {
            state.buffer.append(delta)
            self = .toolCall(state)
        }
    }
}

private struct ToolBlockState: Sendable {
    let id: String
    let name: String
    var buffer: String
}

private extension ParseJSONResult where Output == BedrockStreamEnvelope {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}



// MARK: - Streaming Schema

private struct BedrockStreamEnvelope: Codable, Sendable {
    struct ContentBlockDelta: Codable, Sendable {
        struct Delta: Codable, Sendable {
            struct ToolUse: Codable, Sendable {
                let input: String?
            }

            struct Reasoning: Codable, Sendable {
                struct ReasoningText: Codable, Sendable {
                    let text: String
                    let signature: String?
                }

                struct RedactedReasoning: Codable, Sendable {
                    let data: String?
                }

                let reasoningText: ReasoningText?
                let redactedReasoning: RedactedReasoning?

                var text: String? { reasoningText?.text }
                var signature: String? { reasoningText?.signature }
                var data: String? { redactedReasoning?.data }
            }

            let text: String?
            let toolUse: ToolUse?
            let reasoningContent: Reasoning?
        }
        let contentBlockIndex: Int
        let delta: Delta?
    }

    struct ContentBlockStart: Codable, Sendable {
        struct Start: Codable, Sendable {
            let toolUse: BedrockGenerateResponse.ToolUse?
        }

        let contentBlockIndex: Int
        let start: Start?
    }

    struct ContentBlockStop: Codable, Sendable {
        let contentBlockIndex: Int
    }

    struct Metadata: Codable, Sendable {
        struct Usage: Codable, Sendable {
            let cacheReadInputTokens: Int?
            let cacheWriteInputTokens: Int?
            let inputTokens: Int?
            let outputTokens: Int?
        }

        let trace: JSONValue?
        let usage: Usage?
    }

    struct MessageStop: Codable, Sendable {
        let stopReason: String?
        let additionalModelResponseFields: [String: JSONValue]?
    }

    let contentBlockDelta: ContentBlockDelta?
    let contentBlockStart: ContentBlockStart?
    let contentBlockStop: ContentBlockStop?
    let internalServerException: [String: JSONValue]?
    let messageStop: MessageStop?
    let metadata: Metadata?
    let modelStreamErrorException: [String: JSONValue]?
    let throttlingException: [String: JSONValue]?
    let validationException: [String: JSONValue]?
}

private extension BedrockStreamEnvelope {
    var firstError: [String: JSONValue]? {
        internalServerException ?? modelStreamErrorException ?? throttlingException ?? validationException
    }
}

private let bedrockStreamSchema = FlexibleSchema(
    Schema<BedrockStreamEnvelope>.codable(
        BedrockStreamEnvelope.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

// MARK: - Generate Response Schema

private struct BedrockGenerateResponse: Codable, Sendable {
    struct Output: Codable, Sendable {
        struct Message: Codable, Sendable {
            struct Content: Codable, Sendable {
                struct ReasoningContent: Codable, Sendable {
                    struct ReasoningText: Codable, Sendable {
                        let text: String
                        let signature: String?
                    }

                    struct RedactedReasoning: Codable, Sendable {
                        let data: String?
                    }

                    let reasoningText: ReasoningText?
                    let redactedReasoning: RedactedReasoning?

                    var text: String? { reasoningText?.text }
                    var signature: String? { reasoningText?.signature }
                    var data: String? { redactedReasoning?.data }
                }

                let text: String?
                let toolUse: ToolUse?
                let reasoningContent: ReasoningContent?
            }

            let role: String
            let content: [Content]
        }

        let message: Message
    }

    struct ToolUse: Codable, Sendable {
        let toolUseId: String?
        let name: String?
        let input: JSONValue?
    }

    struct Usage: Codable, Sendable {
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheWriteInputTokens: Int?
    }

    struct Metrics: Codable, Sendable {
        let latencyMs: Int?
    }

    let metrics: Metrics?
    let output: Output
    let stopReason: String?
    let trace: JSONValue?
    let usage: Usage?
}

private let bedrockGenerateResponseSchema = FlexibleSchema(
    Schema<BedrockGenerateResponse>.codable(
        BedrockGenerateResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
