import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleCompletionConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () async throws -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) throws -> String
    public let fetch: FetchFunction?
    public let includeUsage: Bool
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])?

    public init(provider: String, headers: @escaping @Sendable () async throws -> [String: String] = { [:] },
                url: @escaping @Sendable (OpenAICompatibleURLOptions) throws -> String, fetch: FetchFunction? = nil,
                includeUsage: Bool = false, errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
                supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])? = nil) {
        self.provider = provider; self.headers = headers; self.url = url; self.fetch = fetch
        self.includeUsage = includeUsage; self.errorConfiguration = errorConfiguration; self.supportedUrls = supportedUrls
    }
}

public final class OpenAICompatibleCompletionLanguageModel: LanguageModelV4 {
    public let specificationVersion = "v4"
    public let modelId: String
    public var provider: String { config.provider }
    public var supportedUrls: [String: [NSRegularExpression]] { get async throws { try await config.supportedUrls?() ?? [:] } }
    private let config: OpenAICompatibleCompletionConfig
    private var providerOptionsName: String { provider.split(separator: ".").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "" }

    public init(modelId: OpenAICompatibleCompletionModelId, config: OpenAICompatibleCompletionConfig) {
        self.modelId = modelId.rawValue; self.config = config
    }
    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let (body, warnings) = try await prepare(options)
        let response = try await postJsonToAPI(url: try config.url(.init(modelId: modelId, path: "/completions")),
                                               headers: try await headers(options.headers), body: JSONValue.object(body),
                                               failedResponseHandler: config.errorConfiguration.failedResponseHandler,
                                               successfulResponseHandler: createJsonResponseHandler(responseSchema: completionResponseSchema),
                                               isAborted: options.abortSignal, fetch: config.fetch)
        guard let choice = response.value.choices.first else {
            throw InvalidResponseDataError(data: response.rawValue, message: "Response did not contain any choices.")
        }
        return .init(content: choice.text.isEmpty ? [] : [.text(.init(text: choice.text))],
                     finishReason: .init(unified: mapOpenAICompatibleFinishReason(choice.finishReason), raw: choice.finishReason),
                     usage: usage(response.value.usage), request: .init(body: body),
                     response: .init(id: response.value.id, timestamp: response.value.created.map(Date.init(timeIntervalSince1970:)),
                                     modelId: response.value.model, headers: response.responseHeaders, body: response.rawValue), warnings: warnings)
    }
    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        var (body, warnings) = try await prepare(options)
        body["stream"] = true
        if config.includeUsage { body["stream_options"] = ["include_usage": true] }
        let response = try await postJsonToAPI(url: try config.url(.init(modelId: modelId, path: "/completions")),
                                               headers: try await headers(options.headers), body: JSONValue.object(body),
                                               failedResponseHandler: config.errorConfiguration.failedResponseHandler,
                                               successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: completionChunkSchema(config.errorConfiguration)),
                                               isAborted: options.abortSignal, fetch: config.fetch)
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: warnings))
            let task = Task {
                var first = true
                var finish = LanguageModelV4FinishReason(unified: .other)
                var latestUsage: CompletionUsage?
                do {
                    for try await result in response.value {
                        let raw: JSONValue?
                        switch result {
                        case .success(_, let value): raw = try? jsonValue(from: value)
                        case .failure(_, let value): raw = value.flatMap { try? jsonValue(from: $0) }
                        }
                        if options.includeRawChunks == true, let raw { continuation.yield(.raw(rawValue: raw)) }
                        switch result {
                        case .failure(let error, _):
                            finish = .init(unified: .error)
                            continuation.yield(.error(error: .error(error)))
                        case .success(let event, _):
                            switch event {
                            case .error(let error):
                                finish = .init(unified: .error)
                                let payload: JSONValue
                                if case .object(let object) = raw, let error = object["error"] { payload = error }
                                else { payload = .string(error.message) }
                                continuation.yield(.error(error: .value(payload)))
                            case .data(let value):
                                if first {
                                    first = false
                                    continuation.yield(.responseMetadata(id: value.id, modelId: value.model, timestamp: value.created.map(Date.init(timeIntervalSince1970:))))
                                    continuation.yield(.textStart(id: "0", providerMetadata: nil))
                                }
                                if let usage = value.usage { latestUsage = usage }
                                guard let choice = value.choices.first else { continue }
                                if let reason = choice.finishReason { finish = .init(unified: mapOpenAICompatibleFinishReason(reason), raw: reason) }
                                continuation.yield(.textDelta(id: "0", delta: choice.text, providerMetadata: nil))
                            }
                        }
                    }
                    if !first { continuation.yield(.textEnd(id: "0", providerMetadata: nil)) }
                    continuation.yield(.finish(finishReason: finish, usage: usage(latestUsage), providerMetadata: nil))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return .init(stream: stream, request: .init(body: body), response: .init(headers: response.responseHeaders))
    }
    private func prepare(_ options: LanguageModelV4CallOptions) async throws -> ([String: JSONValue], [SharedV4Warning]) {
        var warnings: [SharedV4Warning] = []
        let name = providerOptionsName
        let camelName = openAICompatibleCamelCase(name)
        if let warning = openAICompatibleDeprecatedProviderOptionsWarning(rawName: name, providerOptions: options.providerOptions) { warnings.append(warning) }
        let raw = try await parseProviderOptions(provider: name, providerOptions: options.providerOptions, schema: openAICompatibleCompletionProviderOptionsSchema)
        let camel = try await parseProviderOptions(provider: camelName, providerOptions: options.providerOptions, schema: openAICompatibleCompletionProviderOptionsSchema)
        if options.topK != nil { warnings.append(.unsupported(feature: "topK", details: nil)) }
        if !(options.tools?.isEmpty ?? true) { warnings.append(.unsupported(feature: "tools", details: nil)) }
        if options.toolChoice != nil { warnings.append(.unsupported(feature: "toolChoice", details: nil)) }
        if case .json = options.responseFormat { warnings.append(.unsupported(feature: "responseFormat", details: "JSON response format is not supported.")) }
        let conversion = try OpenAICompatibleCompletionPromptConverter.convert(prompt: options.prompt)
        let stop = (conversion.stopSequences ?? []) + (options.stopSequences ?? [])
        var body: [String: JSONValue] = ["model": .string(modelId)]
        if let value = camel?.echo ?? raw?.echo { body["echo"] = .bool(value) }
        if let value = camel?.logitBias ?? raw?.logitBias { body["logit_bias"] = .object(value.mapValues(JSONValue.number)) }
        if let value = camel?.suffix ?? raw?.suffix { body["suffix"] = .string(value) }
        if let value = camel?.user ?? raw?.user { body["user"] = .string(value) }
        if let value = options.maxOutputTokens { body["max_tokens"] = .number(Double(value)) }
        if let value = options.temperature { body["temperature"] = .number(value) }
        if let value = options.topP { body["top_p"] = .number(value) }
        if let value = options.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if let value = options.presencePenalty { body["presence_penalty"] = .number(value) }
        if let value = options.seed { body["seed"] = .number(Double(value)) }
        body.merge(options.providerOptions?[name] ?? [:]) { _, new in new }
        body.merge(options.providerOptions?[camelName] ?? [:]) { _, new in new }
        body["prompt"] = .string(conversion.prompt)
        if !stop.isEmpty { body["stop"] = .array(stop.map(JSONValue.string)) }
        return (body, warnings)
    }
    private func headers(_ options: SharedV4Headers?) async throws -> [String: String] {
        combineHeaders(try await config.headers().mapValues(Optional.some), options?.mapValues(Optional.some)).compactMapValues { $0 }
    }
    private func usage(_ usage: CompletionUsage?) -> LanguageModelV4Usage {
        guard let usage else { return .init() }
        return .init(inputTokens: .init(total: usage.promptTokens, noCache: usage.promptTokens),
                     outputTokens: .init(total: usage.completionTokens, text: usage.completionTokens), raw: usage.raw)
    }
}

