import Foundation

/**
 Specification for a language model that implements the language model interface version 4.

 Port of `@ai-sdk/provider/src/language-model/v4/language-model-v4.ts`.
 */
public protocol LanguageModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }
    var supportedUrls: [String: [NSRegularExpression]] { get async throws }

    func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult
    func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult
}

extension LanguageModelV4 {
    public var specificationVersion: String { "v4" }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { [:] }
    }
}

public struct LanguageModelV4GenerateResult: Sendable {
    public let content: [LanguageModelV4Content]
    public let finishReason: LanguageModelV4FinishReason
    public let usage: LanguageModelV4Usage
    public let providerMetadata: SharedV4ProviderMetadata?
    public let request: LanguageModelV4RequestInfo?
    public let response: LanguageModelV4ResponseInfo?
    public let warnings: [SharedV4Warning]

    public init(
        content: [LanguageModelV4Content],
        finishReason: LanguageModelV4FinishReason,
        usage: LanguageModelV4Usage,
        providerMetadata: SharedV4ProviderMetadata? = nil,
        request: LanguageModelV4RequestInfo? = nil,
        response: LanguageModelV4ResponseInfo? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.content = content
        self.finishReason = finishReason
        self.usage = usage
        self.providerMetadata = providerMetadata
        self.request = request
        self.response = response
        self.warnings = warnings
    }
}

public struct LanguageModelV4StreamResult: Sendable {
    public let stream: AsyncThrowingStream<LanguageModelV4StreamPart, Error>
    public let request: LanguageModelV4RequestInfo?
    public let response: LanguageModelV4StreamResponseInfo?

    public init(
        stream: AsyncThrowingStream<LanguageModelV4StreamPart, Error>,
        request: LanguageModelV4RequestInfo? = nil,
        response: LanguageModelV4StreamResponseInfo? = nil
    ) {
        self.stream = stream
        self.request = request
        self.response = response
    }
}

public struct LanguageModelV4RequestInfo: @unchecked Sendable {
    public let body: Any?

    public init(body: Any? = nil) {
        self.body = body
    }
}

public struct LanguageModelV4ResponseInfo: @unchecked Sendable {
    public let id: String?
    public let timestamp: Date?
    public let modelId: String?
    public let headers: SharedV4Headers?
    public let body: Any?

    public init(
        id: String? = nil,
        timestamp: Date? = nil,
        modelId: String? = nil,
        headers: SharedV4Headers? = nil,
        body: Any? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.body = body
    }
}

public struct LanguageModelV4StreamResponseInfo: Sendable {
    public let headers: SharedV4Headers?

    public init(headers: SharedV4Headers? = nil) {
        self.headers = headers
    }
}

public struct LanguageModelV4Usage: Sendable, Codable, Equatable {
    public struct InputTokens: Sendable, Codable, Equatable {
        public let total: Int?
        public let noCache: Int?
        public let cacheRead: Int?
        public let cacheWrite: Int?

        public init(total: Int? = nil, noCache: Int? = nil, cacheRead: Int? = nil, cacheWrite: Int? = nil) {
            self.total = total
            self.noCache = noCache
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
        }
    }

    public struct OutputTokens: Sendable, Codable, Equatable {
        public let total: Int?
        public let text: Int?
        public let reasoning: Int?

        public init(total: Int? = nil, text: Int? = nil, reasoning: Int? = nil) {
            self.total = total
            self.text = text
            self.reasoning = reasoning
        }
    }

    public let inputTokens: InputTokens
    public let outputTokens: OutputTokens
    public let raw: JSONValue?

    public init(
        inputTokens: InputTokens = .init(),
        outputTokens: OutputTokens = .init(),
        raw: JSONValue? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.raw = raw
    }
}
