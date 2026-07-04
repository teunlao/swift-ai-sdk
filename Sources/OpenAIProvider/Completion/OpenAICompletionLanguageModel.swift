import Foundation
import AISDKProvider
import AISDKProviderUtils

private struct OpenAICompletionLanguageModelCore: Sendable {
    private let modelIdentifier: OpenAICompletionModelId
    private let config: OpenAIConfig
    private let providerOptionsName: String

    init(modelId: OpenAICompletionModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
        self.providerOptionsName = config.provider
            .split(separator: ".", maxSplits: 1)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "openai"
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }

    var supportedUrls: [String: [NSRegularExpression]] { [:] }

    func doGenerate(options: OpenAICompletionCallSettings) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }

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

        let metadata = OpenAICompletionResponseMetadata(
            id: value.id,
            model: value.model,
            created: value.created
        )

        return LanguageModelV4GenerateResult(
            content: [
                .text(LanguageModelV4Text(text: choice.text))
            ],
            finishReason: LanguageModelV4FinishReason(
                unified: OpenAICompletionFinishReasonMapper.mapV4(choice.finishReason),
                raw: choice.finishReason
            ),
            usage: convertOpenAICompletionUsageToV4(value.usage),
            providerMetadata: openAICompletionProviderMetadata(logprobs: choice.logprobs),
            request: LanguageModelV4RequestInfo(body: prepared.body),
            response: LanguageModelV4ResponseInfo(
                id: metadata.id,
                timestamp: metadata.timestamp,
                modelId: metadata.modelId,
                headers: response.responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )
    }

    func doStream(options: OpenAICompletionCallSettings) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        body["stream_options"] = .object(["include_usage": .bool(true)])

        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) })
            .compactMapValues { $0 }
        let url = config.url(.init(modelId: modelIdentifier.rawValue, path: "/completions"))

        let eventStream = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAICompletionChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let checkedStream: AsyncThrowingStream<ParseJSONResult<OpenAICompletionChunk>, Error>
        if options.throwsPreOutputStreamErrors {
            checkedStream = try await throwIfOpenAICompletionStreamErrorBeforeOutput(
                stream: eventStream.value,
                url: url,
                requestBodyValues: body,
                responseHeaders: eventStream.responseHeaders
            )
        } else {
            checkedStream = eventStream.value
        }

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            let task = Task {
                var finishReason = LanguageModelV4FinishReason(unified: .other, raw: nil)
                var usage = LanguageModelV4Usage()
                var providerMetadata: SharedV4ProviderMetadata = ["openai": [:]]
                var isFirstChunk = true

                do {
                    for try await parseResult in checkedStream {
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
                            finishReason = LanguageModelV4FinishReason(unified: .error, raw: nil)
                            continuation.yield(.error(error: .string(String(describing: error))))

                        case .success(let chunk, _):
                            switch chunk {
                            case .error(let errorData):
                                finishReason = LanguageModelV4FinishReason(unified: .error, raw: nil)
                                if let errorValue = try? JSONEncoder().encodeToJSONValue(errorData) {
                                    continuation.yield(.error(error: errorValue))
                                } else {
                                    continuation.yield(.error(error: .string(errorData.error.message)))
                                }

                            case .data(let data):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let metadata = OpenAICompletionResponseMetadata(
                                        id: data.id,
                                        model: data.model,
                                        created: data.created
                                    )
                                    continuation.yield(.responseMetadata(
                                        id: metadata.id,
                                        modelId: metadata.modelId,
                                        timestamp: metadata.timestamp
                                    ))
                                    continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                }

                                if let usageValue = data.usage {
                                    usage = convertOpenAICompletionUsageToV4(usageValue)
                                }

                                guard let choice = data.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = LanguageModelV4FinishReason(
                                        unified: OpenAICompletionFinishReasonMapper.mapV4(finish),
                                        raw: finish
                                    )
                                }

                                if let logprobs = choice.logprobs,
                                   let logprobsJSON = try? JSONEncoder().encodeToJSONValue(logprobs) {
                                    providerMetadata["openai"]?["logprobs"] = logprobsJSON
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

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return LanguageModelV4StreamResult(
            stream: stream,
            request: LanguageModelV4RequestInfo(body: body),
            response: LanguageModelV4StreamResponseInfo(headers: eventStream.responseHeaders)
        )
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
    }

    private func prepareRequest(options: OpenAICompletionCallSettings) async throws -> PreparedRequest {
        var warnings: [SharedV4Warning] = []

        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }
        if options.hasTools {
            warnings.append(.unsupported(feature: "tools", details: nil))
        }
        if options.hasToolChoice {
            warnings.append(.unsupported(feature: "toolChoice", details: nil))
        }
        if options.hasUnsupportedResponseFormat {
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
        let promptConversion: (prompt: String, stopSequences: [String]?)
        switch options.prompt {
        case .v3(let prompt):
            promptConversion = try OpenAICompletionPromptBuilder.convert(prompt: prompt)
        case .v4(let prompt):
            promptConversion = try OpenAICompletionPromptBuilder.convert(prompt: prompt)
        }

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
            if let logprobs = opt.logprobs {
                switch logprobs {
                case .bool(let value):
                    if value {
                        body["logprobs"] = .number(0)
                    }
                case .number(let value):
                    body["logprobs"] = .number(value)
                }
            }
        }

        return PreparedRequest(body: body, warnings: warnings)
    }

    private func merge(
        first: OpenAICompletionProviderOptions?,
        second: OpenAICompletionProviderOptions?
    ) -> OpenAICompletionProviderOptions? {
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

        if result.echo == nil,
           result.logitBias == nil,
           result.suffix == nil,
           result.user == nil,
           result.logprobs == nil {
            return nil
        }

        return result
    }
}

