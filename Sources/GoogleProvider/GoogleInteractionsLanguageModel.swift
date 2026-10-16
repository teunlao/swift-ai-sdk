import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GoogleInteractionsLanguageModel: LanguageModelV4 {
    public struct Config: Sendable {
        public let provider: String
        public let baseURL: String
        public let headers: @Sendable () throws -> [String: String?]
        public let fetch: FetchFunction?
        public let generateId: @Sendable () -> String
        public let supportedUrls: (@Sendable () -> [String: [NSRegularExpression]])?
        public let resolveBaseURL: (@Sendable () throws -> String)?
        public init(provider: String, baseURL: String, headers: @escaping @Sendable () throws -> [String: String?] = { [:] }, fetch: FetchFunction? = nil, generateId: @escaping @Sendable () -> String = generateID, supportedUrls: (@Sendable () -> [String: [NSRegularExpression]])? = nil, resolveBaseURL: (@Sendable () throws -> String)? = nil) {
            self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch; self.generateId = generateId; self.supportedUrls = supportedUrls; self.resolveBaseURL = resolveBaseURL
        }
    }
    private struct Request {
        let body: JSONObject
        let warnings: [SharedV4Warning]
        let background: Bool
        let timeout: Int
    }
    private let config: Config
    public let modelId: String
    public let agent: String?
    public var provider: String { config.provider }
    public init(modelId: String, config: Config) { self.modelId = modelId; self.agent = nil; self.config = config }
    public init(input: GoogleInteractionsModelInput, config: Config) {
        self.config = config
        switch input {
        case .model(let id): self.modelId = id; self.agent = nil
        case .agent(let name): self.modelId = name.rawValue; self.agent = name.rawValue
        case .managedAgent(let name): self.modelId = name; self.agent = name
        }
    }
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            if let supported = config.supportedUrls { return supported() }
            let http = try! NSRegularExpression(pattern: "^https?://.+")
            return ["image/*": [http], "application/pdf": [http], "audio/*": [http], "video/*": [try! .init(pattern: "^https?://(www\\.)?youtube\\.com/watch\\?v=.+"), try! .init(pattern: "^https?://youtu\\.be/.+"), try! .init(pattern: "^gs://.+")]]
        }
    }

    private func prepare(_ options: LanguageModelV4CallOptions) async throws -> Request {
        let google = try await parseProviderOptions(provider: "google", providerOptions: options.providerOptions, schema: googleInteractionsOptionsSchema)
        var warnings: [SharedV4Warning] = []
        if agent == nil {
            if options.frequencyPenalty != nil { warnings.append(.unsupported(feature: "frequencyPenalty", details: nil)) }
            if options.presencePenalty != nil { warnings.append(.unsupported(feature: "presencePenalty", details: nil)) }
        }
        let tools = prepareGoogleInteractionsTools(options.tools, choice: options.toolChoice, warnings: &warnings)
        var formats: [JSONValue] = []
        if case .json(let schema, _, _) = options.responseFormat {
            if agent != nil { warnings.append(.other(message: "google.interactions: structured output (responseFormat) is not supported when an agent is set; responseFormat will be ignored.")) }
            else {
                var entry: JSONObject = ["type": .string("text"), "mime_type": .string("application/json")]
                if let schema { entry["schema"] = schema }
                formats.append(.object(entry))
            }
        }
        for entry in google?.responseFormat ?? [] {
            let type = interactionString(entry["type"]) ?? "text"
            var result: JSONObject = ["type": .string(type)]
            let fields: [(String, String)]
            switch type {
            case "text": fields = [("mimeType", "mime_type"), ("schema", "schema")]
            case "image": fields = [("mimeType", "mime_type"), ("aspectRatio", "aspect_ratio"), ("imageSize", "image_size")]
            case "audio": fields = [("mimeType", "mime_type")]
            default: fields = [("aspectRatio", "aspect_ratio"), ("resolution", "resolution"), ("duration", "duration"), ("delivery", "delivery"), ("gcsUri", "gcs_uri")]
            }
            for (key, wire) in fields { if let value = entry[key], value != .null { result[wire] = value } }
            formats.append(.object(result))
        }
        let converted = try convertGoogleInteractionsPrompt(options.prompt, options: google, warnings: &warnings)
        var system = converted.system
        if system != nil && google?.systemInstruction != nil { warnings.append(.other(message: "google.interactions: both AI SDK system message and providerOptions.google.systemInstruction were set; using the AI SDK system message.")) }
        else if system == nil { system = google?.systemInstruction }
        var body: JSONObject = [agent == nil ? "model" : "agent": .string(agent ?? modelId), "input": .array(converted.input)]
        if let system { body["system_instruction"] = .string(system) }
        if !tools.tools.isEmpty { body["tools"] = .array(tools.tools) }
        if agent != nil {
            var dropped: [String] = []
            for (key, present) in [("temperature", options.temperature != nil), ("topP", options.topP != nil), ("topK", options.topK != nil), ("frequencyPenalty", options.frequencyPenalty != nil), ("presencePenalty", options.presencePenalty != nil), ("seed", options.seed != nil), ("stopSequences", options.stopSequences?.isEmpty == false), ("maxOutputTokens", options.maxOutputTokens != nil), ("thinkingLevel", google?.thinkingLevel != nil), ("thinkingSummaries", google?.thinkingSummaries != nil), ("imageConfig", google?.imageConfig != nil)] { if present { dropped.append(key) } }
            if !dropped.isEmpty { warnings.append(.other(message: "google.interactions: \(dropped.joined(separator: ", ")) \(dropped.count == 1 ? "is" : "are") not supported when an agent is set; use providerOptions.google.agentConfig instead. Dropped from the request body.")) }
            if let config = google?.agentConfig {
                var agentConfig: JSONObject = ["type": config["type"]!]
                if config["type"] == .string("deep-research") {
                    for (key, wire) in [("thinkingSummaries", "thinking_summaries"), ("visualization", "visualization"), ("collaborativePlanning", "collaborative_planning")] { if let value = config[key], value != .null { agentConfig[wire] = value } }
                }
                body["agent_config"] = .object(agentConfig)
            }
        } else {
            var generation: JSONObject = [:]
            if let temperature = options.temperature { generation["temperature"] = .number(temperature) }
            if let topP = options.topP { generation["top_p"] = .number(topP) }
            if let topK = options.topK { generation["top_k"] = .number(Double(topK)) }
            if let seed = options.seed { generation["seed"] = .number(Double(seed)) }
            if let stop = options.stopSequences, !stop.isEmpty { generation["stop_sequences"] = .array(stop.map(JSONValue.string)) }
            if let max = options.maxOutputTokens { generation["max_output_tokens"] = .number(Double(max)) }
            if let thinking = google?.thinkingLevel { generation["thinking_level"] = .string(thinking) }
            if let summaries = google?.thinkingSummaries { generation["thinking_summaries"] = .string(summaries) }
            if let choice = tools.choice { generation["tool_choice"] = choice }
            if !generation.isEmpty { body["generation_config"] = .object(generation) }
            if let config = google?.imageConfig {
                let hasImage = formats.contains { interactionObject($0)?["type"] == .string("image") }
                warnings.append(.other(message: hasImage ? "google.interactions: providerOptions.google.imageConfig is deprecated and was ignored because providerOptions.google.responseFormat already supplies an image entry. Use responseFormat exclusively." : "google.interactions: providerOptions.google.imageConfig is deprecated. Use providerOptions.google.responseFormat with a { type: \"image\", ... } entry instead."))
                if !hasImage {
                    var image: JSONObject = ["type": .string("image"), "mime_type": .string("image/png")]
                    for (key, wire) in [("aspectRatio", "aspect_ratio"), ("imageSize", "image_size")] { if let value = config[key], value != .null { image[wire] = value } }
                    formats.append(.object(image))
                }
            }
        }
        if !formats.isEmpty { body["response_format"] = .array(formats) }
        if let modalities = google?.responseModalities { body["response_modalities"] = .array(modalities.map(JSONValue.string)) }
        if let previous = google?.previousInteractionId { body["previous_interaction_id"] = .string(previous) }
        if let tier = google?.serviceTier { body["service_tier"] = .string(tier) }
        if let store = google?.store { body["store"] = .bool(store) }
        if let background = google?.background { body["background"] = .bool(background) }
        if let environment = google?.environment, environment != .null {
            if agent == nil { warnings.append(.other(message: "google.interactions: environment is only supported when an agent is set; environment will be omitted from the request body.")) }
            else if case .string = environment { body["environment"] = environment }
            else if let environment = interactionObject(environment) {
                var result: JSONObject = ["type": .string("remote")]
                let sources = interactionArray(environment["sources"]).compactMap { value -> JSONValue? in
                    guard let source = interactionObject(value) else { return nil }
                    var fields: JSONObject = ["type": source["type"]!]
                    for key in source["type"] == .string("inline") ? ["content", "target"] : ["source", "target"] { if let value = source[key], value != .null { fields[key] = value } }
                    return .object(fields)
                }
                if !sources.isEmpty { result["sources"] = .array(sources) }
                if environment["network"] == .string("disabled") { result["network"] = .string("disabled") }
                else if let network = interactionObject(environment["network"]) {
                    result["network"] = .object(["allowlist": .array(interactionArray(network["allowlist"]).compactMap { value in
                        guard let entry = interactionObject(value) else { return nil }
                        var result: JSONObject = ["domain": entry["domain"]!]
                        if let transform = entry["transform"], transform != .null { result["transform"] = transform }
                        return .object(result)
                    })])
                }
                body["environment"] = .object(result)
            }
        }
        return .init(body: body, warnings: warnings, background: google?.background == true, timeout: google?.pollingTimeoutMs ?? 1_800_000)
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let request = try await prepare(options)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        var response = try await postJsonToAPI(url: "\(try config.resolveBaseURL?() ?? config.baseURL)/interactions", headers: headers, body: JSONValue.object(request.body), failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: googleInteractionResponseSchema), isAborted: options.abortSignal, fetch: config.fetch)
        if (agent != nil || request.background) && !isInteractionTerminal(response.value.status) {
            guard let id = response.value.id, !id.isEmpty else { throw InvalidArgumentError(argument: "interactionId", message: "google.interactions: cannot poll a background interaction without an id. The POST response did not include an interaction id.") }
            let started = Date()
            var wait = 1000
            do {
                while true {
                    if options.abortSignal?() == true || Task.isCancelled { throw CancellationError() }
                    if Date().timeIntervalSince(started) * 1000 > Double(request.timeout) { throw InvalidArgumentError(argument: "pollingTimeoutMs", message: "google.interactions: timed out polling interaction \(id) after \(request.timeout)ms.") }
                    try await delay(wait, abortSignal: options.abortSignal)
                    response = try await getFromAPI(url: "\(try config.resolveBaseURL?() ?? config.baseURL)/interactions/\(interactionPathSegment(id))", headers: headers, failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: googleInteractionResponseSchema), isAborted: options.abortSignal, fetch: config.fetch)
                    if isInteractionTerminal(response.value.status) { break }
                    wait = min(wait * 2, 10000)
                }
            } catch {
                if isAbortError(error) { await cancelInteraction(config: config, id: id, headers: headers) }
                throw error
            }
        }
        let value = response.value
        let id = value.id.flatMap { $0.isEmpty ? nil : $0 }
        let parsed = try parseInteractionOutputs(value.steps, id: id, generateId: config.generateId)
        return .init(content: parsed.content, finishReason: interactionFinish(value.status, functionCall: parsed.functionCall), usage: try interactionUsage(value.usage), providerMetadata: interactionMetadata(id: id, tier: value.service_tier ?? response.responseHeaders["x-gemini-service-tier"], usage: value.usage), request: .init(body: request.body), response: .init(id: id, timestamp: interactionDate(value.created), modelId: value.model, headers: response.responseHeaders, body: response.rawValue), warnings: request.warnings)
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let request = try await prepare(options)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        let url = "\(try config.resolveBaseURL?() ?? config.baseURL)/interactions"
        var body = request.body
        var backgroundId: String?
        var initial: AsyncThrowingStream<ParseJSONResult<GoogleInteractionEvent>, Error>?
        let responseHeaders: [String: String]
        if request.background {
            let posted = try await postJsonToAPI(url: url, headers: headers, body: JSONValue.object(body), failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: googleInteractionResponseSchema), isAborted: options.abortSignal, fetch: config.fetch)
            responseHeaders = posted.responseHeaders
            guard let id = posted.value.id, !id.isEmpty else { throw InvalidArgumentError(argument: "interactionId", message: "google.interactions: background POST response did not include an interaction id; cannot stream the result.") }
            backgroundId = id
            if isInteractionTerminal(posted.value.status) {
                let parts = try synthesizeInteractionStream(posted.value, warnings: request.warnings, generateId: config.generateId, raw: options.includeRawChunks == true, headerTier: responseHeaders["x-gemini-service-tier"])
                return .init(stream: AsyncThrowingStream { continuation in for part in parts { continuation.yield(part) }; continuation.finish() }, request: .init(body: body), response: .init(headers: responseHeaders))
            }
        } else {
            body["stream"] = .bool(true)
            let streamed = try await postJsonToAPI(url: url, headers: headers, body: JSONValue.object(body), failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: googleInteractionEventSchema), isAborted: options.abortSignal, fetch: config.fetch)
            responseHeaders = streamed.responseHeaders
            initial = streamed.value
        }
        let first = initial
        let id = backgroundId
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            let task = Task {
                continuation.yield(.streamStart(warnings: request.warnings))
                var state = GoogleInteractionsStreamState(generateId: config.generateId, serviceTier: responseHeaders["x-gemini-service-tier"])
                var source = first
                var lastEvent: String?
                var complete = false
                var attempt = 0
                do {
                    repeat {
                        var received = false
                        do {
                            if source == nil, let id {
                                var endpoint = "\(try config.resolveBaseURL?() ?? config.baseURL)/interactions/\(interactionPathSegment(id))?stream=true"
                                if let lastEvent { endpoint += "&last_event_id=\(interactionPathSegment(lastEvent))" }
                                var eventHeaders = headers; eventHeaders["accept"] = "text/event-stream"
                                source = try await getFromAPI(url: endpoint, headers: eventHeaders, failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: googleInteractionEventSchema), isAborted: options.abortSignal, fetch: config.fetch).value
                            }
                            if let source {
                                for try await event in source {
                                    received = true
                                    if options.includeRawChunks == true {
                                        switch event {
                                        case .success(_, let raw): if let value = try? jsonValue(from: raw) { continuation.yield(.raw(rawValue: value)) }
                                        case .failure(_, let raw): if let raw, let value = try? jsonValue(from: raw) { continuation.yield(.raw(rawValue: value)) }
                                        }
                                    }
                                    switch event {
                                    case .failure(let error, _): for part in state.failed(error) { continuation.yield(part) }
                                    case .success(let value, _):
                                        if let eventId = value.event_id, !eventId.isEmpty { lastEvent = eventId }
                                        if ["interaction.completed", "error"].contains(value.event_type) { complete = true }
                                        for part in try state.process(value) { continuation.yield(part) }
                                    }
                                }
                            }
                            source = nil
                            if id == nil || complete { break }
                            if received { attempt = 0 }
                            else {
                                attempt += 1
                                if attempt >= 3 { throw InvalidArgumentError(argument: "stream", message: "google.interactions: SSE stream closed without producing any events.") }
                                try await delay(500 * attempt, abortSignal: options.abortSignal)
                            }
                        } catch {
                            source = nil
                            if isAbortError(error) || Task.isCancelled || options.abortSignal?() == true || id == nil { throw error }
                            attempt += 1
                            if attempt >= 3 { throw error }
                            try await delay(500 * attempt, abortSignal: options.abortSignal)
                        }
                    } while !complete
                    continuation.yield(try state.finish())
                    continuation.finish()
                } catch {
                    if !complete, let id, isAbortError(error) || Task.isCancelled || options.abortSignal?() == true { await cancelInteraction(config: config, id: id, headers: headers) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return .init(stream: stream, request: .init(body: body), response: .init(headers: responseHeaders))
    }
}

private func isInteractionTerminal(_ status: String) -> Bool { ["completed", "failed", "cancelled", "incomplete"].contains(status) }
private func interactionPathSegment(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")) ?? value }
private func cancelInteraction(config: GoogleInteractionsLanguageModel.Config, id: String, headers: [String: String]) async {
    await Task.detached {
        guard let base = try? config.resolveBaseURL?() ?? config.baseURL,
              let url = URL(string: "\(base)/interactions/\(interactionPathSegment(id))/cancel") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let response = try? await (config.fetch ?? defaultFetchFunction())(request) { _ = try? await response.body.collectData() }
    }.value
}
