import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAICompletionLanguageModel: LanguageModelV3 {
    private let modelIdentifier: OpenAICompletionModelId
    private let config: OpenAIConfig
    private let providerOptionsName: String

    public init(modelId: OpenAICompletionModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
        if let prefix = config.provider.split(separator: ".").first {
            self.providerOptionsName = String(prefix)
        } else {
            self.providerOptionsName = "openai"
        }
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { [:] }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/completions")),
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAICompletionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let value = response.value
        guard let choice = value.choices.first else {
            throw UnsupportedFunctionalityError(functionality: "No completion choices returned")
        }

        let usage = convertOpenAICompletionUsage(value.usage)

        var providerMetadata: SharedV3ProviderMetadata? = nil
	        if let logprobs = choice.logprobs, let logprobsJSON = try? JSONEncoder().encodeToJSONValue(logprobs) {
	            providerMetadata = ["openai": ["logprobs": logprobsJSON]]
	        }

	        let rawFinishReason = choice.finishReason
	        let finishReason = LanguageModelV3FinishReason(
	            unified: OpenAICompletionFinishReasonMapper.map(rawFinishReason),
	            raw: rawFinishReason
	        )
	        let metadata = OpenAICompletionResponseMetadata(id: value.id, model: value.model, created: value.created)

        let content: [LanguageModelV3Content] = [
            .text(LanguageModelV3Text(text: choice.text))
        ]

        return LanguageModelV3GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage,
            providerMetadata: providerMetadata,
            request: LanguageModelV3RequestInfo(body: prepared.body),
            response: LanguageModelV3ResponseInfo(
                id: metadata.id,
                timestamp: metadata.timestamp,
                modelId: metadata.modelId,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        body["stream_options"] = .object(["include_usage": .bool(true)])

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let eventStream = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/completions")),
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAICompletionChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

	        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
	            continuation.yield(.streamStart(warnings: prepared.warnings))

	            Task {
	                var finishReason: LanguageModelV3FinishReason = .init(unified: .other, raw: nil)
	                var usage = LanguageModelV3Usage()
	                var logprobsJSON: JSONValue? = nil
	                var isFirstChunk = true

                do {
                    for try await parseResult in eventStream.value {
                        if options.includeRawChunks == true {
                            let rawJSON: JSONValue?
                            switch parseResult {
                            case .success(_, let raw):
                                rawJSON = try? jsonValue(from: raw)
                            case .failure(_, let raw):
                                rawJSON = raw.flatMap { try? jsonValue(from: $0) }
                            }
                            if let rawJSON {
                                continuation.yield(.raw(rawValue: rawJSON))
                            }
                        }

	                        switch parseResult {
	                        case .failure(let error, _):
	                            finishReason = .init(unified: .error, raw: nil)
	                            continuation.yield(.error(error: .string(String(describing: error))))
	                        case .success(let chunk, _):
	                            switch chunk {
	                            case .error(let errorData):
	                                finishReason = .init(unified: .error, raw: nil)
	                                if let errorValue = try? JSONEncoder().encodeToJSONValue(errorData) {
	                                    continuation.yield(.error(error: errorValue))
	                                } else {
	                                    continuation.yield(.error(error: .string(errorData.error.message)))
	                                }
	                            case .data(let data):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let metadata = OpenAICompletionResponseMetadata(id: data.id, model: data.model, created: data.created)
                                    continuation.yield(.responseMetadata(id: metadata.id, modelId: metadata.modelId, timestamp: metadata.timestamp))
                                    continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                }

                                if let usageValue = data.usage {
                                    usage = convertOpenAICompletionUsage(usageValue)
                                }

	                                guard let choice = data.choices.first else { continue }

	                                if let finish = choice.finishReason {
	                                    finishReason = LanguageModelV3FinishReason(
	                                        unified: OpenAICompletionFinishReasonMapper.map(finish),
	                                        raw: finish
	                                    )
	                                }

                                if let logprobs = choice.logprobs {
                                    logprobsJSON = try? JSONEncoder().encodeToJSONValue(logprobs)
                                }

                                if let text = choice.text, !text.isEmpty {
                                    continuation.yield(.textDelta(id: "0", delta: text, providerMetadata: nil))
                                }
                            }
                        }
                    }

                    if !isFirstChunk {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                    }

                    let providerMetadata: SharedV3ProviderMetadata? = logprobsJSON.map { ["openai": ["logprobs": $0]] }
                    continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: body),
            response: LanguageModelV3StreamResponseInfo(headers: eventStream.responseHeaders)
        )
    }
    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
    }

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }
        if let tools = options.tools, !tools.isEmpty {
            warnings.append(.unsupported(feature: "tools", details: nil))
        }
        if options.toolChoice != nil {
            warnings.append(.unsupported(feature: "toolChoice", details: nil))
        }
        if let responseFormat = options.responseFormat, responseFormat != .text {
            warnings.append(.unsupported(feature: "responseFormat", details: "JSON response format is not supported."))
        }

        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openAICompletionProviderOptionsSchema
        )
        let providerSpecificOptions: OpenAICompletionProviderOptions?
        if providerOptionsName != "openai" {
            providerSpecificOptions = try await parseProviderOptions(
                provider: providerOptionsName,
                providerOptions: options.providerOptions,
                schema: openAICompletionProviderOptionsSchema
            )
        } else {
            providerSpecificOptions = nil
        }

        let combinedOptions = merge(first: openAIOptions, second: providerSpecificOptions)
        let promptConversion = try OpenAICompletionPromptBuilder.convert(prompt: options.prompt)

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "prompt": .string(promptConversion.prompt)
        ]

        if let maxTokens = options.maxOutputTokens {
            body["max_tokens"] = .number(Double(maxTokens))
        }
        if let temperature = options.temperature {
            body["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            body["top_p"] = .number(topP)
        }
        if let frequencyPenalty = options.frequencyPenalty {
            body["frequency_penalty"] = .number(frequencyPenalty)
        }
        if let presencePenalty = options.presencePenalty {
            body["presence_penalty"] = .number(presencePenalty)
        }
        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }

        var stopValues: [JSONValue] = []
        if let promptStops = promptConversion.stopSequences {
            stopValues.append(contentsOf: promptStops.map(JSONValue.string))
        }
        if let userStops = options.stopSequences, !userStops.isEmpty {
            stopValues.append(contentsOf: userStops.map(JSONValue.string))
        }
        if !stopValues.isEmpty {
            body["stop"] = .array(stopValues)
        }

        if let opt = combinedOptions {
            if let echo = opt.echo { body["echo"] = .bool(echo) }
            if let logitBias = opt.logitBias {
                body["logit_bias"] = .object(logitBias.mapValues(JSONValue.number))
            }
            if let suffix = opt.suffix { body["suffix"] = .string(suffix) }
            if let user = opt.user { body["user"] = .string(user) }
            if let logprobs = opt.logprobs { body["logprobs"] = logprobs.jsonValue }
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func merge(first: OpenAICompletionProviderOptions?, second: OpenAICompletionProviderOptions?) -> OpenAICompletionProviderOptions? {
        guard first != nil || second != nil else { return nil }
        var result = OpenAICompletionProviderOptions()

        if let first = first {
            result.echo = first.echo
            result.logitBias = first.logitBias
            result.suffix = first.suffix
            result.user = first.user
            result.logprobs = first.logprobs
        }

        if let second = second {
            if let echo = second.echo { result.echo = echo }
            if let bias = second.logitBias { result.logitBias = bias }
            if let suffix = second.suffix { result.suffix = suffix }
            if let user = second.user { result.user = user }
            if let logprobs = second.logprobs { result.logprobs = logprobs }
        }

        if result.echo == nil && result.logitBias == nil && result.suffix == nil && result.user == nil && result.logprobs == nil {
            return nil
        }

        return result
    }
}

private func convertOpenAICompletionUsage(_ usage: OpenAICompletionUsage?) -> LanguageModelV3Usage {
    // Port of `packages/openai/src/completion/convert-openai-completion-usage.ts`
    guard let usage else {
        return LanguageModelV3Usage()
    }

    let promptTokens = usage.promptTokens
    let completionTokens = usage.completionTokens

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: promptTokens,
            noCache: promptTokens,
            cacheRead: nil,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: completionTokens,
            text: completionTokens,
            reasoning: nil
        ),
        raw: try? JSONEncoder().encodeToJSONValue(usage)
    )
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}
