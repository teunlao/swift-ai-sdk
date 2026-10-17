import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAICompletionLanguageModel: LanguageModelV4 {
    private let modelIdentifier: OpenAICompletionModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAICompletionModelId, config: OpenAIConfig) {
        modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { [:] }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options)
        let response = try await postJsonToAPI(
            url: try config.url(.init(modelId: modelId, path: "/completions")),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(prepared.body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAICompletionResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        guard let choice = response.value.choices.first else {
            throw InvalidResponseDataError(data: response.rawValue, message: "Response did not contain any choices.")
        }
        let metadata = OpenAICompletionResponseMetadata(id: response.value.id, model: response.value.model, created: response.value.created)
        var providerMetadata: SharedV4ProviderMetadata = ["openai": [:]]
        if let logprobs = choice.logprobs {
            providerMetadata["openai"]?["logprobs"] = try encodeJSON(logprobs)
        }
        return LanguageModelV4GenerateResult(
            content: [.text(.init(text: choice.text))],
            finishReason: .init(unified: OpenAICompletionFinishReasonMapper.map(choice.finishReason), raw: choice.finishReason),
            usage: convertUsage(response.value.usage),
            providerMetadata: providerMetadata,
            request: .init(body: prepared.body),
            response: .init(id: metadata.id, timestamp: metadata.timestamp, modelId: metadata.modelId, headers: response.responseHeaders, body: response.rawValue),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options)
        var body = prepared.body
        body["stream"] = .bool(true)
        body["stream_options"] = .object(["include_usage": .bool(true)])
        let url = try config.url(.init(modelId: modelId, path: "/completions"))
        let response = try await postJsonToAPI(
            url: url,
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAICompletionChunkSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let checked = try await prepareOpenAIStream(
            stream: response.value,
            getError: { if case .error(let frame) = $0 { return frame }; return nil },
            isOutput: { chunk in
                guard case .data(let data) = chunk else { return false }
                return data.choices.contains { !$0.text.isEmpty }
            },
            url: url, requestBodyValues: body, responseHeaders: response.responseHeaders
        )
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))
            let task = Task {
                var finishReason = LanguageModelV4FinishReason(unified: .other)
                var usage: OpenAICompletionUsage?
                var providerMetadata: SharedV4ProviderMetadata = ["openai": [:]]
                var isFirstChunk = true
                do {
                    for try await parsed in checked {
                        try Task.checkCancellation()
                        if options.includeRawChunks == true {
                            let raw: Any?
                            switch parsed {
                            case .success(_, let value): raw = value
                            case .failure(_, let value): raw = value
                            }
                            if let raw { continuation.yield(.raw(rawValue: try jsonValue(from: raw))) }
                        }
                        switch parsed {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error)
                            continuation.yield(.error(error: .error(error)))
                        case .success(let chunk, _):
                            switch chunk {
                            case .error(let frame):
                                finishReason = .init(unified: .error)
                                if let error = createOpenAIProviderStreamError(frame) {
                                    continuation.yield(.error(error: .providerStreamError(error)))
                                } else {
                                    continuation.yield(.error(error: .value(frame)))
                                }
                            case .data(let data):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let metadata = OpenAICompletionResponseMetadata(id: data.id, model: data.model, created: data.created)
                                    continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                                    continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                }
                                if let value = data.usage { usage = value }
                                guard let choice = data.choices.first else { continue }
                                if let reason = choice.finishReason {
                                    finishReason = .init(unified: OpenAICompletionFinishReasonMapper.map(reason), raw: reason)
                                }
                                if let logprobs = choice.logprobs {
                                    providerMetadata["openai"]?["logprobs"] = try encodeJSON(logprobs)
                                }
                                if !choice.text.isEmpty {
                                    continuation.yield(.textDelta(id: "0", delta: choice.text, providerMetadata: nil))
                                }
                            }
                        }
                    }
                    try Task.checkCancellation()
                    if !isFirstChunk { continuation.yield(.textEnd(id: "0", providerMetadata: nil)) }
                    continuation.yield(.finish(finishReason: finishReason, usage: convertUsage(usage), providerMetadata: providerMetadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return LanguageModelV4StreamResult(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }

    private func prepareRequest(_ options: LanguageModelV4CallOptions) async throws -> (body: [String: JSONValue], warnings: [SharedV4Warning]) {
        let openAI = try await parseProviderOptions(provider: "openai", providerOptions: options.providerOptions, schema: openAICompletionProviderOptionsSchema)
        let namespace = config.provider.components(separatedBy: ".")[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = namespace == "openai" ? nil : try await parseProviderOptions(provider: namespace, providerOptions: options.providerOptions, schema: openAICompletionProviderOptionsSchema)
        var warnings: [SharedV4Warning] = []
        if options.topK != nil { warnings.append(.unsupported(feature: "topK", details: nil)) }
        if options.tools?.isEmpty == false { warnings.append(.unsupported(feature: "tools", details: nil)) }
        if options.toolChoice != nil { warnings.append(.unsupported(feature: "toolChoice", details: nil)) }
        if let format = options.responseFormat, format != .text {
            warnings.append(.unsupported(feature: "responseFormat", details: "JSON response format is not supported."))
        }
        let prompt = try OpenAICompletionPromptBuilder.convert(prompt: options.prompt)
        var body: [String: JSONValue] = ["model": .string(modelId), "prompt": .string(prompt.prompt)]
        if let value = custom?.echo ?? openAI?.echo { body["echo"] = .bool(value) }
        if let value = custom?.logitBias ?? openAI?.logitBias { body["logit_bias"] = .object(value.mapValues(JSONValue.number)) }
        if let value = custom?.suffix ?? openAI?.suffix { body["suffix"] = .string(value) }
        if let value = custom?.user ?? openAI?.user { body["user"] = .string(value) }
        if let value = custom?.logprobs ?? openAI?.logprobs {
            switch value {
            case .bool(true): body["logprobs"] = .number(0)
            case .bool(false): break
            case .number(let number): body["logprobs"] = .number(Double(number))
            }
        }
        if let value = options.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if let value = options.temperature { body["temperature"] = .number(value) }
        if let value = options.topP { body["top_p"] = .number(value) }
        if let value = options.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if let value = options.presencePenalty { body["presence_penalty"] = .number(value) }
        if let value = options.seed { body["seed"] = .number(Double(value)) }
        let stops = (prompt.stopSequences ?? []) + (options.stopSequences ?? [])
        if !stops.isEmpty { body["stop"] = .array(stops.map(JSONValue.string)) }
        return (body, warnings)
    }
}

private func convertUsage(_ usage: OpenAICompletionUsage?) -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    return .init(
        inputTokens: .init(total: usage.promptTokens, noCache: usage.promptTokens),
        outputTokens: .init(total: usage.completionTokens, text: usage.completionTokens),
        raw: usage.raw
    )
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
}
