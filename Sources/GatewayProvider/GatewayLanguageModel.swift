import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-language-model.ts
// Upstream commit: 77db222ee
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
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewayGenerateResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            let providerMetadata = response.value.providerMetadata
            let requestInfo = LanguageModelV3RequestInfo(body: jsonValueToFoundation(prepared.body))
            let responseInfo = LanguageModelV3ResponseInfo(
                id: response.value.id,
                timestamp: response.value.created,
                modelId: response.value.model,
                headers: response.responseHeaders,
                body: response.rawValue
            )

            return LanguageModelV3GenerateResult(
                content: response.value.content,
                finishReason: response.value.finishReason,
                usage: response.value.usage,
                providerMetadata: providerMetadata,
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

        let streamResponse: ResponseHandlerResult<AsyncThrowingStream<ParseJSONResult<LanguageModelV3StreamPart>, Error>>
        do {
            streamResponse = try await postJsonToAPI(
                url: getUrl(),
                headers: requestHeaders,
                body: prepared.body,
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: gatewayStreamSchema),
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
                        if options.includeRawChunks == true, let raw = chunk.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch chunk {
                        case .success(let part, _):
                            if case .raw = part, options.includeRawChunks != true {
                                continue
                            }
                            continuation.yield(part)
                        case .failure(let error, let raw):
                            if let raw, let json = try? jsonValue(from: raw) {
                                continuation.yield(.error(error: json))
                            }
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
            "ai-language-model-specification-version": "2",
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

private let gatewayStreamSchema = FlexibleSchema(
    Schema<LanguageModelV3StreamPart>.codable(
        LanguageModelV3StreamPart.self,
        jsonSchema: .object(["type": .string("object")]),
        configureDecoder: { decoder in
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    )
)

private extension ParseJSONResult where Output == LanguageModelV3StreamPart {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            guard let raw else { return nil }
            return try? jsonValue(from: raw)
        }
    }
}

// MARK: - Response Schema

private struct GatewayGenerateResponse: Decodable, Sendable {
    let id: String?
    let model: String?
    let created: Date?
    let content: [LanguageModelV3Content]
    let finishReason: LanguageModelV3FinishReason
    let usage: LanguageModelV3Usage
    let providerMetadata: SharedV3ProviderMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case created
        case content
        case finishReason = "finish_reason"
        case usage
        case providerMetadata = "provider_metadata"
    }
}

private let gatewayGenerateResponseSchema = FlexibleSchema(
    Schema<GatewayGenerateResponse>.codable(
        GatewayGenerateResponse.self,
        jsonSchema: .object(["type": .string("object")]),
        configureDecoder: { decoder in
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    )
)
