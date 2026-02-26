import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-language-model.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

public final class GatewayLanguageModel: LanguageModelV3 {
    private static let wildcardRegex: NSRegularExpression = {
        // Matches any URL path
        return try! NSRegularExpression(pattern: ".*", options: [])
    }()

    private let modelIdentifier: GatewayModelId
    private let config: GatewayLanguageModelConfig

    init(modelId: GatewayModelId, config: GatewayLanguageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v3" }

    public var provider: String { config.provider }

    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        ["*/*": [GatewayLanguageModel.wildcardRegex]]
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareArguments(options: options)
        let resolvedHeaders = try await resolve(config.headers)
        let authMethod = parseAuthMethod(from: resolvedHeaders.compactMapValues { $0 })
        let o11yHeaders = try await resolve(config.o11yHeaders)

        let requestHeaders = combineHeaders(
            resolvedHeaders,
            options.headers?.mapValues { Optional($0) },
            getModelConfigHeaders(streaming: false),
            o11yHeaders
        ).compactMapValues { $0 }

        do {
            let response = try await postJsonToAPI(
                url: getUrl(),
                headers: requestHeaders,
                body: prepared.body,
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewayJSONSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            let parsed = try parseGatewayGeneratePayload(from: response.value)
            let requestInfo = LanguageModelV3RequestInfo(body: jsonValueToFoundation(prepared.body))
            let responseInfo = LanguageModelV3ResponseInfo(
                id: parsed.id,
                timestamp: parsed.created,
                modelId: parsed.model,
                headers: response.responseHeaders,
                body: response.rawValue
            )

            return LanguageModelV3GenerateResult(
                content: parsed.content,
                finishReason: parsed.finishReason,
                usage: parsed.usage,
                providerMetadata: parsed.providerMetadata,
                request: requestInfo,
                response: responseInfo,
                warnings: prepared.warnings
            )
        } catch {
            throw asGatewayError(error, authMethod: authMethod)
        }
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareArguments(options: options)
        let resolvedHeaders = try await resolve(config.headers)
        let authMethod = parseAuthMethod(from: resolvedHeaders.compactMapValues { $0 })
        let o11yHeaders = try await resolve(config.o11yHeaders)

        let requestHeaders = combineHeaders(
            resolvedHeaders,
            options.headers?.mapValues { Optional($0) },
            getModelConfigHeaders(streaming: true),
            o11yHeaders
        ).compactMapValues { $0 }

        let streamResponse: ResponseHandlerResult<AsyncThrowingStream<ParseJSONResult<JSONValue>, Error>>
        do {
            streamResponse = try await postJsonToAPI(
                url: getUrl(),
                headers: requestHeaders,
                body: prepared.body,
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: gatewayJSONSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
        } catch {
            throw asGatewayError(error, authMethod: authMethod)
        }

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            if !prepared.warnings.isEmpty {
                continuation.yield(.streamStart(warnings: prepared.warnings))
            }

            Task {
                do {
                    for try await chunk in streamResponse.value {
                        switch chunk {
                        case .success(let value, _):
                            if let part = try mapGatewayStreamPart(from: value, includeRawChunks: options.includeRawChunks == true) {
                                continuation.yield(part)
                            }
                        case .failure(let error, let raw):
                            _ = raw
                            throw error
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        let requestInfo = LanguageModelV3RequestInfo(body: jsonValueToFoundation(prepared.body))
        let responseInfo = LanguageModelV3StreamResponseInfo(headers: streamResponse.responseHeaders)

        return LanguageModelV3StreamResult(stream: stream, request: requestInfo, response: responseInfo)
    }

    // MARK: - Helpers

    private func getUrl() -> String {
        "\(config.baseURL)/language-model"
    }

    private func getModelConfigHeaders(streaming: Bool) -> [String: String?] {
        [
            "ai-language-model-specification-version": "3",
            "ai-language-model-id": modelIdentifier.rawValue,
            "ai-language-model-streaming": String(streaming)
        ]
    }

    private func prepareArguments(options: LanguageModelV3CallOptions) async throws -> (body: JSONValue, warnings: [SharedV3Warning]) {
        let encodedOptions = encodeFileParts(in: options)
        let requestBody = GatewayLanguageModelRequestBody(options: encodedOptions)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(requestBody)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        let json = try jsonValue(from: jsonObject)
        return (body: json, warnings: [])
    }

    private func encodeFileParts(in options: LanguageModelV3CallOptions) -> LanguageModelV3CallOptions {
        let encodedPrompt = encodePrompt(options.prompt)
        return LanguageModelV3CallOptions(
            prompt: encodedPrompt,
            maxOutputTokens: options.maxOutputTokens,
            temperature: options.temperature,
            stopSequences: options.stopSequences,
            topP: options.topP,
            topK: options.topK,
            presencePenalty: options.presencePenalty,
            frequencyPenalty: options.frequencyPenalty,
            responseFormat: options.responseFormat,
            seed: options.seed,
            tools: options.tools,
            toolChoice: options.toolChoice,
            includeRawChunks: options.includeRawChunks,
            abortSignal: nil,
            headers: options.headers,
            providerOptions: options.providerOptions
        )
    }

    private func encodePrompt(_ prompt: LanguageModelV3Prompt) -> LanguageModelV3Prompt {
        prompt.map { message in
            switch message {
            case .system:
                return message
            case .user(let parts, let providerOptions):
                let updated = parts.map { part -> LanguageModelV3UserMessagePart in
                    switch part {
                    case .text:
                        return part
                    case .file(let filePart):
                        return .file(encodeFilePart(filePart))
                    }
                }
                return .user(content: updated, providerOptions: providerOptions)
            case .assistant(let parts, let providerOptions):
                let updated = parts.map { part -> LanguageModelV3MessagePart in
                    switch part {
                    case .file(let filePart):
                        return .file(encodeFilePart(filePart))
                    default:
                        return part
                    }
                }
                return .assistant(content: updated, providerOptions: providerOptions)
            case .tool:
                return message
            }
        }
    }

    private func encodeFilePart(_ part: LanguageModelV3FilePart) -> LanguageModelV3FilePart {
        switch part.data {
        case .data(let data):
            let base64 = data.base64EncodedString()
            let mediaType = part.mediaType.isEmpty ? "application/octet-stream" : part.mediaType
            let urlString = "data:\(mediaType);base64,\(base64)"
            guard let url = URL(string: urlString) else {
                return part
            }
            return LanguageModelV3FilePart(
                data: .url(url),
                mediaType: part.mediaType,
                filename: part.filename,
                providerOptions: part.providerOptions
            )
        case .base64, .url:
            return part
        }
    }
}

// MARK: - Request Body Encoding

private struct GatewayLanguageModelRequestBody: Encodable {
    let prompt: LanguageModelV3Prompt
    let maxOutputTokens: Int?
    let temperature: Double?
    let stopSequences: [String]?
    let topP: Double?
    let topK: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let responseFormat: LanguageModelV3ResponseFormat?
    let seed: Int?
    let tools: [LanguageModelV3Tool]?
    let toolChoice: LanguageModelV3ToolChoice?
    let includeRawChunks: Bool?
    let headers: [String: String]?
    let providerOptions: SharedV3ProviderOptions?

    init(options: LanguageModelV3CallOptions) {
        self.prompt = options.prompt
        self.maxOutputTokens = options.maxOutputTokens
        self.temperature = options.temperature
        self.stopSequences = options.stopSequences
        self.topP = options.topP
        self.topK = options.topK
        self.presencePenalty = options.presencePenalty
        self.frequencyPenalty = options.frequencyPenalty
        self.responseFormat = options.responseFormat
        self.seed = options.seed
        self.tools = options.tools
        self.toolChoice = options.toolChoice
        self.includeRawChunks = options.includeRawChunks
        self.headers = options.headers
        self.providerOptions = options.providerOptions
    }
}

// MARK: - Streaming Schema

private let gatewayJSONSchema = FlexibleSchema(
    Schema<JSONValue>.codable(
        JSONValue.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct GatewayParsedGeneratePayload: Sendable {
    let id: String?
    let model: String?
    let created: Date?
    let content: [LanguageModelV3Content]
    let finishReason: LanguageModelV3FinishReason
    let usage: LanguageModelV3Usage
    let providerMetadata: SharedV3ProviderMetadata?
}

private func parseGatewayGeneratePayload(from value: JSONValue) throws -> GatewayParsedGeneratePayload {
    guard case .object(let dict) = value else {
        return GatewayParsedGeneratePayload(
            id: nil,
            model: nil,
            created: nil,
            content: [],
            finishReason: .init(unified: .other),
            usage: .init(),
            providerMetadata: nil
        )
    }

    let id = dict["id"].flatMap(stringValue)
    let model = dict["model"].flatMap(stringValue)
    let created = dict["created"].flatMap(parseGatewayTimestamp)

    let content: [LanguageModelV3Content]
    if let rawContent = dict["content"] {
        content = (try? decodeGatewayContentArray(from: rawContent)) ?? []
    } else {
        content = []
    }

    let finishValue = dict["finish_reason"] ?? dict["finishReason"]
    let finishReason = parseGatewayFinishReason(from: finishValue)

    let usageValue = dict["usage"]
    let usage = parseGatewayUsage(from: usageValue)

    let providerMetadataValue = dict["provider_metadata"] ?? dict["providerMetadata"]
    let providerMetadata = providerMetadataValue.flatMap { try? decodeGatewayProviderMetadata(from: $0) }

    return GatewayParsedGeneratePayload(
        id: id,
        model: model,
        created: created,
        content: content,
        finishReason: finishReason,
        usage: usage,
        providerMetadata: providerMetadata
    )
}

private func mapGatewayStreamPart(
    from value: JSONValue,
    includeRawChunks: Bool
) throws -> LanguageModelV3StreamPart? {
    guard case .object(let dict) = value else {
        return nil
    }

    guard let type = dict["type"].flatMap(stringValue) else {
        return nil
    }

    switch type {
    case "raw":
        guard includeRawChunks else { return nil }
        let rawValue = dict["rawValue"] ?? .null
        return .raw(rawValue: rawValue)

    case "stream-start":
        let warnings = (dict["warnings"].flatMap { try? decodeGatewayCodable([SharedV3Warning].self, from: $0) }) ?? []
        return .streamStart(warnings: warnings)

    case "text-start":
        let id = dict["id"].flatMap(stringValue) ?? "text"
        let providerMetadata = dict["providerMetadata"].flatMap { try? decodeGatewayProviderMetadata(from: $0) }
        return .textStart(id: id, providerMetadata: providerMetadata)

    case "text-delta":
        let id = dict["id"].flatMap(stringValue) ?? "text"
        let delta = dict["delta"].flatMap(stringValue) ?? dict["textDelta"].flatMap(stringValue) ?? ""
        let providerMetadata = dict["providerMetadata"].flatMap { try? decodeGatewayProviderMetadata(from: $0) }
        return .textDelta(id: id, delta: delta, providerMetadata: providerMetadata)

    case "text-end":
        let id = dict["id"].flatMap(stringValue) ?? "text"
        let providerMetadata = dict["providerMetadata"].flatMap { try? decodeGatewayProviderMetadata(from: $0) }
        return .textEnd(id: id, providerMetadata: providerMetadata)

    case "response-metadata":
        let id = dict["id"].flatMap(stringValue)
        let modelId = dict["modelId"].flatMap(stringValue)
        let timestamp = dict["timestamp"].flatMap(parseGatewayTimestamp)
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)

    case "finish":
        let finishValue = dict["finishReason"] ?? dict["finish_reason"]
        let finishReason = parseGatewayFinishReason(from: finishValue)
        let usage = parseGatewayUsage(from: dict["usage"])
        let providerMetadata = dict["providerMetadata"].flatMap { try? decodeGatewayProviderMetadata(from: $0) }
        return .finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata)

    case "error":
        let errorValue = dict["error"] ?? .null
        return .error(error: errorValue)

    default:
        // Best-effort decode for fully-formed V3 chunks (tool calls/results, sources, etc).
        if let decoded = try? decodeGatewayCodable(LanguageModelV3StreamPart.self, from: value) {
            if case .raw = decoded, !includeRawChunks {
                return nil
            }
            return decoded
        }
        return nil
    }
}

private func decodeGatewayContentArray(from value: JSONValue) throws -> [LanguageModelV3Content] {
    switch value {
    case .array(let array):
        return try array.map { try decodeGatewayCodable(LanguageModelV3Content.self, from: $0) }
    default:
        return [try decodeGatewayCodable(LanguageModelV3Content.self, from: value)]
    }
}

private func decodeGatewayProviderMetadata(from value: JSONValue) throws -> SharedV3ProviderMetadata {
    try decodeGatewayCodable(SharedV3ProviderMetadata.self, from: value)
}

private func decodeGatewayCodable<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = try JSONSerialization.data(withJSONObject: jsonValueToFoundation(value), options: [])
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
}

private func stringValue(_ value: JSONValue) -> String? {
    guard case .string(let text) = value else { return nil }
    return text
}

private func intValue(_ value: JSONValue?) -> Int? {
    guard let value else { return nil }
    switch value {
    case .number(let number):
        return Int(number)
    case .string(let text):
        return Int(text)
    default:
        return nil
    }
}

private func parseGatewayTimestamp(_ value: JSONValue) -> Date? {
    switch value {
    case .number(let seconds):
        return Date(timeIntervalSince1970: seconds)
    case .string(let text):
        if let date = ISO8601DateFormatter().date(from: text) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    default:
        return nil
    }
}

private func parseGatewayFinishReason(from value: JSONValue?) -> LanguageModelV3FinishReason {
    guard let value else {
        return LanguageModelV3FinishReason(unified: .other)
    }

    if case .string(let raw) = value {
        return LanguageModelV3FinishReason(unified: unifiedFinishReason(from: raw), raw: raw)
    }

    if let decoded = try? decodeGatewayCodable(LanguageModelV3FinishReason.self, from: value) {
        return decoded
    }

    return LanguageModelV3FinishReason(unified: .other)
}

private func unifiedFinishReason(from raw: String) -> LanguageModelV3FinishReason.Unified {
    switch raw {
    case "stop":
        return .stop
    case "length":
        return .length
    case "content-filter", "content_filter":
        return .contentFilter
    case "tool-calls", "tool_calls":
        return .toolCalls
    case "error":
        return .error
    default:
        return .other
    }
}

private func parseGatewayUsage(from value: JSONValue?) -> LanguageModelV3Usage {
    guard let value else {
        return LanguageModelV3Usage()
    }

    if let decoded = try? decodeGatewayCodable(LanguageModelV3Usage.self, from: value) {
        return decoded
    }

    guard case .object(let dict) = value else {
        return LanguageModelV3Usage(raw: value)
    }

    let promptTokens = intValue(dict["prompt_tokens"] ?? dict["promptTokens"])
    let completionTokens = intValue(dict["completion_tokens"] ?? dict["completionTokens"])

    return LanguageModelV3Usage(
        inputTokens: .init(total: promptTokens, noCache: promptTokens),
        outputTokens: .init(total: completionTokens, text: completionTokens),
        raw: value
    )
}