private enum OpenAICompletionPromptInput: Sendable {
    case v3(LanguageModelV3Prompt)
    case v4(LanguageModelV4Prompt)
}

private struct OpenAICompletionCallSettings: Sendable {
    let prompt: OpenAICompletionPromptInput
    let maxOutputTokens: Int?
    let temperature: Double?
    let stopSequences: [String]?
    let topP: Double?
    let topK: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let seed: Int?
    let hasTools: Bool
    let hasToolChoice: Bool
    let hasUnsupportedResponseFormat: Bool
    let includeRawChunks: Bool?
    let throwsPreOutputStreamErrors: Bool
    let abortSignal: (@Sendable () -> Bool)?
    let headers: SharedV4Headers?
    let providerOptions: SharedV4ProviderOptions?

    init(v3 options: LanguageModelV3CallOptions) {
        self.prompt = .v3(options.prompt)
        self.maxOutputTokens = options.maxOutputTokens
        self.temperature = options.temperature
        self.stopSequences = options.stopSequences
        self.topP = options.topP
        self.topK = options.topK
        self.presencePenalty = options.presencePenalty
        self.frequencyPenalty = options.frequencyPenalty
        self.seed = options.seed
        self.hasTools = options.tools?.isEmpty == false
        self.hasToolChoice = options.toolChoice != nil
        if let responseFormat = options.responseFormat, responseFormat != .text {
            self.hasUnsupportedResponseFormat = true
        } else {
            self.hasUnsupportedResponseFormat = false
        }
        self.includeRawChunks = options.includeRawChunks
        self.throwsPreOutputStreamErrors = false
        self.abortSignal = options.abortSignal
        self.headers = options.headers
        self.providerOptions = options.providerOptions
    }

