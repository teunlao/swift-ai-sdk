import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct MoonshotAIChatURLOptions: Sendable {
    public let modelId: String
    public let path: String
    public init(modelId: String, path: String) { self.modelId = modelId; self.path = path }
}
public struct MoonshotAIChatConfig: Sendable {
    public let provider: String
    public let headers: (@Sendable () throws -> [String: String?])?
    public let url: @Sendable (MoonshotAIChatURLOptions) -> String
    public let fetch: FetchFunction?
    public let includeUsage: Bool
    public let supportsStructuredOutputs: Bool
    public init(provider: String, headers: (@Sendable () throws -> [String: String?])? = nil, url: @escaping @Sendable (MoonshotAIChatURLOptions) -> String, fetch: FetchFunction? = nil, includeUsage: Bool = false, supportsStructuredOutputs: Bool = false) {
        self.provider = provider; self.headers = headers; self.url = url; self.fetch = fetch; self.includeUsage = includeUsage; self.supportsStructuredOutputs = supportsStructuredOutputs
    }
}

public final class MoonshotAIChatLanguageModel: LanguageModelV4 {
    public let modelId: String
    public var provider: String { config.provider }
    private let config: MoonshotAIChatConfig
    private var optionsName: String { provider.components(separatedBy: ".")[0].trimmingCharacters(in: .whitespacesAndNewlines) }
    public init(modelId: MoonshotAIChatModelId, config: MoonshotAIChatConfig) { self.modelId = modelId.rawValue; self.config = config }
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { let regex = try NSRegularExpression(pattern: "^ms://"); return ["image/*": [regex], "video/*": [regex]] }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareMoonshotRequest(modelId: modelId, providerName: optionsName, structuredOutputs: config.supportsStructuredOutputs, options: options)
        let response = try await postJsonToAPI(url: config.url(.init(modelId: modelId, path: "/chat/completions")), headers: combineHeaders(try config.headers?(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }, body: JSONValue.object(prepared.body), failedResponseHandler: moonshotFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: moonshotResponseSchema), isAborted: options.abortSignal, fetch: config.fetch)
        guard let choice = response.value.choices.first else { throw InvalidResponseDataError(data: response.rawValue, message: "Moonshot response contains no choices") }
        var content: [LanguageModelV4Content] = []
        if let reasoning = choice.message.reasoning_content, !reasoning.isEmpty { content.append(.reasoning(.init(text: reasoning))) }
        for call in choice.message.tool_calls ?? [] { content.append(.toolCall(.init(toolCallId: call.id?.isEmpty == false ? call.id! : generateID(), toolName: call.function.name, input: call.function.arguments))) }
        if let text = choice.message.content, !text.isEmpty { content.append(.text(.init(text: text))) }
        var metadata: [String: JSONValue] = [:]
        if let logprobs = choice.logprobs { metadata["logprobs"] = logprobs.json }
        if let object = response.value.object { metadata["responseObject"] = .string(object.rawValue) }
        if let index = choice.index { metadata["choiceIndex"] = .number(index) }
        if let role = choice.message.role { metadata["messageRole"] = .string(role.rawValue) }
        if let calls = choice.message.tool_calls { metadata["toolCallTypes"] = .array(calls.compactMap { $0.type.map { .string($0.rawValue) } }) }
        return .init(content: content, finishReason: .init(unified: mapMoonshotAIFinishReason(choice.finish_reason), raw: choice.finish_reason), usage: convertMoonshotAIChatUsage(response.value.usage?.raw), providerMetadata: [optionsName: metadata], request: .init(body: prepared.body), response: .init(id: response.value.id, timestamp: response.value.created.map(Date.init(timeIntervalSince1970:)), modelId: response.value.model, headers: response.responseHeaders, body: response.rawValue), warnings: prepared.warnings)
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareMoonshotRequest(modelId: modelId, providerName: optionsName, structuredOutputs: config.supportsStructuredOutputs, options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        if config.includeUsage { body["stream_options"] = .object(["include_usage": .bool(true)]) }
        let response = try await postJsonToAPI(url: config.url(.init(modelId: modelId, path: "/chat/completions")), headers: combineHeaders(try config.headers?(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }, body: JSONValue.object(body), failedResponseHandler: moonshotFailedResponseHandler, successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: moonshotChunkSchema), isAborted: options.abortSignal, fetch: config.fetch)
        let name = optionsName
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))
            let producer = Task {
                let tracker = StreamingToolCallTracker(enqueue: { continuation.yield($0) })
                var finish = LanguageModelV4FinishReason(unified: .other, raw: nil)
                var rootUsage: JSONValue?, choiceUsage: JSONValue?
                var logprobs: [JSONValue] = []
                var first = true, reasoning = false, text = false
                var responseObject: String?, role: String?
                var choiceIndex: Double?
                var toolTypes: [Int: String] = [:]
                do {
                    for try await parsed in response.value {
                        try Task.checkCancellation()
                        if options.includeRawChunks == true { continuation.yield(.raw(rawValue: moonshotRawChunk(parsed))) }
                        switch parsed {
                        case .failure(let error, _):
                            finish = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .error(error)))
                        case .success(.error(let error), _):
                            finish = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .providerStreamError(moonshotStreamError(error, data: try moonshotJSONValue(error)))))
                        case .success(.body(let chunk), _):
                            if first {
                                first = false
                                continuation.yield(.responseMetadata(id: chunk.id, modelId: chunk.model, timestamp: chunk.created.map(Date.init(timeIntervalSince1970:))))
                            }
                            if let usage = chunk.usage { rootUsage = usage.raw }
                            if let object = chunk.object { responseObject = object.rawValue }
                            guard let choice = chunk.choices.first else { continue }
                            if let usage = choice.usage { choiceUsage = usage.raw }
                            if let index = choice.index { choiceIndex = index }
                            if let reason = choice.finish_reason { finish = .init(unified: mapMoonshotAIFinishReason(reason), raw: reason) }
                            if let content = choice.logprobs?.content { logprobs.append(contentsOf: content.map(\.json)) }
                            guard let delta = choice.delta else { continue }
                            if let value = delta.role { role = value.rawValue }
                            if let value = delta.reasoning_content, !value.isEmpty {
                                if !reasoning { continuation.yield(.reasoningStart(id: "reasoning-0", providerMetadata: nil)); reasoning = true }
                                continuation.yield(.reasoningDelta(id: "reasoning-0", delta: value, providerMetadata: nil))
                            }
                            if let value = delta.content, !value.isEmpty {
                                if !text { continuation.yield(.textStart(id: "txt-0", providerMetadata: nil)); text = true }
                                if reasoning { continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil)); reasoning = false }
                                continuation.yield(.textDelta(id: "txt-0", delta: value, providerMetadata: nil))
                            }
                            if let calls = delta.tool_calls, !calls.isEmpty {
                                if reasoning { continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil)); reasoning = false }
                                for (position, call) in calls.enumerated() {
                                    let index = call.index ?? position
                                    if let type = call.type { toolTypes[index] = type.rawValue }
                                    try tracker.processDelta(.init(index: index, id: call.id, type: call.type?.rawValue, function: .init(name: call.function.name, arguments: call.function.arguments)))
                                }
                            }
                        }
                    }
                    if reasoning { continuation.yield(.reasoningEnd(id: "reasoning-0", providerMetadata: nil)) }
                    if text { continuation.yield(.textEnd(id: "txt-0", providerMetadata: nil)) }
                    tracker.flush()
                    var metadata: [String: JSONValue] = [:]
                    if !logprobs.isEmpty { metadata["logprobs"] = .object(["content": .array(logprobs)]) }
                    if let responseObject { metadata["responseObject"] = .string(responseObject) }
                    if let choiceIndex { metadata["choiceIndex"] = .number(choiceIndex) }
                    if let role { metadata["messageRole"] = .string(role) }
                    if !toolTypes.isEmpty { metadata["toolCallTypes"] = .array(toolTypes.keys.sorted().map { .string(toolTypes[$0]!) }) }
                    continuation.yield(.finish(finishReason: finish, usage: convertMoonshotAIChatUsage(rootUsage ?? choiceUsage), providerMetadata: [name: metadata]))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
        return .init(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }
}

