import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GoogleLanguageModel: LanguageModelV4 {
    public struct DownloadToolResultFiles: Sendable {
        public let maxBytes: Int
        public let supportsGoogleCloudStorageUrls: Bool
        public init(maxBytes: Int, supportsGoogleCloudStorageUrls: Bool = false) {
            self.maxBytes = maxBytes
            self.supportsGoogleCloudStorageUrls = supportsGoogleCloudStorageUrls
        }
    }
    public struct Config: Sendable {
        public let provider: String
        public let baseURL: String
        public let headers: @Sendable () throws -> [String: String?]
        public let fetch: FetchFunction?
        public let generateId: @Sendable () -> String
        public let supportedUrls: @Sendable () -> [String: [NSRegularExpression]]
        public let downloadToolResultFiles: DownloadToolResultFiles?
        public let resolveBaseURL: (@Sendable () throws -> String)?
        public init(
            provider: String,
            baseURL: String,
            headers: @escaping @Sendable () throws -> [String: String?] = { [:] },
            fetch: FetchFunction? = nil,
            generateId: @escaping @Sendable () -> String = generateID,
            supportedUrls: @escaping @Sendable () -> [String: [NSRegularExpression]] = { [:] },
            downloadToolResultFiles: DownloadToolResultFiles? = nil,
            resolveBaseURL: (@Sendable () throws -> String)? = nil
        ) {
            self.provider = provider; self.baseURL = baseURL; self.headers = headers
            self.fetch = fetch; self.generateId = generateId; self.supportedUrls = supportedUrls
            self.downloadToolResultFiles = downloadToolResultFiles
            self.resolveBaseURL = resolveBaseURL
        }
    }
    private struct Request {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
        let names: [String]
        let extraHeaders: [String: String?]
        let codeToolName: String
        let jsonToolName: String?
    }
    private let config: Config
    public let modelId: String
    public var provider: String { config.provider }
    public var supportedUrls: [String: [NSRegularExpression]] { get async throws { config.supportedUrls() } }
    public init(modelId: GoogleModelId, config: Config) { self.modelId = modelId.rawValue; self.config = config }

    private func prepare(_ options: LanguageModelV4CallOptions, streaming: Bool = false) async throws -> Request {
        var warnings: [SharedV4Warning] = []
        let names = googleProviderOptionsNames(provider)
        var google: GoogleLanguageModelOptions?
        for name in names + (names.contains("google") ? [] : ["google"]) {
            google = try await parseProviderOptions(provider: name, providerOptions: options.providerOptions, schema: googleLanguageModelOptionsSchema)
            if google != nil { break }
        }
        let vertex = provider.hasPrefix("google.vertex.")
        let capabilities = googleModelCapabilities(modelId)
        if options.tools?.contains(where: { if case .provider(let tool) = $0 { return tool.id == "google.vertex_rag_store" }; return false }) == true && !vertex {
            warnings.append(.other(message: "The 'vertex_rag_store' tool is only supported with the Google Vertex provider and might not be supported or could behave unexpectedly with the current Google provider (\(provider))."))
        }
        if google?.streamFunctionCallArguments == true && !vertex {
            warnings.append(.other(message: "'streamFunctionCallArguments' is only supported on the Vertex AI API and will be ignored with the current Google provider (\(provider)). See https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/function-calling#streaming-fc"))
        }
        if google?.serviceTier != nil && vertex {
            warnings.append(.other(message: "'serviceTier' is a Gemini API option and is not supported on Vertex AI. Use 'sharedRequestType' (and optionally 'requestType') instead. See https://docs.cloud.google.com/vertex-ai/generative-ai/docs/priority-paygo"))
        }
        if (google?.sharedRequestType != nil || google?.requestType != nil) && !vertex {
            warnings.append(.other(message: "'sharedRequestType' and 'requestType' are Vertex AI options and are ignored with the current Google provider (\(provider))."))
        }
        var extraHeaders: [String: String?] = [:]
        if vertex {
            if let value = google?.sharedRequestType { extraHeaders["X-Vertex-AI-LLM-Shared-Request-Type"] = value }
            if let value = google?.requestType { extraHeaders["X-Vertex-AI-LLM-Request-Type"] = value }
        }
        let gemma = modelId.lowercased().hasPrefix("gemma-")
        let prompt = try await downloadGoogleToolResultFiles(options.prompt, config: config, capabilities: capabilities, abortSignal: options.abortSignal)
        let converted = try convertToGoogleMessages(prompt, options: .init(
            isGemmaModel: gemma, providerOptionsName: names[0],
            supportsFunctionResponseParts: capabilities.usesGemini3Features,
            includeFunctionCallIds: !vertex, isGemini3Model: capabilities.usesGemini3Features,
            supportsGoogleCloudStorageUrls: capabilities.usesGemini3Features && config.downloadToolResultFiles?.supportsGoogleCloudStorageUrls == true
        ), onWarning: { warnings.append($0) })
        let encoded = encodeGooglePrompt(converted)
        var tools = options.tools
        var choice = options.toolChoice
        var jsonToolName: String?
        var format = options.responseFormat
        if case .json(let schema?, _, let description) = format,
           tools?.contains(where: { if case .function = $0 { return true }; return false }) == true,
           googleModelMatches(modelId, "(^|/)gemini-"),
           !capabilities.usesGemini3Features || choice == .required || { if case .tool = choice { return true }; return false }() {
            let existing = Set((tools ?? []).map { tool in switch tool { case .function(let f): return f.name; case .provider(let p): return p.name } })
            var name = "json"
            var suffix = 1
            while existing.contains(name) { name = "json_\(suffix)"; suffix += 1 }
            jsonToolName = name
            tools = (tools ?? []) + [.function(.init(name: name, inputSchema: schema, description: description ?? "Respond with a JSON object."))]
            if case .tool = choice {} else if choice == LanguageModelV4ToolChoice.none { choice = .tool(toolName: name) } else { choice = .required }
            format = nil
        }
        let preparedTools = prepareGoogleTools(tools: tools, toolChoice: choice, modelId: .init(rawValue: modelId), isVertexProvider: vertex)
        let codeToolName = (tools ?? []).compactMap { tool -> String? in
            if case .provider(let p) = tool, p.id == "google.code_execution" { return p.name }; return nil
        }.first ?? "code_execution"
        let gemini25 = !vertex && googleModelMatches(modelId, "(^|[/.])gemini-2\\.5(?:[.-]|$)")
        var generation: [String: JSONValue] = [:]
        if let value = options.maxOutputTokens { generation["maxOutputTokens"] = .number(Double(value)) }
        if let value = options.temperature { generation["temperature"] = .number(value) }
        if let value = options.topP { generation["topP"] = .number(value) }
        if let value = options.topK { generation["topK"] = .number(Double(value)) }
        if let value = options.seed { generation["seed"] = .number(Double(value)) }
        if let value = options.stopSequences { generation["stopSequences"] = .array(value.map(JSONValue.string)) }
        for (key, value) in [("frequencyPenalty", options.frequencyPenalty), ("presencePenalty", options.presencePenalty)] {
            if let value {
                if gemini25 { warnings.append(.unsupported(feature: key, details: nil)) }
                else { generation[key] = .number(value) }
            }
        }
        if case .json(let schema, _, _) = format {
            generation["responseMimeType"] = .string("application/json")
            if let schema, google?.structuredOutputs ?? true { generation["responseJsonSchema"] = sanitizeGoogleResponseSchema(schema) }
        }
        if google?.audioTimestamp == true { generation["audioTimestamp"] = .bool(true) }
        if let value = google?.responseModalities { generation["responseModalities"] = .array(value.map { .string($0.rawValue) }) }
        var thinking = google?.thinkingConfig
        if thinking?.thinkingBudget == nil && thinking?.thinkingLevel == nil, isCustomReasoning(options.reasoning), let reasoning = options.reasoning {
            var resolved = googleThinkingConfig(reasoning, modelId: modelId, warnings: &warnings)
            resolved?.includeThoughts = thinking?.includeThoughts
            thinking = resolved ?? thinking
        }
        if let value = thinking {
            var object: [String: JSONValue] = [:]
            if let include = value.includeThoughts { object["includeThoughts"] = .bool(include) }
            if let budget = value.thinkingBudget { object["thinkingBudget"] = .number(budget) }
            if let level = value.thinkingLevel { object["thinkingLevel"] = .string(level.rawValue) }
            generation["thinkingConfig"] = .object(object)
        }
        if let value = google?.mediaResolution { generation["mediaResolution"] = .string(value.rawValue) }
        if let image = google?.imageConfig {
            var object: [String: JSONValue] = [:]
            if let value = image.aspectRatio { object["aspectRatio"] = .string(value.rawValue) }
            if let value = image.imageSize { object["imageSize"] = .string(value.rawValue) }
            var dropped: [String] = []
            for (key, value) in [("personGeneration", image.personGeneration.map(JSONValue.string)), ("prominentPeople", image.prominentPeople.map(JSONValue.string)), ("imageOutputOptions", image.imageOutputOptions)] {
                if let value { if vertex { object[key] = value } else { dropped.append("'imageConfig.\(key)'") } }
            }
            if !dropped.isEmpty { warnings.append(.other(message: "\(dropped.joined(separator: ", ")) \(dropped.count == 1 ? "is a Vertex AI option and is" : "are Vertex AI options and are") ignored with the current Google provider (\(provider)).")) }
            generation["imageConfig"] = .object(object)
        }
        var body: [String: JSONValue] = ["contents": encoded.contents, "generationConfig": .object(generation)]
        if let system = encoded.system { body["systemInstruction"] = system }
        let safety = google?.safetySettings ?? google?.threshold.map { threshold in
            [GoogleSafetyCategory.hateSpeech, .dangerousContent, .harassment, .sexuallyExplicit].map { .init(category: $0, threshold: threshold) }
        }
        if let safety { body["safetySettings"] = .array(safety.map { .object(["category": .string($0.category.rawValue), "threshold": .string($0.threshold.rawValue)]) }) }
        if let value = google?.cachedContent { body["cachedContent"] = .string(value) }
        if let value = google?.labels { body["labels"] = .object(value.mapValues(JSONValue.string)) }
        if let value = google?.serviceTier, !vertex { body["serviceTier"] = .string(value) }
        if let value = google?.continuationToken { body["continuationToken"] = .string(value) }
        if let value = preparedTools.tools { body["tools"] = value }
        var toolConfig: [String: JSONValue] = [:]
        if case .object(let value) = preparedTools.toolConfig { toolConfig = value }
        if streaming && vertex && google?.streamFunctionCallArguments == true {
            var function: [String: JSONValue] = [:]
            if case .object(let value) = toolConfig["functionCallingConfig"] { function = value }
            function["streamFunctionCallArguments"] = .bool(true)
            toolConfig["functionCallingConfig"] = .object(function)
        }
        if let value = google?.retrievalConfig {
            var retrieval: [String: JSONValue] = [:]
            if let location = value.latLng { retrieval["latLng"] = .object(["latitude": .number(location.latitude), "longitude": .number(location.longitude)]) }
            toolConfig["retrievalConfig"] = .object(retrieval)
        }
        if !toolConfig.isEmpty { body["toolConfig"] = .object(toolConfig) }
        return .init(body: body, warnings: warnings + preparedTools.toolWarnings, names: names, extraHeaders: extraHeaders, codeToolName: codeToolName, jsonToolName: jsonToolName)
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let request = try await prepare(options)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }, request.extraHeaders).compactMapValues { $0 }
        var body = request.body
        var content: [LanguageModelV4Content] = []
        var usage: [String: JSONValue]?
        var initialPromptTokens: JSONValue?
        var firstHop = true
        var continued = false
        while true {
            let response = try await postJsonToAPI(url: "\(try config.resolveBaseURL?() ?? config.baseURL)/\(getGoogleModelPath(modelId)):generateContent", headers: headers, body: JSONValue.object(body), failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: googleResponseSchema), isAborted: options.abortSignal, fetch: config.fetch)
            let value = response.value
            usage = addGoogleUsage(usage, value.usageMetadata)
            if firstHop { initialPromptTokens = value.usageMetadata?["promptTokenCount"].flatMap { $0 == .null ? nil : $0 }; firstHop = false }
            let blocked = googlePromptBlockReason(value.promptFeedback)
            var mapper = GoogleContentMapper(names: request.names, generateId: config.generateId, codeToolName: request.codeToolName, jsonToolName: request.jsonToolName)
            let currentContent = try mapper.convert(value.candidates?.first?.content?.parts ?? [])
            content += currentContent
            content += googleSources(value.candidates?.first?.groundingMetadata, generateId: config.generateId).map(LanguageModelV4Content.source)
            let candidate = value.candidates?.first
            if candidate?.finishReason == "CONTINUATION", let token = candidate?.continuationToken {
                continued = true
                body["continuationToken"] = .string(token)
                continue
            }
            let raw = candidate?.finishReason ?? blocked
            let hasCalls = currentContent.contains { if case .toolCall(let call) = $0 { return call.providerExecuted != true }; return false }
            return .init(content: content, finishReason: .init(unified: candidate?.finishReason == nil && blocked != nil ? .contentFilter : mapGoogleFinishReason(finishReason: raw, hasToolCalls: hasCalls), raw: raw), usage: try convertGoogleUsage(usage), providerMetadata: googleResponseMetadata(response: value, usage: usage, names: request.names, initialPromptTokens: continued ? initialPromptTokens : nil), request: .init(body: request.body), response: .init(id: value.responseId, headers: response.responseHeaders, body: response.rawValue), warnings: request.warnings)
        }
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let request = try await prepare(options, streaming: true)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }, request.extraHeaders).compactMapValues { $0 }
        let url = "\(try config.resolveBaseURL?() ?? config.baseURL)/\(getGoogleModelPath(modelId)):streamGenerateContent?alt=sse"
        let first = try await postJsonToAPI(url: url, headers: headers, body: JSONValue.object(request.body), failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: googleResponseSchema), isAborted: options.abortSignal, fetch: config.fetch)
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            let task = Task {
                continuation.yield(.streamStart(warnings: request.warnings))
                var state = GoogleStreamState(names: request.names, generateId: config.generateId, codeToolName: request.codeToolName)
                var source = first.value
                do {
                    while true {
                        var pendingToken: String?
                        for try await parsed in source {
                            if options.includeRawChunks == true {
                                switch parsed {
                                case .success(_, let raw): if let value = try? jsonValue(from: raw) { continuation.yield(.raw(rawValue: value)) }
                                case .failure(_, let raw): if let raw, let value = try? jsonValue(from: raw) { continuation.yield(.raw(rawValue: value)) }
                                }
                            }
                            switch parsed {
                            case .failure(let error, _): continuation.yield(.error(error: .error(error)))
                            case .success(let value, _):
                                for part in try state.process(value) { continuation.yield(part) }
                                if value.candidates?.first?.finishReason == "CONTINUATION", let token = value.candidates?.first?.continuationToken { pendingToken = token }
                            }
                        }
                        guard let token = pendingToken else { break }
                        var body = request.body
                        body["continuationToken"] = .string(token)
                        do {
                            source = try await postJsonToAPI(url: url, headers: headers, body: JSONValue.object(body), failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: googleResponseSchema), isAborted: options.abortSignal, fetch: config.fetch).value
                        } catch {
                            continuation.yield(.error(error: .error(error)))
                            break
                        }
                    }
                    for part in try state.finish() { continuation.yield(part) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return .init(stream: request.jsonToolName.map { convertJsonResponseToolStream(stream, toolName: $0) } ?? stream, request: .init(body: request.body), response: .init(headers: first.responseHeaders))
    }
}

