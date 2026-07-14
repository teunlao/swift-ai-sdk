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
    public let supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])?

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])? = nil
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.includeUsage = includeUsage
        self.errorConfiguration = errorConfiguration
        self.supportedUrls = supportedUrls
    }
}

private enum OpenAICompatibleCompletionPromptInput: Sendable {
    case v3(LanguageModelV3Prompt)
    case v4(LanguageModelV4Prompt)
}

private enum OpenAICompatibleCompletionContract: Sendable {
    case v3
    case v4

    var isV4: Bool {
        switch self {
        case .v3: return false
        case .v4: return true
        }
    }

    var usesCamelCaseProviderOptions: Bool { isV4 }
    var startsTextOnFirstDataChunk: Bool { isV4 }
    var emitsEmptyTextDeltas: Bool { isV4 }
    var includesUsageProviderMetadata: Bool { !isV4 }
    var usesV4StreamErrorPayload: Bool { isV4 }
}

private struct OpenAICompatibleCompletionCallSettings: Sendable {
    let contract: OpenAICompatibleCompletionContract
    let prompt: OpenAICompatibleCompletionPromptInput
    let maxOutputTokens: Int?
    let temperature: Double?
    let stopSequences: [String]?
    let topP: Double?
    let topK: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let responseFormat: LanguageModelV4ResponseFormat?
    let seed: Int?
    let hasUnsupportedTools: Bool
    let hasToolChoice: Bool
    let includeRawChunks: Bool?
    let abortSignal: (@Sendable () -> Bool)?
    let headers: SharedV4Headers?
    let providerOptions: SharedV4ProviderOptions?

    init(v3 options: LanguageModelV3CallOptions) {
        contract = .v3
        prompt = .v3(options.prompt)
        maxOutputTokens = options.maxOutputTokens
        temperature = options.temperature
        stopSequences = options.stopSequences
        topP = options.topP
        topK = options.topK
        presencePenalty = options.presencePenalty
        frequencyPenalty = options.frequencyPenalty
        responseFormat = options.responseFormat.map(convertOpenAICompatibleCompletionResponseFormatToV4)
        seed = options.seed
        hasUnsupportedTools = options.tools != nil
        hasToolChoice = options.toolChoice != nil
        includeRawChunks = options.includeRawChunks
        abortSignal = options.abortSignal
        headers = options.headers
        providerOptions = options.providerOptions
    }

    init(v4 options: LanguageModelV4CallOptions) {
        contract = .v4
        prompt = .v4(options.prompt)
        maxOutputTokens = options.maxOutputTokens
        temperature = options.temperature
        stopSequences = options.stopSequences
        topP = options.topP
        topK = options.topK
        presencePenalty = options.presencePenalty
        frequencyPenalty = options.frequencyPenalty
        responseFormat = options.responseFormat
        seed = options.seed
        hasUnsupportedTools = !(options.tools?.isEmpty ?? true)
        hasToolChoice = options.toolChoice != nil
        includeRawChunks = options.includeRawChunks
        abortSignal = options.abortSignal
        headers = options.headers
        providerOptions = options.providerOptions
    }
}

private struct OpenAICompatibleCompletionLanguageModelCore: Sendable {
    private let modelIdentifier: OpenAICompatibleCompletionModelId
    private let config: OpenAICompatibleCompletionConfig
    private let legacyProviderOptionsName: String
    private let v4ProviderOptionsName: String

