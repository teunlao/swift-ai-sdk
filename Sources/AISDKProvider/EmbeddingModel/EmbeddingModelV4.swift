/**
 Specification for a text embedding model that implements the embedding model interface version 4.

 Port of `@ai-sdk/provider/src/embedding-model/v4/embedding-model-v4.ts`.
 */
public protocol EmbeddingModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }
    var maxEmbeddingsPerCall: Int? { get async throws }
    var supportsParallelCalls: Bool { get async throws }

    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result
}

extension EmbeddingModelV4 {
    public var specificationVersion: String { "v4" }
}

public typealias EmbeddingModelV4Embedding = [Double]

public struct EmbeddingModelV4CallOptions: Sendable {
    public let values: [String]
    public let abortSignal: (@Sendable () -> Bool)?
    public let providerOptions: SharedV4ProviderOptions?
    public let headers: SharedV4Headers?

    public init(
        values: [String],
        abortSignal: (@Sendable () -> Bool)? = nil,
        providerOptions: SharedV4ProviderOptions? = nil,
        headers: SharedV4Headers? = nil
    ) {
        self.values = values
        self.abortSignal = abortSignal
        self.providerOptions = providerOptions
        self.headers = headers
    }
}

public struct EmbeddingModelV4Result: Sendable {
    public let embeddings: [EmbeddingModelV4Embedding]
    public let usage: EmbeddingModelV4Usage?
    public let providerMetadata: SharedV4ProviderMetadata?
    public let response: EmbeddingModelV4ResponseInfo?
    public let warnings: [SharedV4Warning]

    public init(
        embeddings: [EmbeddingModelV4Embedding],
        usage: EmbeddingModelV4Usage? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil,
        response: EmbeddingModelV4ResponseInfo? = nil,
        warnings: [SharedV4Warning] = []
    ) {
        self.embeddings = embeddings
        self.usage = usage
        self.providerMetadata = providerMetadata
        self.response = response
        self.warnings = warnings
    }
}

public struct EmbeddingModelV4Usage: Sendable, Codable, Equatable {
    public let tokens: Int

    public init(tokens: Int) {
        self.tokens = tokens
    }
}

public struct EmbeddingModelV4ResponseInfo: @unchecked Sendable {
    public let headers: SharedV4Headers?
    public let body: Any?

    public init(headers: SharedV4Headers? = nil, body: Any? = nil) {
        self.headers = headers
        self.body = body
    }
}
