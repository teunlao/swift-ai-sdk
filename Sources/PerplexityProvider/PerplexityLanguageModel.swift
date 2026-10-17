import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class PerplexityLanguageModel: LanguageModelV4 {
    struct Config: Sendable {
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
        let generateId: IDGenerator
    }
    private struct Request {
        let body: JSONObject
        let warnings: [SharedV4Warning]
    }
    private let modelIdentifier: PerplexityLanguageModelId
    private let config: Config
    private static let presets: Set<String> = ["fast", "low", "medium", "high", "xhigh"]
    private static let imageRegex = try! NSRegularExpression(pattern: "^https?://.*$")

    init(modelId: PerplexityLanguageModelId, config: Config) { modelIdentifier = modelId; self.config = config }
    public var provider: String { "perplexity" }
    public var modelId: String { modelIdentifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] { ["image/*": [Self.imageRegex]] }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let request = try await prepare(options)
        let url = "\(config.baseURL)/v1/agent"
        let response = try await postJsonToAPI(
            url: url, headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(request.body), failedResponseHandler: perplexityFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: perplexityAgentResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let value = response.value
        if value.error != nil || value.status == "failed" {
            throw APICallError(message: value.error?.message ?? "Perplexity response failed", url: url,
                               requestBodyValues: request.body, statusCode: 400, responseHeaders: response.responseHeaders,
                               responseBody: try response.rawValue.map { try perplexityJSONString(jsonValue(from: $0)) }, isRetryable: false)
        }
        var content: [LanguageModelV4Content] = []
        var sourceIndexes: [String: (index: Int, hasResultId: Bool)] = [:]
        var hasFunctionCall = false
        func addSource(_ source: PerplexitySource) {
            if let previous = sourceIndexes[source.url] {
                if source.resultId != nil && !previous.hasResultId {
                    content[previous.index] = .source(source.value)
                    sourceIndexes[source.url] = (previous.index, true)
                }
            } else {
                sourceIndexes[source.url] = (content.count, source.resultId != nil)
                content.append(.source(source.value))
            }
        }
        for item in value.output {
            switch item {
            case .message(_, let parts):
                for part in parts ?? [] {
                    if part.type == "output_text", let text = part.text { content.append(.text(.init(text: text))) }
                    for annotation in part.annotations ?? [] {
                        if let url = annotation.url { addSource(.init(annotation: annotation, url: url, generateId: config.generateId)) }
                    }
                }
            case .searchResults, .fetchedContents:
                for source in try perplexityOutputSources(item, generateId: config.generateId) { addSource(source) }
            case .functionCall(let value):
                if let call = perplexityToolCall(value) { hasFunctionCall = true; content.append(.toolCall(call)) }
            case .unhandled: break
            }
        }
        return .init(
            content: content,
            finishReason: .init(unified: mapPerplexityFinishReason(status: value.status, incompleteReason: value.incomplete?.reason, hasFunctionCall: hasFunctionCall), raw: value.incomplete?.reason ?? value.status),
            usage: convertPerplexityUsage(value.usage), providerMetadata: perplexityProviderMetadata(value.usage),
            request: .init(body: request.body),
            response: .init(id: value.id, timestamp: Date(timeIntervalSince1970: value.createdAt), modelId: value.model, headers: response.responseHeaders, body: response.rawValue),
            warnings: request.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let request = try await prepare(options)
        var body = request.body
        body["stream"] = true
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/v1/agent", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: perplexityFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: perplexityAgentChunkSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: request.warnings))
            let task = Task {
                var state = PerplexityAgentStream(generateId: config.generateId)
                do {
                    for try await parsed in response.value {
                        if options.includeRawChunks == true {
                            switch parsed {
                            case .success(_, let raw): continuation.yield(.raw(rawValue: try jsonValue(from: raw)))
                            case .failure(_, let raw): if let raw { continuation.yield(.raw(rawValue: try jsonValue(from: raw))) }
                            }
                        }
                        switch parsed {
                        case .failure(let error, _):
                            state.parsingFailed()
                            continuation.yield(.error(error: .error(error)))
                        case .success(let chunk, _):
                            for part in try state.process(chunk) { continuation.yield(part) }
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
        let options = try await parseProviderOptions(provider: "perplexity", providerOptions: call.providerOptions, schema: perplexityLanguageModelOptions)
        var warnings: [SharedV4Warning] = []
        for (name, present) in [("topK", call.topK != nil), ("frequencyPenalty", call.frequencyPenalty != nil), ("presencePenalty", call.presencePenalty != nil), ("stopSequences", call.stopSequences != nil), ("seed", call.seed != nil)] where present {
            warnings.append(.unsupported(feature: name, details: nil))
        }
        let input = try convertToPerplexityInput(call.prompt)
        warnings += input.warnings
        let tools = preparePerplexityTools(tools: call.tools, toolChoice: call.toolChoice)
        warnings += tools.warnings
        var reasoning = options?.reasoning?.fields
        if reasoning == nil, let effort = call.reasoning, isCustomReasoning(effort) {
            if effort == .none { warnings.append(.unsupported(feature: "reasoning \"none\"", details: nil)) }
            else if let value = mapReasoningToProviderEffort(reasoning: effort, effortMap: [.minimal: "minimal", .low: "low", .medium: "medium", .high: "high", .xhigh: "xhigh", .max: "xhigh"], warnings: &warnings) {
                reasoning = ["effort": .string(value)]
            }
        }
        var body = options?.fields ?? [:]
        for name in ["input", "max_output_tokens", "temperature", "top_p", "reasoning", "response_format", "tools"] { body.removeValue(forKey: name) }
        body[Self.presets.contains(modelId) ? "preset" : "model"] = .string(modelId)
        body["input"] = .array(input.input)
        if let max = call.maxOutputTokens { body["max_output_tokens"] = .number(Double(max)) }
        if let temperature = call.temperature { body["temperature"] = .number(temperature) }
        if let topP = call.topP { body["top_p"] = .number(topP) }
        if let reasoning { body["reasoning"] = .object(reasoning) }
        if case .json(let schema, let name, let description) = call.responseFormat {
            if let schema {
                var value: JSONObject = ["name": .string(name ?? "response"), "schema": schema, "strict": true]
                if let description { value["description"] = .string(description) }
                body["response_format"] = ["type": "json_schema", "json_schema": .object(value)]
            } else { warnings.append(.unsupported(feature: "JSON response format without a schema", details: nil)) }
        }
        let native = (options?.tools ?? []).map { JSONValue.object($0.fields) }
        if !native.isEmpty || !tools.tools.isEmpty { body["tools"] = .array(native + tools.tools) }
        return .init(body: body, warnings: warnings)
    }
}