    init(modelId: OpenAICompatibleCompletionModelId, config: OpenAICompatibleCompletionConfig) {
        modelIdentifier = modelId
        self.config = config
        legacyProviderOptionsName = config.provider.split(separator: ".").first.map(String.init) ?? ""
        v4ProviderOptionsName = config.provider
            .split(separator: ".", omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }

    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await config.supportedUrls?() ?? [:] }
    }

    func doGenerate(
        options: OpenAICompatibleCompletionCallSettings
    ) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let headers = requestHeaders(for: options.headers)
        let url = config.url(.init(modelId: modelIdentifier.rawValue, path: "/completions"))

        let response = try await postJsonToAPI(
            url: url,
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
                url: url,
                requestBodyValues: prepared.body
            )
        }

        var content: [LanguageModelV4Content] = []
        if let text = choice.text, !text.isEmpty {
            content.append(.text(LanguageModelV4Text(text: text)))
        }

        let rawFinishReason = choice.finishReason
        let metadata = responseMetadata(
            id: response.value.id,
            model: response.value.model,
            created: response.value.created
        )
        let providerMetadata = options.contract.includesUsageProviderMetadata
            ? makeProviderMetadata(
                usage: response.value.usage,
                providerOptionsName: prepared.providerOptionsName
            )
            : nil

        return LanguageModelV4GenerateResult(
            content: content,
            finishReason: LanguageModelV4FinishReason(
                unified: mapOpenAICompatibleFinishReasonV4(rawFinishReason),
                raw: rawFinishReason
            ),
            usage: mapUsage(response.value.usage),
            providerMetadata: providerMetadata,
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

    func doStream(
        options: OpenAICompatibleCompletionCallSettings
    ) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options: options)
        var body = prepared.body
        body["stream"] = .bool(true)
        if config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }

        let eventStream = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/completions")),
            headers: requestHeaders(for: options.headers),
            body: JSONValue.object(body),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: openAICompatibleCompletionChunkSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))

            let task = Task {
                var finishReason = LanguageModelV4FinishReason(unified: .other, raw: nil)
                var usage = LanguageModelV4Usage()
                var latestUsage: OpenAICompatibleCompletionUsage?
                var isFirstChunk = true
                var isActiveText = false

                do {
                    for try await parseResult in eventStream.value {
                        if options.includeRawChunks == true,
                           let rawJSON = parseResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: rawJSON))
                        }

                        switch parseResult {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error, raw: nil)
                            continuation.yield(.error(error: .string(String(describing: error))))
                        case .success(let chunk, let raw):
                            switch chunk {
                            case .error(let errorData):
                                finishReason = .init(unified: .error, raw: nil)
                                continuation.yield(.error(error: streamErrorValue(
                                    errorData,
                                    rawJSON: try? jsonValue(from: raw),
                                    contract: options.contract
                                )))
                            case .data(let data):
                                if isFirstChunk {
                                    isFirstChunk = false
                                    let metadata = responseMetadata(
                                        id: data.id,
                                        model: data.model,
                                        created: data.created
                                    )
                                    continuation.yield(.responseMetadata(
                                        id: metadata.id,
                                        modelId: metadata.modelId,
                                        timestamp: metadata.timestamp
                                    ))
                                    if options.contract.startsTextOnFirstDataChunk {
                                        isActiveText = true
                                        continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                    }
                                }

                                if let usageValue = data.usage {
                                    latestUsage = usageValue
                                    usage = mapUsage(usageValue)
                                }

                                guard let choice = data.choices.first else { continue }

                                if let finish = choice.finishReason {
                                    finishReason = LanguageModelV4FinishReason(
                                        unified: mapOpenAICompatibleFinishReasonV4(finish),
                                        raw: finish
                                    )
                                }

                                if let textDelta = choice.textDelta,
                                   options.contract.emitsEmptyTextDeltas || !textDelta.isEmpty {
                                    if !isActiveText {
                                        isActiveText = true
                                        continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                    }
                                    continuation.yield(.textDelta(
                                        id: "0",
                                        delta: textDelta,
                                        providerMetadata: nil
                                    ))
                                }
                            }
                        }
                    }

                    if isActiveText {
                        continuation.yield(.textEnd(id: "0", providerMetadata: nil))
                    }

                    let providerMetadata = options.contract.includesUsageProviderMetadata
                        ? makeProviderMetadata(
                            usage: latestUsage,
                            providerOptionsName: prepared.providerOptionsName
                        )
                        : nil
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
        let providerOptionsName: String
    }

    private func prepareRequest(
        options: OpenAICompatibleCompletionCallSettings
    ) async throws -> PreparedRequest {
        let providerOptionsName = options.contract.isV4
            ? v4ProviderOptionsName
            : legacyProviderOptionsName
        let camelCaseProviderOptionsName = openAICompatibleCamelCase(providerOptionsName)
        var warnings: [SharedV4Warning] = []

        if options.contract.usesCamelCaseProviderOptions,
           let warning = openAICompatibleDeprecatedProviderOptionsWarning(
               rawName: providerOptionsName,
               providerOptions: options.providerOptions
           ) {
            warnings.append(warning)
        }
        if options.topK != nil {
            warnings.append(.unsupported(feature: "topK", details: nil))
        }
        if options.hasUnsupportedTools {
            warnings.append(.unsupported(feature: "tools", details: nil))
        }
        if options.hasToolChoice {
            warnings.append(.unsupported(feature: "toolChoice", details: nil))
        }
        if let responseFormat = options.responseFormat, case .json = responseFormat {
            warnings.append(.unsupported(
                feature: "responseFormat",
                details: "JSON response format is not supported."
            ))
        }

        let legacyOptions: OpenAICompatibleCompletionProviderOptions
        if options.contract.isV4 {
            legacyOptions = OpenAICompatibleCompletionProviderOptions()
        } else {
            legacyOptions = try await parseProviderOptions(
                provider: "openai-compatible",
                providerOptions: options.providerOptions,
                schema: openAICompatibleCompletionProviderOptionsSchema
            ) ?? OpenAICompatibleCompletionProviderOptions()
        }

        let rawOptions = try await parseProviderOptions(
            provider: providerOptionsName,
            providerOptions: options.providerOptions,
            schema: openAICompatibleCompletionProviderOptionsSchema
        ) ?? OpenAICompatibleCompletionProviderOptions()

        let camelCaseOptions: OpenAICompatibleCompletionProviderOptions
        if options.contract.usesCamelCaseProviderOptions {
            camelCaseOptions = try await parseProviderOptions(
                provider: camelCaseProviderOptionsName,
                providerOptions: options.providerOptions,
                schema: openAICompatibleCompletionProviderOptionsSchema
            ) ?? OpenAICompatibleCompletionProviderOptions()
        } else {
            camelCaseOptions = OpenAICompatibleCompletionProviderOptions()
        }

        var mergedOptions = legacyOptions
        merge(rawOptions, into: &mergedOptions)
        if options.contract.usesCamelCaseProviderOptions {
            merge(camelCaseOptions, into: &mergedOptions)
        }

        let conversion: OpenAICompatibleCompletionPromptConversion
        switch options.prompt {
        case .v3(let prompt):
            conversion = try OpenAICompatibleCompletionPromptConverter.convert(prompt: prompt)
        case .v4(let prompt):
            conversion = try OpenAICompatibleCompletionPromptConverter.convert(prompt: prompt)
        }

        var stopSequences = conversion.stopSequences ?? []
        if let userStops = options.stopSequences {
            stopSequences.append(contentsOf: userStops)
        }

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue)
        ]

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

        let rawProviderOptions = options.providerOptions?[providerOptionsName] ?? [:]
        switch options.contract {
        case .v3:
            body["prompt"] = .string(conversion.prompt)
            if !stopSequences.isEmpty {
                body["stop"] = .array(stopSequences.map(JSONValue.string))
            }
            let forwardedOptions = rawProviderOptions.filter { key, _ in
                !["echo", "logitBias", "suffix", "user"].contains(key)
            }
            body.merge(forwardedOptions) { _, new in new }
        case .v4:
            body.merge(rawProviderOptions) { _, new in new }
            body.merge(options.providerOptions?[camelCaseProviderOptionsName] ?? [:]) { _, new in new }
            body["prompt"] = .string(conversion.prompt)
            if !stopSequences.isEmpty {
                body["stop"] = .array(stopSequences.map(JSONValue.string))
            }
        }

        return PreparedRequest(
            body: body,
            warnings: warnings,
            providerOptionsName: providerOptionsName
        )
    }

    private func merge(
        _ source: OpenAICompatibleCompletionProviderOptions,
        into destination: inout OpenAICompatibleCompletionProviderOptions
    ) {
        if let echo = source.echo { destination.echo = echo }
        if let logitBias = source.logitBias { destination.logitBias = logitBias }
        if let suffix = source.suffix { destination.suffix = suffix }
        if let user = source.user { destination.user = user }
    }

    private func requestHeaders(for requestHeaders: SharedV4Headers?) -> [String: String] {
        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = requestHeaders?.mapValues { Optional($0) }
        return combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }
    }

    private func mapUsage(
        _ usage: OpenAICompatibleCompletionUsage?
    ) -> LanguageModelV4Usage {
        guard let usage else { return LanguageModelV4Usage() }

        let promptTokens = usage.promptTokens ?? 0
        let completionTokens = usage.completionTokens ?? 0
        return LanguageModelV4Usage(
            inputTokens: .init(total: promptTokens, noCache: promptTokens),
            outputTokens: .init(total: completionTokens, text: completionTokens),
            raw: try? JSONEncoder().encodeToJSONValue(usage)
        )
    }

    private func makeProviderMetadata(
        usage: OpenAICompatibleCompletionUsage?,
        providerOptionsName: String
    ) -> SharedV4ProviderMetadata? {
        var entry: [String: JSONValue] = [:]
        if let cachedTokens = usage?.promptTokensDetails?.cachedTokens {
            entry["cachedTokens"] = .number(Double(cachedTokens))
        }
        if let acceptedTokens = usage?.completionTokensDetails?.acceptedPredictionTokens {
            entry["acceptedPredictionTokens"] = .number(Double(acceptedTokens))
        }
        if let rejectedTokens = usage?.completionTokensDetails?.rejectedPredictionTokens {
            entry["rejectedPredictionTokens"] = .number(Double(rejectedTokens))
        }
        return entry.isEmpty ? nil : [providerOptionsName: entry]
    }

    private func streamErrorValue(
        _ errorData: OpenAICompatibleErrorData,
        rawJSON: JSONValue?,
        contract: OpenAICompatibleCompletionContract
    ) -> JSONValue {
        if contract.usesV4StreamErrorPayload {
            if case .object(let object) = rawJSON,
               let error = object["error"] {
                return error
            }
            return (try? JSONEncoder().encodeToJSONValue(errorData.error))
                ?? .string(errorData.error.message)
        }
        return (try? JSONEncoder().encodeToJSONValue(errorData))
            ?? .string(errorData.error.message)
    }

    private func responseMetadata(
        id: String?,
        model: String?,
        created: Double?
    ) -> (id: String?, modelId: String?, timestamp: Date?) {
        (id, model, created.map { Date(timeIntervalSince1970: $0) })
    }
}

