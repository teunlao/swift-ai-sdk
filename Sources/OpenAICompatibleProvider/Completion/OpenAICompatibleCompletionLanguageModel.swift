import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleCompletionConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let fetch: FetchFunction?
    public let includeUsage: Bool
    public let errorConfiguration: OpenAICompatibleErrorConfiguration

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.includeUsage = includeUsage
        self.errorConfiguration = errorConfiguration
    }
}

public final class OpenAICompatibleCompletionLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleCompletionModelId
    private let config: OpenAICompatibleCompletionConfig
    private let providerOptionsName: String

    public init(modelId: OpenAICompatibleCompletionModelId, config: OpenAICompatibleCompletionConfig) {
        self.modelIdentifier = modelId
        self.config = config
        self.providerOptionsName = config.provider.split(separator: ".").first.map(String.init) ?? ""
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] { [:] }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/completions")),
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAICompatibleCompletionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let choice = response.value.choices.first else {
            throw APICallError(
                message: "OpenAI-compatible completion response did not include choices.",
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/completions")),
                requestBodyValues: prepared.body
            )
        }

        var content: [LanguageModelV3Content] = []

        if let text = choice.text, !text.isEmpty {
            content.append(.text(LanguageModelV3Text(text: text)))
        }

        let usage = mapUsage(response.value.usage)
        let rawFinishReason = choice.finishReason
        let finishReason = LanguageModelV3FinishReason(
            unified: mapOpenAICompatibleFinishReason(rawFinishReason),
            raw: rawFinishReason
        )
        let metadata = responseMetadata(id: response.value.id, model: response.value.model, created: response.value.created)

        let providerMetadata = makeProviderMetadata(usage: response.value.usage)

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
        if config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }

        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let eventStream = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/completions")),
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAICompatibleCompletionChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            Task {
                var finishReason: LanguageModelV3FinishReason = .init(unified: .other, raw: nil)
                var usage = LanguageModelV3Usage()
                var latestUsage: OpenAICompatibleCompletionUsage? = nil
                var isFirstChunk = true
                var isActiveText = false

                do {
                    for try await parseResult in eventStream.value {
                        if options.includeRawChunks == true, let rawJSON = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: rawJSON))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .string(String(describing: error))))
                        case .success(let chunk, _):
                            switch chunk {
                            case .error(let errorData):
                                finishReason = .init(unified: .error, raw: nil)
                                if let encoded = try? JSONEncoder().encodeToJSONValue(errorData) {
                                    continuation.yield(.error(error: encoded))
                                } else {
                                    continuation.yield(.error(error: .string(errorData.error.message)))
                                }
                            case .data(let data):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let meta = responseMetadata(id: data.id, model: data.model, created: data.created)
                                    continuation.yield(.responseMetadata(id: meta.id, modelId: meta.modelId, timestamp: meta.timestamp))
                                }

                                if let usageValue = data.usage {
                                    latestUsage = usageValue
                                    usage = mapUsage(usageValue)
                                }

                                guard let choice = data.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = LanguageModelV3FinishReason(
                                        unified: mapOpenAICompatibleFinishReason(finish),
                                        raw: finish
                                    )
                                }

                                if let textDelta = choice.textDelta, !textDelta.isEmpty {
                                    if !isActiveText {
                                        isActiveText = true
                                        continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                    }
                                    continuation.yield(.textDelta(id: "0", delta: textDelta, providerMetadata: nil))
                                }
                            }
                        }
                    }

                    if isActiveText {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                    }

                    continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: makeProviderMetadata(usage: latestUsage)))
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
        if options.tools != nil {
            warnings.append(.unsupported(feature: "tools", details: nil))
        }
        if options.toolChoice != nil {
            warnings.append(.unsupported(feature: "toolChoice", details: nil))
        }
        if let responseFormat = options.responseFormat, case .json = responseFormat {
            warnings.append(.unsupported(feature: "responseFormat", details: "JSON response format is not supported."))
        }

        let baseOptions = try await parseProviderOptions(
            provider: "openai-compatible",
            providerOptions: options.providerOptions,
            schema: openAICompatibleCompletionProviderOptionsSchema
        ) ?? OpenAICompatibleCompletionProviderOptions()

        let providerSpecific = try await parseProviderOptions(
            provider: providerOptionsName,
            providerOptions: options.providerOptions,
            schema: openAICompatibleCompletionProviderOptionsSchema
        ) ?? OpenAICompatibleCompletionProviderOptions()

        var mergedOptions = baseOptions
        if let echo = providerSpecific.echo {
            mergedOptions.echo = echo
        }
        if let logitBias = providerSpecific.logitBias {
            mergedOptions.logitBias = logitBias
        }
        if let suffix = providerSpecific.suffix {
            mergedOptions.suffix = suffix
        }
        if let user = providerSpecific.user {
            mergedOptions.user = user
        }

        let conversion = try OpenAICompatibleCompletionPromptConverter.convert(prompt: options.prompt)
        var stopSequences = conversion.stopSequences ?? []
        if let userStops = options.stopSequences {
            stopSequences.append(contentsOf: userStops)
        }

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "prompt": .string(conversion.prompt)
        ]

        let providerSpecificRaw = options.providerOptions?[providerOptionsName] ?? [:]
        let forwardedOptions = providerSpecificRaw.filter { key, _ in
            !["echo", "logitBias", "suffix", "user"].contains(key)
        }

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
        if !stopSequences.isEmpty {
            body["stop"] = .array(stopSequences.map(JSONValue.string))
        }

        if let echo = mergedOptions.echo {
            body["echo"] = .bool(echo)
        }
        if let logitBias = mergedOptions.logitBias {
            body["logit_bias"] = .object(logitBias.mapValues(JSONValue.number))
        }
        if let suffix = mergedOptions.suffix {
            body["suffix"] = .string(suffix)
        }
        if let user = mergedOptions.user {
            body["user"] = .string(user)
        }

        for (key, value) in forwardedOptions {
            body[key] = value
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func mapUsage(_ usage: OpenAICompatibleCompletionUsage?) -> LanguageModelV3Usage {
        guard let usage else { return LanguageModelV3Usage() }

        let promptTokens = usage.promptTokens ?? 0
        let completionTokens = usage.completionTokens ?? 0

        return LanguageModelV3Usage(
            inputTokens: .init(total: promptTokens, noCache: promptTokens),
            outputTokens: .init(total: completionTokens, text: completionTokens, reasoning: nil),
            raw: try? jsonValue(from: usage)
        )
    }

    private func makeProviderMetadata(usage: OpenAICompatibleCompletionUsage?) -> SharedV3ProviderMetadata? {
        var metadata: SharedV3ProviderMetadata = [:]
        var entry: [String: JSONValue] = [:]
        if let promptTokens = usage?.promptTokensDetails?.cachedTokens {
            entry["cachedTokens"] = .number(Double(promptTokens))
        }
        if let entryValue = usage?.completionTokensDetails?.acceptedPredictionTokens {
            entry["acceptedPredictionTokens"] = .number(Double(entryValue))
        }
        if let entryValue = usage?.completionTokensDetails?.rejectedPredictionTokens {
            entry["rejectedPredictionTokens"] = .number(Double(entryValue))
        }
        if entry.isEmpty {
            return nil
        }
        metadata[providerOptionsName] = entry
        return metadata
    }

    private func responseMetadata(id: String?, model: String?, created: Double?) -> (id: String?, modelId: String?, timestamp: Date?) {
        (id, model, created.map { Date(timeIntervalSince1970: $0) })
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private struct OpenAICompatibleCompletionResponse: Codable {
    struct Choice: Codable {
        let text: String?
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case text
            case finishReason = "finish_reason"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: OpenAICompatibleCompletionUsage?
}

private struct OpenAICompatibleCompletionUsage: Codable {
    struct PromptTokensDetails: Codable {
        let cachedTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    struct CompletionTokensDetails: Codable {
        let acceptedPredictionTokens: Int?
        let rejectedPredictionTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case acceptedPredictionTokens = "accepted_prediction_tokens"
            case rejectedPredictionTokens = "rejected_prediction_tokens"
        }
    }

    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let promptTokensDetails: PromptTokensDetails?
    let completionTokensDetails: CompletionTokensDetails?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
    }
}

private struct OpenAICompatibleCompletionStreamChunk: Codable {
    struct Choice: Codable {
        let textDelta: String?
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case textDelta = "text"
            case finishReason = "finish_reason"
        }
    }

    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: OpenAICompatibleCompletionUsage?
}

private enum OpenAICompatibleCompletionStreamEvent: Codable {
    case data(OpenAICompatibleCompletionStreamChunk)
    case error(OpenAICompatibleErrorData)

    private enum CodingKeys: String, CodingKey { case error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.error) {
            self = .error(try OpenAICompatibleErrorData(from: decoder))
        } else {
            self = .data(try OpenAICompatibleCompletionStreamChunk(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .data(let chunk):
            try chunk.encode(to: encoder)
        case .error(let error):
            try error.encode(to: encoder)
        }
    }
}

private let openAICompatibleCompletionResponseSchema = FlexibleSchema(
    Schema<OpenAICompatibleCompletionResponse>.codable(
        OpenAICompatibleCompletionResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let openAICompatibleCompletionChunkSchema = FlexibleSchema(
    Schema<OpenAICompatibleCompletionStreamEvent>.codable(
        OpenAICompatibleCompletionStreamEvent.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private extension ParseJSONResult where Output == OpenAICompatibleCompletionStreamEvent {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}