    init(v4 options: LanguageModelV4CallOptions) {
        self.prompt = .v4(options.prompt)
        self.maxOutputTokens = options.maxOutputTokens
        self.temperature = options.temperature
        self.stopSequences = options.stopSequences
        self.topP = options.topP
        self.topK = options.topK
        self.presencePenalty = options.presencePenalty
        self.frequencyPenalty = options.frequencyPenalty
        self.seed = options.seed
        self.hasTools = options.tools?.isEmpty == false
        self.hasToolChoice = options.toolChoice != nil
        if let responseFormat = options.responseFormat, responseFormat != .text {
            self.hasUnsupportedResponseFormat = true
        } else {
            self.hasUnsupportedResponseFormat = false
        }
        self.includeRawChunks = options.includeRawChunks
        self.throwsPreOutputStreamErrors = true
        self.abortSignal = options.abortSignal
        self.headers = options.headers
        self.providerOptions = options.providerOptions
    }
}

public final class OpenAICompletionLanguageModel: LanguageModelV3 {
    private let core: OpenAICompletionLanguageModelCore

    public init(modelId: OpenAICompletionModelId, config: OpenAIConfig) {
        self.core = OpenAICompletionLanguageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { core.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let result = try await core.doGenerate(options: OpenAICompletionCallSettings(v3: options))
        return try convertLanguageModelV4GenerateResultToV3(result)
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let result = try await core.doStream(options: OpenAICompletionCallSettings(v3: options))
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await part in result.stream {
                        continuation.yield(try convertLanguageModelV4StreamPartToV3(part))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: result.request.map(convertLanguageModelV4RequestInfoToV3),
            response: result.response.map(convertLanguageModelV4StreamResponseInfoToV3)
        )
    }

    func asV4() -> OpenAICompletionLanguageModelV4 {
        OpenAICompletionLanguageModelV4(core: core)
    }
}

public final class OpenAICompletionLanguageModelV4: LanguageModelV4 {
    private let core: OpenAICompletionLanguageModelCore

    public init(modelId: OpenAICompletionModelId, config: OpenAIConfig) {
        self.core = OpenAICompletionLanguageModelCore(modelId: modelId, config: config)
    }

