import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class MistralConversationLanguageModel: LanguageModelV4 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
        let generateId: IDGenerator
    }

    private struct Request {
        let body: JSONObject
        let warnings: [SharedV4Warning]
    }

    private let modelIdentifier: MistralConversationModelId
    private let config: Config
    private static let pdfRegex = try! NSRegularExpression(pattern: "^https://.*$")
    private static let reasoningModels: Set<String> = [
        "glm-5-2", "labs-leanstral-1-5", "labs-leanstral-1-5-1", "magistral-medium-latest", "magistral-small-latest",
        "mistral-large-4", "mistral-large-4-0", "mistral-medium", "mistral-medium-2604", "mistral-medium-3",
        "mistral-medium-3-5", "mistral-medium-3.5", "mistral-medium-latest", "mistral-small-2603", "mistral-small-latest",
        "mistral-vibe-cli-fast", "mistral-vibe-cli-latest", "mistral-vibe-cli-with-tools", "zai-glm-5-2"
    ]

    init(modelId: MistralConversationModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { ["application/pdf": [Self.pdfRegex]] }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let request = try await prepareRequest(options)
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/conversations",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(request.body),
            failedResponseHandler: mistralFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mistralConversationResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        var converter = ContentConverter(tools: options.tools, generateId: config.generateId)
        var content: [LanguageModelV4Content] = []
        var hasFunctionCalls = false
        var responseModelId: String?
        for output in response.value.outputs {
            switch output {
            case .execution(let execution): content += try converter.convertTool(execution)
            case .functionCall(let call):
                hasFunctionCalls = true
                content.append(.toolCall(.init(toolCallId: call.toolCallId, toolName: call.name, input: try call.arguments.stringValue())))
            case .message(let message):
                responseModelId = message.model ?? responseModelId
                for chunk in message.content.chunks { content += converter.convertChunk(chunk) }
            }
        }
        return .init(
            content: content,
            finishReason: .init(unified: hasFunctionCalls ? .toolCalls : .stop, raw: nil),
            usage: convertMistralUsage(response.value.usage?.value),
            request: .init(body: request.body),
            response: .init(id: response.value.conversationId, modelId: responseModelId, headers: response.responseHeaders, body: response.rawValue),
            warnings: request.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let request = try await prepareRequest(options)
        var body = request.body
        body["stream"] = .bool(true)
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/conversations",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: mistralFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: mistralConversationEventSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: request.warnings))
            let task = Task {
                struct Execution {
                    let name: String
                    var arguments: String
                    let function: String?
                }
                var executions: [String: Execution] = [:]
                var converter = ContentConverter(tools: options.tools, generateId: config.generateId)
                let tracker = StreamingToolCallTracker(enqueue: { continuation.yield($0) }, options: .init(generateId: config.generateId))
                var active: (id: String, reasoning: Bool)?
                var usage: MistralUsage?
                var hasFunctionCalls = false
                var hasError = false
                var isDone = false
                var hasModelId = false
                func closeContent() {
                    guard let previous = active else { return }
                    continuation.yield(previous.reasoning ? .reasoningEnd(id: previous.id, providerMetadata: nil) : .textEnd(id: previous.id, providerMetadata: nil))
                    active = nil
                }
                do {
                    for try await parsed in response.value {
                        if options.includeRawChunks == true {
                            switch parsed {
                            case .success(_, let raw): continuation.yield(.raw(rawValue: try jsonValue(from: raw)))
                            case .failure(_, let raw):
                                if let raw { continuation.yield(.raw(rawValue: try jsonValue(from: raw))) }
                            }
                        }
                        switch parsed {
                        case .failure(let error, _):
                            hasError = true
                            continuation.yield(.error(error: .error(error)))
                        case .success(let event, _):
                            switch event {
                            case .started(let event):
                                continuation.yield(.responseMetadata(id: event.conversationId, modelId: nil, timestamp: event.createdAt.flatMap(conversationDate)))
                            case .done(let event):
                                usage = event.usage?.value
                                isDone = true
                            case .error(let event):
                                hasError = true
                                continuation.yield(.error(error: .value(["type": "conversation.response.error", "message": .string(event.message), "code": .number(event.code)])))
                            case .message(let event):
                                if !hasModelId, let model = event.model {
                                    hasModelId = true
                                    continuation.yield(.responseMetadata(id: nil, modelId: model, timestamp: nil))
                                }
                                for part in converter.convertChunk(event.content.chunk) {
                                    let text: String
                                    let reasoning: Bool
                                    switch part {
                                    case .text(let value): text = value.text; reasoning = false
                                    case .reasoning(let value): text = value.text; reasoning = true
                                    case .source(let source): continuation.yield(.source(source)); continue
                                    default: continue
                                    }
                                    let index = event.contentIndex ?? 0
                                    let indexText = index == 0 ? "0" : try mistralJSONString(index)
                                    let id = "\(event.id)-\(indexText)"
                                    if active?.id != id || active?.reasoning != reasoning {
                                        closeContent()
                                        active = (id, reasoning)
                                        continuation.yield(reasoning ? .reasoningStart(id: id, providerMetadata: nil) : .textStart(id: id, providerMetadata: nil))
                                    }
                                    continuation.yield(reasoning ? .reasoningDelta(id: id, delta: text, providerMetadata: nil) : .textDelta(id: id, delta: text, providerMetadata: nil))
                                }
                            case .functionCall(let event):
                                closeContent()
                                hasFunctionCalls = true
                                try tracker.processDelta(.init(index: event.outputIndex, id: event.toolCallId, function: .init(name: event.name, arguments: event.arguments)))
                            case .execution(let event):
                                closeContent()
                                if var execution = executions[event.id] {
                                    execution.arguments += event.arguments
                                    executions[event.id] = execution
                                } else {
                                    executions[event.id] = Execution(name: event.name, arguments: event.arguments, function: event.function)
                                    continuation.yield(.toolInputStart(id: event.id, toolName: converter.toolNameMapping.toCustomToolName(event.name), providerMetadata: nil, providerExecuted: true, dynamic: nil, title: nil))
                                }
                            case .executionDone(let event):
                                guard let execution = executions[event.id] else {
                                    hasError = true
                                    continuation.yield(.error(error: .error(InvalidResponseDataError(data: event.id, message: "Missing tool execution start for \(event.id)"))))
                                    continue
                                }
                                continuation.yield(.toolInputDelta(id: event.id, delta: try mistralJSONString(["arguments": execution.arguments]), providerMetadata: nil))
                                continuation.yield(.toolInputEnd(id: event.id, providerMetadata: nil))
                                let result = MistralConversationToolExecution(id: event.id, name: execution.name, arguments: execution.arguments, function: event.function ?? execution.function, info: event.info)
                                for part in try converter.convertTool(result) {
                                    switch part {
                                    case .toolCall(let call): continuation.yield(.toolCall(call))
                                    case .toolResult(let value): continuation.yield(.toolResult(value))
                                    default: break
                                    }
                                }
                                executions.removeValue(forKey: event.id)
                            }
                        }
                    }
                    closeContent()
                    tracker.flush()
                    let finishReason: LanguageModelV4FinishReason.Unified = hasError || !isDone || !executions.isEmpty ? .error : hasFunctionCalls ? .toolCalls : .stop
                    continuation.yield(.finish(finishReason: .init(unified: finishReason, raw: nil), usage: convertMistralUsage(usage), providerMetadata: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .init(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }

    private func prepareRequest(_ call: LanguageModelV4CallOptions) async throws -> Request {
        let options = try await parseProviderOptions(provider: "mistral", providerOptions: call.providerOptions, schema: mistralLanguageModelConversationOptions)
        var warnings: [SharedV4Warning] = []
        if call.topK != nil { warnings.append(.unsupported(feature: "topK", details: nil)) }
        var effort: String?
        if Self.reasoningModels.contains(modelId) {
            effort = options?.reasoningEffort?.rawValue
            if effort == nil, let reasoning = call.reasoning, isCustomReasoning(reasoning) {
                effort = reasoning == .none ? "none" : mapReasoningToProviderEffort(reasoning: reasoning, effortMap: [.minimal: "high", .low: "high", .medium: "high", .high: "high", .xhigh: "high", .max: "high"], warnings: &warnings)
            }
        } else if isCustomReasoning(call.reasoning) {
            warnings.append(.unsupported(feature: "reasoning", details: "This model does not support reasoning configuration."))
        }
        let structured = options?.structuredOutputs ?? true
        var prompt = call.prompt
        if case .json(let schema, _, _) = call.responseFormat, !structured || schema == nil {
            prompt = injectJSONInstructionIntoMessages(messages: prompt, schema: schema)
        }
        var completion: JSONObject = [:]
        if let value = call.maxOutputTokens { completion["max_tokens"] = .number(Double(value)) }
        if let value = call.temperature { completion["temperature"] = .number(value) }
        if let value = call.topP { completion["top_p"] = .number(value) }
        if let value = call.frequencyPenalty { completion["frequency_penalty"] = .number(value) }
        if let value = call.presencePenalty { completion["presence_penalty"] = .number(value) }
        if let value = call.stopSequences { completion["stop"] = .array(value.map(JSONValue.string)) }
        if let value = call.seed { completion["random_seed"] = .number(Double(value)) }
        if let effort { completion["reasoning_effort"] = .string(effort) }
        if case .json(let schema, let name, let description) = call.responseFormat {
            if structured, let schema {
                var jsonSchema: JSONObject = ["schema": schema, "strict": .bool(options?.strictJsonSchema ?? false), "name": .string(name ?? "response")]
                if let description { jsonSchema["description"] = .string(description) }
                completion["response_format"] = ["type": "json_schema", "json_schema": .object(jsonSchema)]
            } else { completion["response_format"] = ["type": "json_object"] }
        }
        let tools = prepareMistralConversationTools(tools: call.tools, toolChoice: call.toolChoice)
        if let choice = tools.toolChoice { completion["tool_choice"] = choice }
        let unsupported: [(String, Bool)] = [
            ("safePrompt", options?.safePrompt != nil), ("documentImageLimit", options?.documentImageLimit != nil),
            ("documentPageLimit", options?.documentPageLimit != nil), ("promptCacheKey", options?.promptCacheKey != nil),
            ("parallelToolCalls", options?.parallelToolCalls != nil)
        ]
        for (feature, present) in unsupported where present {
            warnings.append(.unsupported(feature: feature, details: "Not supported by the Mistral Conversations API."))
        }
        warnings += tools.toolWarnings
        let mapping = createToolNameMapping(tools: call.tools, providerToolNames: mistralProviderToolNames)
        let inputs = try convertToMistralConversationInputs(prompt: prompt, toolNameMapping: mapping)
        var body: JSONObject = ["model": .string(modelId), "store": .bool(false), "inputs": .array(inputs.inputs), "completion_args": .object(completion)]
        if let instructions = inputs.instructions { body["instructions"] = .string(instructions) }
        if let tools = tools.tools { body["tools"] = .array(tools) }
        return .init(body: body, warnings: warnings)
    }
}

private struct ContentConverter {
    let toolNameMapping: ToolNameMapping
    let generateId: IDGenerator
    private var sourceUrls: Set<String> = []

    init(tools: [LanguageModelV4Tool]?, generateId: @escaping IDGenerator) {
        self.toolNameMapping = createToolNameMapping(tools: tools, providerToolNames: mistralProviderToolNames)
        self.generateId = generateId
    }

    mutating func convertChunk(_ chunk: MistralConversationContent) -> [LanguageModelV4Content] {
        switch chunk {
        case .text(let text): return text.isEmpty ? [] : [.text(.init(text: text))]
        case .thinking(let parts):
            let text = parts.map(\.text).joined()
            return text.isEmpty ? [] : [.reasoning(.init(text: text))]
        case .reference(let reference):
            guard let url = reference.url, !sourceUrls.contains(url) else { return [] }
            let id = generateId()
            sourceUrls.insert(url)
            return [.source(.url(id: id, url: url, title: reference.title ?? url, providerMetadata: nil))]
        }
    }

    func convertTool(_ output: MistralConversationToolExecution) throws -> [LanguageModelV4Content] {
        let name = toolNameMapping.toCustomToolName(output.name)
        var metadata: JSONObject = ["type": "tool.execution", "name": .string(output.name)]
        if let function = output.function { metadata["function"] = .string(function) }
        var result: JSONObject = [:]
        if let info = output.info { result["info"] = .object(info) }
        return [
            .toolCall(.init(toolCallId: output.id, toolName: name, input: try mistralJSONString(["arguments": output.arguments]), providerExecuted: true, providerMetadata: ["mistral": metadata])),
            .toolResult(.init(toolCallId: output.id, toolName: name, result: .object(result)))
        ]
    }
}

private func conversationDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