public final class OpenAICompatibleCompletionLanguageModel: LanguageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleCompletionModelId
    private let core: OpenAICompatibleCompletionLanguageModelCore

    public init(
        modelId: OpenAICompatibleCompletionModelId,
        config: OpenAICompatibleCompletionConfig
    ) {
        modelIdentifier = modelId
        core = OpenAICompatibleCompletionLanguageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }
    public var supportedUrls: [String: [NSRegularExpression]] { [:] }

    public func doGenerate(
        options: LanguageModelV3CallOptions
    ) async throws -> LanguageModelV3GenerateResult {
        let result = try await core.doGenerate(
            options: OpenAICompatibleCompletionCallSettings(v3: options)
        )
        return try convertOpenAICompatibleCompletionGenerateResultToV3(result)
    }

    public func doStream(
        options: LanguageModelV3CallOptions
    ) async throws -> LanguageModelV3StreamResult {
        let result = try await core.doStream(
            options: OpenAICompatibleCompletionCallSettings(v3: options)
        )
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await part in result.stream {
                        continuation.yield(try convertOpenAICompatibleCompletionStreamPartToV3(part))
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
            request: result.request.map { LanguageModelV3RequestInfo(body: $0.body) },
            response: result.response.map { LanguageModelV3StreamResponseInfo(headers: $0.headers) }
        )
    }
}

