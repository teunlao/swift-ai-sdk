import Foundation
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider

public struct AmazonBedrockAnthropicProviderSettings: Sendable {
    public var region: String?
    public var apiKey: String?
    public var accessKeyId: String?
    public var secretAccessKey: String?
    public var sessionToken: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var headersProvider: (@Sendable () async throws -> [String: String?])?
    public var fetch: FetchFunction?
    public var credentialProvider: AmazonBedrockProviderSettings.CredentialProvider?
    public init(region: String? = nil, apiKey: String? = nil, accessKeyId: String? = nil, secretAccessKey: String? = nil, sessionToken: String? = nil, baseURL: String? = nil, headers: [String: String]? = nil, headersProvider: (@Sendable () async throws -> [String: String?])? = nil, fetch: FetchFunction? = nil, credentialProvider: AmazonBedrockProviderSettings.CredentialProvider? = nil) {
        self.region = region; self.apiKey = apiKey; self.accessKeyId = accessKeyId; self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken; self.baseURL = baseURL; self.headers = headers; self.headersProvider = headersProvider
        self.fetch = fetch; self.credentialProvider = credentialProvider
    }
    var common: AmazonBedrockProviderSettings {
        .init(region: region, apiKey: apiKey, accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, sessionToken: sessionToken, baseURL: baseURL, headers: headers, fetch: fetch, credentialProvider: credentialProvider)
    }
}

public struct AmazonBedrockAnthropicModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public final class AmazonBedrockAnthropicProvider: ProviderV4 {
    private let settings: AmazonBedrockAnthropicProviderSettings
    private let fetch: FetchFunction
    public let tools: AnthropicTools = anthropicTools
    init(settings: AmazonBedrockAnthropicProviderSettings) {
        self.settings = settings
        self.fetch = createBedrockAnthropicFetch(makeBedrockFetchFunction(settings: settings.common, inheritSessionToken: true))
    }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 { messages(modelId: .init(rawValue: modelId)) }
    public func callAsFunction(_ modelId: String) -> AnthropicMessagesLanguageModel { messages(modelId: .init(rawValue: modelId)) }
    public func chat(modelId: AmazonBedrockAnthropicModelId) -> AnthropicMessagesLanguageModel { messages(modelId: modelId) }
    public func messages(modelId: AmazonBedrockAnthropicModelId) -> AnthropicMessagesLanguageModel {
        let id = modelId.rawValue
        return .init(modelId: .init(rawValue: id), config: .init(
            provider: "bedrock.anthropic.messages", baseURL: "", headers: {
                let resolved = try await self.settings.headersProvider?() ?? self.settings.headers?.mapValues(Optional.some) ?? [:]
                return withUserAgentSuffix(resolved, "ai-sdk-amazon-bedrock/\(AMAZON_BEDROCK_VERSION)").mapValues(Optional.some)
            }, fetch: fetch,
            supportedUrls: { [:] }, requestTransform: .init(
                buildURL: { _, streaming in "\(try resolveBedrockBaseURL(settings: self.settings.common, service: "bedrock-runtime"))/model/\(bedrockEncodeURIComponent(id))/\(streaming ? "invoke-with-response-stream" : "invoke")" },
                transformBody: transformBedrockAnthropicBody
            ), supportsNativeStructuredOutput: bedrockSupportsNativeStructuredOutput(id), supportsStrictTools: bedrockSupportsStrictTools(id)
        ))
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel) }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
}

public func createAmazonBedrockAnthropic(settings: AmazonBedrockAnthropicProviderSettings = .init()) -> AmazonBedrockAnthropicProvider { .init(settings: settings) }
public let amazonBedrockAnthropic = createAmazonBedrockAnthropic()