    fileprivate init(core: OpenAICompletionLanguageModelCore) {
        self.core = core
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { core.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        try await core.doGenerate(options: OpenAICompletionCallSettings(v4: options))
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        try await core.doStream(options: OpenAICompletionCallSettings(v4: options))
    }
}

private func openAICompletionProviderMetadata(logprobs: OpenAICompletionLogprobs?) -> SharedV4ProviderMetadata {
    var metadata: SharedV4ProviderMetadata = ["openai": [:]]
    if let logprobs, let logprobsJSON = try? JSONEncoder().encodeToJSONValue(logprobs) {
        metadata["openai"]?["logprobs"] = logprobsJSON
    }
    return metadata
}

private func convertOpenAICompletionUsageToV4(_ usage: OpenAICompletionUsage?) -> LanguageModelV4Usage {
    guard let usage else {
        return LanguageModelV4Usage()
    }

    let promptTokens = usage.promptTokens
    let completionTokens = usage.completionTokens

    return LanguageModelV4Usage(
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

private func convertLanguageModelV4GenerateResultToV3(
    _ result: LanguageModelV4GenerateResult
) throws -> LanguageModelV3GenerateResult {
    LanguageModelV3GenerateResult(
        content: try result.content.map(convertLanguageModelV4ContentToV3),
        finishReason: convertLanguageModelV4FinishReasonToV3(result.finishReason),
        usage: convertLanguageModelV4UsageToV3(result.usage),
        providerMetadata: nilIfEmptyOpenAIMetadata(result.providerMetadata),
        request: result.request.map(convertLanguageModelV4RequestInfoToV3),
        response: result.response.map(convertLanguageModelV4ResponseInfoToV3),
        warnings: result.warnings.map(convertSharedV4WarningToV3)
    )
}

private func convertLanguageModelV4ContentToV3(_ value: LanguageModelV4Content) throws -> LanguageModelV3Content {
    switch value {
    case .text(let content):
        return .text(LanguageModelV3Text(text: content.text, providerMetadata: content.providerMetadata))
    default:
        throw UnsupportedFunctionalityError(functionality: "OpenAI completion V4 content \(value) on V3 facade")
    }
}

private func convertLanguageModelV4StreamPartToV3(
    _ value: LanguageModelV4StreamPart
) throws -> LanguageModelV3StreamPart {
    switch value {
    case let .textStart(id, providerMetadata):
        return .textStart(id: id, providerMetadata: providerMetadata)
    case let .textDelta(id, delta, providerMetadata):
        return .textDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .textEnd(id, providerMetadata):
        return .textEnd(id: id, providerMetadata: providerMetadata)
    case let .streamStart(warnings):
        return .streamStart(warnings: warnings.map(convertSharedV4WarningToV3))
    case let .responseMetadata(id, modelId, timestamp):
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)
    case let .finish(finishReason, usage, providerMetadata):
        return .finish(
            finishReason: convertLanguageModelV4FinishReasonToV3(finishReason),
            usage: convertLanguageModelV4UsageToV3(usage),
            providerMetadata: nilIfEmptyOpenAIMetadata(providerMetadata)
        )
    case let .raw(rawValue):
        return .raw(rawValue: rawValue)
    case let .error(error):
        return .error(error: error)
    default:
        throw UnsupportedFunctionalityError(functionality: "OpenAI completion V4 stream part \(value) on V3 facade")
    }
}

private func convertLanguageModelV4FinishReasonToV3(_ value: LanguageModelV4FinishReason) -> LanguageModelV3FinishReason {
    LanguageModelV3FinishReason(
        unified: LanguageModelV3FinishReason.Unified(rawValue: value.unified.rawValue) ?? .other,
        raw: value.raw
    )
}

private func convertLanguageModelV4UsageToV3(_ value: LanguageModelV4Usage) -> LanguageModelV3Usage {
    LanguageModelV3Usage(
        inputTokens: .init(
            total: value.inputTokens.total,
            noCache: value.inputTokens.noCache,
            cacheRead: value.inputTokens.cacheRead,
            cacheWrite: value.inputTokens.cacheWrite
        ),
        outputTokens: .init(
            total: value.outputTokens.total,
            text: value.outputTokens.text,
            reasoning: value.outputTokens.reasoning
        ),
        raw: value.raw
    )
}

private func convertLanguageModelV4RequestInfoToV3(_ value: LanguageModelV4RequestInfo) -> LanguageModelV3RequestInfo {
    LanguageModelV3RequestInfo(body: value.body)
}

private func convertLanguageModelV4ResponseInfoToV3(_ value: LanguageModelV4ResponseInfo) -> LanguageModelV3ResponseInfo {
    LanguageModelV3ResponseInfo(
        id: value.id,
        timestamp: value.timestamp,
        modelId: value.modelId,
        headers: value.headers,
        body: value.body
    )
}

private func convertLanguageModelV4StreamResponseInfoToV3(
    _ value: LanguageModelV4StreamResponseInfo
) -> LanguageModelV3StreamResponseInfo {
    LanguageModelV3StreamResponseInfo(headers: value.headers)
}

private func convertSharedV4WarningToV3(_ value: SharedV4Warning) -> SharedV3Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .deprecated(setting, message):
        return .other(message: "\(setting): \(message)")
    case let .other(message):
        return .other(message: message)
    }
}

private func nilIfEmptyOpenAIMetadata(_ value: SharedV4ProviderMetadata?) -> SharedV3ProviderMetadata? {
    guard let value else { return nil }
    let withoutEmptyObjects = value.filter { !$0.value.isEmpty }
    return withoutEmptyObjects.isEmpty ? nil : withoutEmptyObjects
}

private func throwIfOpenAICompletionStreamErrorBeforeOutput(
    stream: AsyncThrowingStream<ParseJSONResult<OpenAICompletionChunk>, Error>,
    url: String,
    requestBodyValues: [String: JSONValue],
    responseHeaders: SharedV4Headers?
) async throws -> AsyncThrowingStream<ParseJSONResult<OpenAICompletionChunk>, Error> {
    let iteratorBox = OpenAICompletionStreamIteratorBox(iterator: stream.makeAsyncIterator())
    var buffered: [ParseJSONResult<OpenAICompletionChunk>] = []

    while let chunk = try await iteratorBox.next() {
        switch chunk {
        case .failure:
            buffered.append(chunk)
            return makeOpenAICompletionCheckedStream(buffered: buffered, iteratorBox: iteratorBox)

        case .success(let value, _):
            if case .error(let errorData) = value {
                throw openAICompletionStreamError(
                    errorData: errorData,
                    url: url,
                    requestBodyValues: requestBodyValues,
                    responseHeaders: responseHeaders
                )
            }

            buffered.append(chunk)
            if isOpenAICompletionOutputChunk(value) {
                return makeOpenAICompletionCheckedStream(buffered: buffered, iteratorBox: iteratorBox)
            }
        }
    }

    return makeOpenAICompletionCheckedStream(buffered: buffered, iteratorBox: iteratorBox)
}

private final class OpenAICompletionStreamIteratorBox: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<ParseJSONResult<OpenAICompletionChunk>, Error>.Iterator