public final class OpenAICompatibleCompletionLanguageModelV4: LanguageModelV4 {
    private let core: OpenAICompatibleCompletionLanguageModelCore

    public init(
        modelId: OpenAICompatibleCompletionModelId,
        config: OpenAICompatibleCompletionConfig
    ) {
        core = OpenAICompatibleCompletionLanguageModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await core.supportedUrls }
    }

    public func doGenerate(
        options: LanguageModelV4CallOptions
    ) async throws -> LanguageModelV4GenerateResult {
        try await core.doGenerate(options: OpenAICompatibleCompletionCallSettings(v4: options))
    }

    public func doStream(
        options: LanguageModelV4CallOptions
    ) async throws -> LanguageModelV4StreamResult {
        try await core.doStream(options: OpenAICompatibleCompletionCallSettings(v4: options))
    }
}

private func convertOpenAICompatibleCompletionResponseFormatToV4(
    _ value: LanguageModelV3ResponseFormat
) -> LanguageModelV4ResponseFormat {
    switch value {
    case .text:
        return .text
    case let .json(schema, name, description):
        return .json(schema: schema, name: name, description: description)
    }
}

private func convertOpenAICompatibleCompletionGenerateResultToV3(
    _ result: LanguageModelV4GenerateResult
) throws -> LanguageModelV3GenerateResult {
    LanguageModelV3GenerateResult(
        content: try result.content.map { content in
            guard case .text(let text) = content else {
                throw UnsupportedFunctionalityError(
                    functionality: "OpenAI-compatible Completion V4 content on V3 facade"
                )
            }
            return .text(LanguageModelV3Text(
                text: text.text,
                providerMetadata: text.providerMetadata
            ))
        },
        finishReason: convertOpenAICompatibleCompletionFinishReasonToV3(result.finishReason),
        usage: convertOpenAICompatibleCompletionUsageToV3(result.usage),
        providerMetadata: result.providerMetadata,
        request: result.request.map { LanguageModelV3RequestInfo(body: $0.body) },
        response: result.response.map {
            LanguageModelV3ResponseInfo(
                id: $0.id,
                timestamp: $0.timestamp,
                modelId: $0.modelId,
                headers: $0.headers,
                body: $0.body
            )
        },
        warnings: result.warnings.map(convertOpenAICompatibleCompletionWarningToV3)
    )
}