private func transformBedrockAnthropicBody(_ body: [String: JSONValue], betas: Set<String>) -> [String: JSONValue] {
    var result = body
    result.removeValue(forKey: "model"); result.removeValue(forKey: "stream")
    if case .object(let choice)? = body["tool_choice"] {
        var transformed: [String: JSONValue] = [:]
        transformed["type"] = choice["type"]
        transformed["name"] = choice["name"]
        result["tool_choice"] = .object(transformed)
    }
    if case .object(var thinking)? = body["thinking"], case .object(let binding)? = thinking["block_binding"] {
        var transformed: [String: JSONValue] = [:]
        transformed["mismatch_behavior"] = binding["prefix_mismatch_behavior"]
        thinking["block_binding"] = .object(transformed)
        result["thinking"] = .object(thinking)
    }
    var requiredBetas = betas
    let versions = ["bash_20241022": "bash_20250124", "text_editor_20241022": "text_editor_20250728", "computer_20241022": "computer_20250124"]
    let toolBetas = [
        "bash_20250124": "computer-use-2025-01-24", "bash_20241022": "computer-use-2024-10-22",
        "text_editor_20250124": "computer-use-2025-01-24", "text_editor_20241022": "computer-use-2024-10-22",
        "text_editor_20250429": "computer-use-2025-01-24", "text_editor_20250728": "computer-use-2025-01-24",
        "computer_20250124": "computer-use-2025-01-24", "computer_20241022": "computer-use-2024-10-22",
        "tool_search_tool_regex_20251119": "tool-search-tool-2025-10-19", "tool_search_tool_bm25_20251119": "tool-search-tool-2025-10-19"
    ]
    if case .array(let tools)? = body["tools"] {
        result["tools"] = .array(tools.map { value in
            guard case .object(var tool) = value else { return value }
            if tool.removeValue(forKey: "eager_input_streaming") == .bool(true) { requiredBetas.insert("fine-grained-tool-streaming-2025-05-14") }
            if case .string(let type)? = tool["type"] {
                let resolved = versions[type] ?? type
                tool["type"] = .string(resolved)
                if let beta = toolBetas[resolved] { requiredBetas.insert(beta) }
                if resolved == "text_editor_20250728" { tool["name"] = .string("str_replace_based_edit_tool") }
            }
            return .object(tool)
        })
    }
    if !requiredBetas.isEmpty { result["anthropic_beta"] = .array(requiredBetas.sorted().map(JSONValue.string)) }
    result["anthropic_version"] = .string("bedrock-2023-05-31")
    return result
}

private func createBedrockAnthropicFetch(_ baseFetch: @escaping FetchFunction) -> FetchFunction {
    { request in
        let response = try await baseFetch(request)
        guard let http = response.urlResponse as? HTTPURLResponse else { return response }
        if !(200..<300).contains(http.statusCode) {
            let data = try await response.body.collectData()
            let text = String(decoding: data, as: UTF8.self)
            let parsed = try? JSONDecoder().decode([String: JSONValue].self, from: data)
            let message: String
            if case .string(let value)? = parsed?["message"], !value.isEmpty { message = value } else { message = text }
            let error: JSONValue = .object(["type": .string("error"), "error": .object(["type": .string("error"), "message": .string(message)])])
            return .init(body: .data(Data(try bedrockJSONString(error).utf8)), urlResponse: http)
        }
        guard http.value(forHTTPHeaderField: "content-type")?.contains("application/vnd.amazon.eventstream") == true else { return response }
        if case .none = response.body { return response }
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    for try await event in decodeBedrockEventStream(response.body.makeStream()) {
                        var text = String(decoding: event.body, as: UTF8.self)
                        if event.headers[":message-type"] == "event" {
                            if event.headers[":event-type"] == "chunk" {
                                if let object = try? JSONDecoder().decode([String: JSONValue].self, from: event.body), case .string(let bytes)? = object["bytes"], !bytes.isEmpty {
                                    let decoded = try convertBase64ToData(bytes)
                                    text = String(decoding: decoded, as: UTF8.self)
                                }
                            } else if event.headers[":event-type"] == "messageStop" { text = "[DONE]" }
                            else { continue }
                        } else if event.headers[":message-type"] == "exception" {
                            let data = (try? JSONDecoder().decode(JSONValue.self, from: event.body)) ?? .string(text)
                            let type = event.headers[":event-type"] ?? event.headers[":exception-type"] ?? "error"
                            let status = bedrockStreamErrorStatus(type)
                            var error: [String: JSONValue] = ["type": .string(type), "message": .string(text), "data": data]
                            if case .object(let object) = data, case .string(let message)? = object["message"] { error["message"] = .string(message) }
                            if let code = status.code { error["statusCode"] = .number(Double(code)) }
                            if let retryable = status.retryable { error["isRetryable"] = .bool(retryable) }
                            text = try bedrockJSONString(.object(["type": .string("error"), "error": .object(error)]))
                        } else { continue }
                        continuation.yield(Data("data: \(text)\n\n".utf8))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        var headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in result[String(describing: pair.key)] = String(describing: pair.value) }
        headers["content-type"] = "text/event-stream"
        guard let url = http.url, let transformed = HTTPURLResponse(url: url, statusCode: http.statusCode, httpVersion: nil, headerFields: headers) else { return response }
        return .init(body: .stream(stream), urlResponse: transformed)
    }
}