private func googleThinkingConfig(_ reasoning: LanguageModelV4ReasoningEffort, modelId: String, warnings: inout [SharedV4Warning]) -> GoogleThinkingConfig? {
    let lower = modelId.lowercased()
    if googleModelCapabilities(modelId).usesGemini3Features && !lower.contains("gemini-3-pro-image") {
        let model = modelId.lowercased().components(separatedBy: "/").last ?? modelId.lowercased()
        let minimum: String = model == "gemini-flash-latest" || googleModelMatches(model, "^gemini-[3-9](?:\\.\\d+)?-pro(?:$|-)") || googleModelMatches(model, "^gemini-(?:3\\.[7-9]|[4-9]\\.\\d+)-flash(?:$|-(?!lite(?:-|$)))") ? "low" : "minimal"
        if reasoning == .none { return .init(thinkingLevel: .init(rawValue: minimum)) }
        let level = mapReasoningToProviderEffort(reasoning: reasoning, effortMap: [.minimal: minimum, .low: "low", .medium: "medium", .high: "high", .xhigh: "high", .max: "high"], warnings: &warnings)
        return level.flatMap { GoogleThinkingLevel(rawValue: $0) }.map { .init(thinkingLevel: $0) }
    }
    if reasoning == .none { return .init(thinkingBudget: 0) }
    let max = modelId.lowercased().contains("2.5-pro") || modelId.lowercased().contains("gemini-3-pro-image") ? 32768 : 24576
    return mapReasoningToProviderBudget(reasoning: reasoning, maxOutputTokens: 65536, maxReasoningBudget: max, minReasoningBudget: 0, warnings: &warnings).map { .init(thinkingBudget: Double($0)) }
}