    init(iterator: AsyncThrowingStream<ParseJSONResult<OpenAICompletionChunk>, Error>.Iterator) {
        self.iterator = iterator
    }

    func next() async throws -> ParseJSONResult<OpenAICompletionChunk>? {
        try await iterator.next()
    }
}

private func makeOpenAICompletionCheckedStream(
    buffered: [ParseJSONResult<OpenAICompletionChunk>],
    iteratorBox: OpenAICompletionStreamIteratorBox
) -> AsyncThrowingStream<ParseJSONResult<OpenAICompletionChunk>, Error> {
    AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
        let task = Task {
            do {
                for chunk in buffered {
                    continuation.yield(chunk)
                }
                while let chunk = try await iteratorBox.next() {
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}

private func isOpenAICompletionOutputChunk(_ chunk: OpenAICompletionChunk) -> Bool {
    guard case .data(let data) = chunk else { return false }
    return data.choices.contains { ($0.text?.isEmpty == false) }
}

private func openAICompletionStreamError(
    errorData: OpenAIErrorData,
    url: String,
    requestBodyValues: [String: JSONValue],
    responseHeaders: SharedV4Headers?
) -> APICallError {
    let frameJSON = (try? JSONEncoder().encodeToJSONValue(errorData.error)) ?? .string(errorData.error.message)
    return APICallError(
        message: errorData.error.message,
        url: url,
        requestBodyValues: requestBodyValues,
        statusCode: openAICompletionStreamErrorStatusCode(errorData.error),
        responseHeaders: responseHeaders,
        responseBody: jsonString(from: frameJSON),
        data: frameJSON
    )
}

private func openAICompletionStreamErrorStatusCode(_ error: OpenAIErrorData.ErrorPayload) -> Int {
    if let code = error.code {
        switch code {
        case .number(let value):
            let intValue = Int(value)
            if Double(intValue) == value, (400...599).contains(intValue) {
                return intValue
            }
        case .string(let value):
            if value.range(of: #"^\d{3}$"#, options: .regularExpression) != nil,
               let intValue = Int(value),
               (400...599).contains(intValue) {
                return intValue
            }
        }
    }

    let discriminator = [openAIErrorCodeDescription(error.code), error.type]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

    if discriminator.contains("insufficient_quota") || discriminator.contains("rate_limit") {
        return 429
    }
    if discriminator.contains("authentication") { return 401 }
    if discriminator.contains("permission") { return 403 }
    if discriminator.contains("not_found") { return 404 }
    if discriminator.contains("invalid")
        || discriminator.contains("bad_request")
        || discriminator.contains("context_length") {
        return 400
    }
    if discriminator.contains("overload") { return 503 }
    if discriminator.contains("timeout") { return 504 }

    return 500
}

private func openAIErrorCodeDescription(_ code: OpenAIErrorCode?) -> String? {
    switch code {
    case .none:
        return nil
    case .number(let value):
        return String(value)
    case .string(let value):
        return value
    }
}

private func jsonString(from value: JSONValue) -> String? {
    do {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}