private struct CompletionUsage: Decodable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let raw: JSONValue
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        promptTokens = try c.decode(Int.self, forKey: .prompt)
        completionTokens = try c.decode(Int.self, forKey: .completion)
        totalTokens = try c.decode(Int.self, forKey: .total)
        raw = try JSONValue(from: decoder)
    }
    private enum Key: String, CodingKey { case prompt = "prompt_tokens", completion = "completion_tokens", total = "total_tokens" }
}
private struct CompletionResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        let text: String
        let finishReason: String
        enum CodingKeys: String, CodingKey { case text; case finishReason = "finish_reason" }
    }
    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: CompletionUsage?
}
private struct CompletionChunk: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        let text: String
        let finishReason: String?
        let index: Double
        enum CodingKeys: String, CodingKey { case text, index; case finishReason = "finish_reason" }
    }
    let id: String?
    let created: Double?
    let model: String?
    let choices: [Choice]
    let usage: CompletionUsage?
}
private enum CompletionEvent: Sendable { case data(CompletionChunk); case error(OpenAICompatibleParsedStreamError) }
private let completionResponseSchema = FlexibleSchema(Schema<CompletionResponse>.codable(CompletionResponse.self, jsonSchema: ["type": "object"]))
private func completionChunkSchema(_ error: OpenAICompatibleErrorConfiguration) -> FlexibleSchema<CompletionEvent> {
    createOpenAICompatibleStreamSchema(dataType: CompletionChunk.self, errorConfiguration: error, transformData: CompletionEvent.data, transformError: CompletionEvent.error)
}
