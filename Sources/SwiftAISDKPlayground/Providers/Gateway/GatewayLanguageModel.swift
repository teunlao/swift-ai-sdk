import Foundation
import AISDKProvider
import AISDKProviderUtils
import EventSourceParser

/// Minimal Swift port of Vercel AI Gateway language model for CLI usage.
/// Supports basic text generation and streaming for manual testing purposes.
final class GatewayLanguageModel: LanguageModelV3 {
    private struct Constants {
        static let protocolVersion = "0.0.1"
        static let defaultBaseURL = URL(string: "https://ai-gateway.vercel.sh/v1/ai")!
        static let userAgentSuffix = "swift-ai-sdk-playground/0.1.0"
    }

    let modelId: String
    let provider: String = "gateway"

    private let apiKey: String
    private let baseURL: URL
    private let urlSession: URLSession

    init(modelId: String, apiKey: String, baseURL: URL?, urlSession: URLSession = .shared) {
        self.modelId = modelId
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Constants.defaultBaseURL
        self.urlSession = urlSession
    }

    private func makeHeaders(streaming: Bool, extra: [String: String]?) -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(apiKey)",
            "ai-gateway-protocol-version": Constants.protocolVersion,
            "ai-gateway-auth-method": "api-key",
            "ai-language-model-specification-version": "2",
            "ai-language-model-id": modelId,
            "ai-language-model-streaming": String(streaming),
            "Content-Type": "application/json",
            "Accept": streaming ? "text/event-stream" : "application/json",
            "User-Agent": "SwiftAISDKPlayground/\(PlaygroundVersion.current.description)"
        ]

        if let extra {
            headers.merge(extra) { current, _ in current }
        }

        return headers
    }

    private func makeRequestBody(
        options: LanguageModelV3CallOptions
    ) throws -> Data {
        let body = GatewayRequestBody(options: options)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(body)
    }

    private func makePrompt(options: LanguageModelV3CallOptions) -> LanguageModelV3RequestInfo {
        LanguageModelV3RequestInfo(body: options)
    }

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let requestURL = baseURL.appendingPathComponent("language-model")
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = "POST"
        let headers = makeHeaders(streaming: false, extra: options.headers)
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = try makeRequestBody(options: options)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayErrorWrapper(message: "Некорректный HTTP ответ от шлюза.", statusCode: nil)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Неизвестная ошибка шлюза"
            throw GatewayErrorWrapper(message: message, statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GatewayGenerateResponse.self, from: data)

        return LanguageModelV3GenerateResult(
            content: payload.content,
            finishReason: payload.finishReason,
            usage: payload.usage,
            providerMetadata: payload.providerMetadata,
            request: makePrompt(options: options),
            response: LanguageModelV3ResponseInfo(
                id: payload.id,
                timestamp: payload.timestamp,
                modelId: payload.model,
                headers: httpResponse.allHeaderFields as? [String: String],
                body: payload.rawResponseBody ?? payload.content
            ),
            warnings: payload.warnings ?? []
        )
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let requestURL = baseURL.appendingPathComponent("language-model")
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = "POST"
        let headers = makeHeaders(streaming: true, extra: options.headers)
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = try makeRequestBody(options: options)

        guard #available(macOS 12.0, *) else {
            throw GatewayErrorWrapper(message: "Streaming доступно только на macOS 12 и выше.", statusCode: nil)
        }

        let (stream, response) = try await urlSession.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayErrorWrapper(message: "Некорректный HTTP ответ от шлюза.", statusCode: nil)
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            var buffer = Data()
            for try await byte in stream {
                buffer.append(byte)
            }
            let message = String(data: buffer, encoding: .utf8) ?? "Неизвестная ошибка шлюза"
            throw GatewayErrorWrapper(message: message, statusCode: httpResponse.statusCode)
        }

        let byteStream = stream

        let dataStream = AsyncThrowingStream<Data, Error> { continuation in
            Task.detached {
                do {
                    for try await byte in byteStream {
                        continuation.yield(Data([byte]))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        let eventStream = EventSourceParserStream.makeStream(
            from: dataStream,
            options: .init(onError: .ignore)
        )

        let partStream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            Task.detached {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                do {
                    for try await event in eventStream {
                        guard let data = event.data.data(using: .utf8) else { continue }
                        let chunk = try decoder.decode(GatewayStreamChunk.self, from: data)
                        continuation.yield(chunk.part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: partStream,
            request: makePrompt(options: options),
            response: LanguageModelV3StreamResponseInfo(
                headers: httpResponse.allHeaderFields as? [String: String]
            )
        )
    }
}

private struct GatewayRequestBody: Encodable {
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
        self.providerOptions = options.providerOptions
    }
}

private struct GatewayGenerateResponse: Decodable {
    struct Metadata: Decodable {
        let headers: [String: String]?
        let body: JSONValue?
    }

    let id: String?
    let created: Date?
    let model: String?
    let content: [LanguageModelV3Content]
    let finishReason: LanguageModelV3FinishReason
    let usage: LanguageModelV3Usage
    let providerMetadata: SharedV3ProviderMetadata?
    let warnings: [SharedV3Warning]?

    let response: Metadata?
    let request: Metadata?

    var rawResponseBody: Any? {
        if let value = response?.body {
            return jsonValueToAny(value)
        }
        return nil
    }

    var timestamp: Date? { created }

    enum CodingKeys: String, CodingKey {
        case id
        case created
        case model
        case content
        case finishReason = "finish_reason"
        case usage
        case providerMetadata = "provider_metadata"
        case warnings
        case response
        case request
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        model = try container.decodeIfPresent(String.self, forKey: .model)

        if let createdSeconds = try container.decodeIfPresent(Double.self, forKey: .created) {
            created = Date(timeIntervalSince1970: createdSeconds)
        } else if let createdInt = try container.decodeIfPresent(Int.self, forKey: .created) {
            created = Date(timeIntervalSince1970: TimeInterval(createdInt))
        } else if let createdString = try container.decodeIfPresent(String.self, forKey: .created) {
            // Try to parse ISO8601 string
            if let date = ISO8601DateFormatter().date(from: createdString) {
                created = date
            } else if let doubleValue = Double(createdString) {
                created = Date(timeIntervalSince1970: doubleValue)
            } else {
                created = nil
            }
        } else {
            created = nil
        }

        content = try container.decode([LanguageModelV3Content].self, forKey: .content)
        finishReason = try container.decode(LanguageModelV3FinishReason.self, forKey: .finishReason)

        let usagePayload = try container.decodeIfPresent(UsagePayload.self, forKey: .usage)
        usage = usagePayload?.toUsage() ?? LanguageModelV3Usage()

        providerMetadata = try container.decodeIfPresent(SharedV3ProviderMetadata.self, forKey: .providerMetadata)
        warnings = try container.decodeIfPresent([SharedV3Warning].self, forKey: .warnings)

        response = try container.decodeIfPresent(Metadata.self, forKey: .response)
        request = try container.decodeIfPresent(Metadata.self, forKey: .request)
    }
}

private struct UsagePayload: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let reasoningTokens: Int?
    let cachedInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens
        case outputTokens
        case totalTokens
        case reasoningTokens
        case cachedInputTokens
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case total = "total_tokens"
        case reasoning = "reasoning_tokens"
        case cachedInput = "cached_input_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .promptTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .completionTokens)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .total)
        reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .reasoning)
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens)
            ?? container.decodeIfPresent(Int.self, forKey: .cachedInput)
    }

    func toUsage() -> LanguageModelV3Usage {
        let noCacheTokens = inputTokens
        let cacheReadTokens = cachedInputTokens
        let totalInputTokens: Int? = {
            if noCacheTokens == nil, cacheReadTokens == nil {
                return nil
            }
            return (noCacheTokens ?? 0) + (cacheReadTokens ?? 0)
        }()

        let totalOutputTokens = outputTokens
        let textTokens = totalOutputTokens.map { total in
            reasoningTokens.map { total - $0 } ?? total
        }

        return LanguageModelV3Usage(
            inputTokens: .init(
                total: totalInputTokens,
                noCache: noCacheTokens,
                cacheRead: cacheReadTokens,
                cacheWrite: nil
            ),
            outputTokens: .init(
                total: totalOutputTokens,
                text: textTokens,
                reasoning: reasoningTokens
            ),
            raw: nil
        )
    }
}

private struct GatewayStreamChunk: Decodable {
    let part: LanguageModelV3StreamPart

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.part = try container.decode(LanguageModelV3StreamPart.self)
    }
}

private struct GatewayErrorWrapper: LocalizedError {
    let message: String
    let statusCode: Int?

    var errorDescription: String? {
        if let statusCode {
            return "Gateway error (\(statusCode)): \(message)"
        } else {
            return "Gateway error: \(message)"
        }
    }
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .string(let string):
        return string
    case .number(let number):
        return number
    case .bool(let bool):
        return bool
    case .null:
        return NSNull()
    case .array(let array):
        return array.map { jsonValueToAny($0) }
    case .object(let object):
        var result: [String: Any] = [:]
        for (key, entry) in object {
            result[key] = jsonValueToAny(entry)
        }
        return result
    }
}
