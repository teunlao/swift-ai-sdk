import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenResponsesLanguageModel: LanguageModelV4 {
    public let modelId: String
    private let config: OpenResponsesConfig
    private static let imageRegex = try! NSRegularExpression(pattern: "^https?://.*$")
    private struct Request {
        let body: JSONObject
        let warnings: [SharedV4Warning]
    }

    init(modelId: String, config: OpenResponsesConfig) { self.modelId = modelId; self.config = config }
    public var provider: String { config.provider }
    public var supportedUrls: [String: [NSRegularExpression]] { ["image/*": [Self.imageRegex]] }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let request = try await prepare(options)
        let result = try await postJsonToAPI(
            url: config.url, headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(request.body), failedResponseHandler: config.failedResponseHandler ?? openResponsesFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openResponsesJSONSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        guard case .object(let fields) = result.value else { throw InvalidResponseDataError(data: result.value, message: "Expected Responses API object") }
        if openResponsesTruthy(fields["error"]), let value = fields["error"] {
            let error = try OpenResponsesResponseError(wire: value)
            let metadata = try config.getResponseErrorMetadata?(error)
            throw APICallError(message: error.message, url: config.url, requestBodyValues: request.body,
                               statusCode: metadata?.statusCode ?? 400, responseHeaders: result.responseHeaders,
                               responseBody: try openResponsesJSONString(result.value), isRetryable: metadata?.isRetryable, data: error.fields)
        }
        let response = try OpenResponsesResponse(fields)
        guard let output = response.output else {
            let detail = response.incompleteReason ?? response.status ?? ""
            throw APICallError(message: detail.isEmpty ? "Responses API returned no output" : "Responses API returned no output (\(detail))",
                               url: config.url, requestBodyValues: request.body, statusCode: 500, responseHeaders: result.responseHeaders,
                               responseBody: try openResponsesJSONString(result.value), isRetryable: false)
        }
        var content: [LanguageModelV4Content] = []
        var hasToolCalls = false
        for item in output {
            switch item {
            case .reasoning(let value):
                if let parts = value.content, !parts.isEmpty {
                    for part in parts {
                        guard let text = part.text else { throw InvalidResponseDataError(data: value.id, message: "Expected reasoning text") }
                        content.append(.reasoning(.init(text: text, providerMetadata: try openResponsesReasoningMetadata(value, namespace: config.providerOptionsName, content: [part], useExplicitContent: true))))
                    }
                } else {
                    guard let summary = value.summary else { throw InvalidResponseDataError(data: value.id, message: "Expected reasoning summary") }
                    let text = try summary.map { part -> String in
                        guard let text = part.text else { throw InvalidResponseDataError(data: value.id, message: "Expected reasoning summary text") }
                        return text
                    }.joined()
                    content.append(.reasoning(.init(text: text, providerMetadata: try openResponsesReasoningMetadata(value, namespace: config.providerOptionsName))))
                }
            case .message(let value):
                guard let parts = value.content else { throw InvalidResponseDataError(data: value.id, message: "Expected message content") }
                for part in parts {
                    if let text = part.text { content.append(.text(.init(text: text, providerMetadata: openResponsesItemMetadata(id: value.id, annotations: part.annotations ?? [], namespace: config.providerOptionsName)))) }
                }
            case .function(let value):
                guard let id = value.callId, let name = value.name, let arguments = value.arguments else { throw InvalidResponseDataError(data: value.id, message: "Incomplete function call") }
                hasToolCalls = true
                content.append(.toolCall(.init(toolCallId: id, toolName: name, input: arguments, providerMetadata: openResponsesItemMetadata(id: value.id, namespace: config.providerOptionsName))))
            case .custom(let value):
                guard let id = value.callId, let name = value.name, let input = value.input else { throw InvalidResponseDataError(data: value.id, message: "Incomplete custom tool call") }
                hasToolCalls = true
                content.append(.toolCall(.init(toolCallId: id, toolName: name, input: try openResponsesJSONString(input), providerMetadata: openResponsesItemMetadata(id: value.id, namespace: config.providerOptionsName))))
            case .other(let fields):
                if let item = Experimental_OpenResponsesExtensionItem(wire: fields), let decoded = try await config.extensions.decode(item, mode: .generate, namespace: config.providerOptionsName) {
                    content += decoded.map(\.content)
                    hasToolCalls = hasToolCalls || decoded.contains(where: \.isToolCall)
                }
            }
        }
        return .init(content: content,
                     finishReason: .init(unified: mapOpenResponsesFinishReason(finishReason: response.incompleteReason, hasToolCalls: hasToolCalls), raw: response.incompleteReason),
                     usage: openResponsesGenerationUsage(response.usage), request: .init(body: request.body),
                     response: .init(id: response.id, timestamp: response.createdAt.map { Date(timeIntervalSince1970: $0) }, modelId: response.model, headers: result.responseHeaders, body: result.rawValue),
                     warnings: request.warnings)
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let request = try await prepare(options)
        var body = request.body
        body["stream"] = true
        let response = try await postJsonToAPI(
            url: config.url, headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: config.failedResponseHandler ?? openResponsesFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openResponsesJSONSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: request.warnings))
            let task = Task {
                var state = OpenResponsesStream(config: config)
                do {
                    for try await parsed in response.value {
                        if options.includeRawChunks == true {
                            switch parsed {
                            case .success(_, let raw): continuation.yield(.raw(rawValue: try jsonValue(from: raw)))
                            case .failure(_, let raw): if let raw { continuation.yield(.raw(rawValue: try jsonValue(from: raw))) }
                            }
                        }
                        switch parsed {
                        case .failure(let error, _): continuation.yield(.error(error: .error(error)))
                        case .success(let value, _): for part in try await state.process(value) { continuation.yield(part) }
                        }
                    }
                    for part in state.flush() { continuation.yield(part) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .init(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }

    private func prepare(_ call: LanguageModelV4CallOptions) async throws -> Request {
        var warnings: [SharedV4Warning] = []
        for (name, present) in [("stopSequences", call.stopSequences != nil), ("topK", call.topK != nil), ("seed", call.seed != nil)] where present { warnings.append(.unsupported(feature: name, details: nil)) }
        var providers: [String: LanguageModelV4ProviderTool] = [:]
        for tool in call.tools ?? [] { if case .provider(let value) = tool { providers[value.name] = value } }
        let input = try await convertToOpenResponsesInput(prompt: call.prompt, config: config, providerTools: providers)
        warnings += input.warnings
        let tools = await prepareOpenResponsesTools(call.tools, choice: call.toolChoice, config: config, providerTools: providers)
        warnings += tools.warnings
        var textFormat: JSONValue?
        if case .json(let schema, let name, let description) = call.responseFormat {
            if config.structuredOutputs {
                if let schema {
                    var fields: JSONObject = ["type": "json_schema", "name": .string(name ?? "response"), "schema": schema, "strict": true]
                    if let description { fields["description"] = .string(description) }
                    textFormat = .object(fields)
                } else { textFormat = ["type": "json_object"] }
            } else { warnings.append(.unsupported(feature: "responseFormat", details: nil)) }
        }
        let options = try await parseProviderOptions(provider: config.providerOptionsName, providerOptions: call.providerOptions, schema: openResponsesLanguageModelOptions)
        var effort = options?.reasoningEffort
        if effort == nil, let reasoning = call.reasoning, isCustomReasoning(reasoning) {
            effort = reasoning == .none ? "none" : mapReasoningToProviderEffort(reasoning: reasoning, effortMap: [.minimal: "low", .low: "low", .medium: "medium", .high: "high", .xhigh: "xhigh", .max: "max"], warnings: &warnings)
        }
        var body: JSONObject = ["model": .string(modelId), "input": .array(input.input)]
        if let instructions = input.instructions { body["instructions"] = .string(instructions) }
        if let value = call.maxOutputTokens { body["max_output_tokens"] = .number(Double(value)) }
        if let value = call.temperature { body["temperature"] = .number(value) }
        if let value = call.topP { body["top_p"] = .number(value) }
        if let value = call.presencePenalty { body["presence_penalty"] = .number(value) }
        if let value = call.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if effort != nil || options?.reasoningSummary != nil {
            var reasoning: JSONObject = [:]
            if let effort { reasoning["effort"] = .string(effort) }
            if let summary = options?.reasoningSummary { reasoning["summary"] = .string(summary.rawValue) }
            body["reasoning"] = .object(reasoning)
        }
        if !tools.tools.isEmpty { body["tools"] = .array(tools.tools) }
        if let choice = tools.choice { body["tool_choice"] = choice }
        if let textFormat { body["text"] = ["format": textFormat] }
        return .init(body: body, warnings: warnings)
    }
}

func openResponsesItemMetadata(id: String?, annotations: [OpenResponsesAnnotation] = [], namespace: String) -> SharedV4ProviderMetadata {
    var value: JSONObject = [:]
    if let id { value["itemId"] = .string(id) }
    if !annotations.isEmpty { value["annotations"] = .array(annotations.map { .object($0.fields) }) }
    return [namespace: value]
}