private func convertOpenAICompatibleCompletionStreamPartToV3(
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
        return .streamStart(warnings: warnings.map(convertOpenAICompatibleCompletionWarningToV3))
    case let .responseMetadata(id, modelId, timestamp):
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)
    case let .finish(finishReason, usage, providerMetadata):
        return .finish(
            finishReason: convertOpenAICompatibleCompletionFinishReasonToV3(finishReason),
            usage: convertOpenAICompatibleCompletionUsageToV3(usage),
            providerMetadata: providerMetadata
        )
    case let .raw(rawValue):
        return .raw(rawValue: rawValue)
    case let .error(error):
        return .error(error: error)
    default:
        throw UnsupportedFunctionalityError(
            functionality: "OpenAI-compatible Completion V4 stream part on V3 facade"
        )
    }
}

private func convertOpenAICompatibleCompletionFinishReasonToV3(
    _ value: LanguageModelV4FinishReason
) -> LanguageModelV3FinishReason {
    LanguageModelV3FinishReason(
        unified: LanguageModelV3FinishReason.Unified(rawValue: value.unified.rawValue) ?? .other,
        raw: value.raw
    )
}

private func convertOpenAICompatibleCompletionUsageToV3(
    _ value: LanguageModelV4Usage
) -> LanguageModelV3Usage {
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

private func convertOpenAICompatibleCompletionWarningToV3(
    _ value: SharedV4Warning
) -> SharedV3Warning {
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

private struct OpenAICompatibleCompletionUsage: Codable, Sendable {
    struct PromptTokensDetails: Codable, Sendable {
        let cachedTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }

    struct CompletionTokensDetails: Codable, Sendable {
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