private func downloadGoogleToolResultFiles(_ prompt: LanguageModelV4Prompt, config: GoogleLanguageModel.Config, capabilities: GoogleModelCapabilities, abortSignal: (@Sendable () -> Bool)?) async throws -> LanguageModelV4Prompt {
    guard let downloads = config.downloadToolResultFiles else { return prompt }
    func transform(_ part: LanguageModelV4ToolResultPart) async throws -> LanguageModelV4ToolResultPart {
        guard case .content(let values) = part.output else { return part }
        var result: [LanguageModelV4ToolResultContentPart] = []
        for value in values {
            guard case .file(.url(let url, _), let mediaType, let filename, let providerOptions) = value else { result.append(value); continue }
            if capabilities.usesGemini3Features && downloads.supportsGoogleCloudStorageUrls && url.scheme == "gs" && ["image/png", "image/jpeg", "image/webp", "application/pdf", "text/plain"].contains(mediaType) { result.append(value); continue }
            let blob = try await downloadBlob(url: url, maxBytes: downloads.maxBytes, isAborted: abortSignal)
            let resolved = detectMediaType(data: blob.data, topLevelType: "image") ?? (!isFullMediaType(mediaType) ? blob.mediaType : nil) ?? mediaType
            result.append(.file(data: .data(blob.data), mediaType: resolved, filename: filename, providerOptions: providerOptions))
        }
        return .init(toolCallId: part.toolCallId, toolName: part.toolName, output: .content(value: result), providerOptions: part.providerOptions)
    }
    var result: LanguageModelV4Prompt = []
    for message in prompt {
        switch message {
        case .assistant(let parts, let providerOptions):
            var content: [LanguageModelV4MessagePart] = []
            for part in parts { if case .toolResult(let tool) = part { content.append(.toolResult(try await transform(tool))) } else { content.append(part) } }
            result.append(.assistant(content: content, providerOptions: providerOptions))
        case .tool(let parts, let providerOptions):
            var content: [LanguageModelV4ToolMessagePart] = []
            for part in parts { if case .toolResult(let tool) = part { content.append(.toolResult(try await transform(tool))) } else { content.append(part) } }
            result.append(.tool(content: content, providerOptions: providerOptions))
        default: result.append(message)
        }
    }
    return result
}