private func moonshotRawChunk(_ parsed: ParseJSONResult<MoonshotChunk>) -> JSONValue {
    switch parsed { case .success(_, let raw): return (try? jsonValue(from: raw)) ?? .null; case .failure(_, let raw): return raw.flatMap { try? jsonValue(from: $0) } ?? .null }
}
private func moonshotStreamError(_ payload: MoonshotAIErrorData, data: JSONValue) -> ProviderStreamError {
    let status: Int?, retryable: Bool?
    switch payload.error.type {
    case "rate_limit_exceeded", "rate_limit_error": status = 429; retryable = true
    case "server_error", "api_error", "internal_server_error": status = 500; retryable = true
    case "overloaded_error", "service_unavailable": status = 503; retryable = true
    case "timeout", "timeout_error": status = 504; retryable = true
    case "authentication_error", "invalid_api_key": status = 401; retryable = false
    case "permission_error": status = 403; retryable = false
    case "not_found_error", "model_not_found": status = 404; retryable = false
    case "bad_request", "context_length_exceeded", "invalid_request_error": status = 400; retryable = false
    default: status = nil; retryable = nil
    }
    return createProviderStreamError(message: payload.error.message, type: payload.error.type, code: payload.error.code.map(ProviderStreamError.Code.string), statusCode: status, isRetryable: retryable, data: data)
}
