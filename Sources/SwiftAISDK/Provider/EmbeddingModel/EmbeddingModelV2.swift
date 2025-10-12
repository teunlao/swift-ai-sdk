/**
 Specification for an embedding model that implements the embedding model interface version 2.

 Port of `@ai-sdk/provider/src/embedding-model/v2/embedding-model-v2.ts`.

 VALUE is the type of the values that the model can embed.
 This will allow us to go beyond text embeddings in the future,
 e.g. to support image embeddings.
 */
public protocol EmbeddingModelV2<VALUE>: Sendable {
    /// The type of values that the model can embed (e.g., String for text embeddings)
    associatedtype VALUE: Sendable

    /**
     The embedding model must specify which embedding model interface
     version it implements. This will allow us to evolve the embedding
     model interface and retain backwards compatibility. The different
     implementation versions can be handled as a discriminated union
     on our side.
     */
    var specificationVersion: String { get }

    /**
     Name of the provider for logging purposes.
     */
    var provider: String { get }

    /**
     Provider-specific model ID for logging purposes.
     */
    var modelId: String { get }

    /**
     Limit of how many embeddings can be generated in a single API call.

     Use `.infinity` for models that do not have a limit.
     Returns `nil` if the limit is not known.
     */
    var maxEmbeddingsPerCall: Int? { get async throws }

    /**
     True if the model can handle multiple embedding calls in parallel.
     */
    var supportsParallelCalls: Bool { get async throws }

    /**
     Generates a list of embeddings for the given input values.

     Naming: "do" prefix to prevent accidental direct usage of the method by the user.

     - Parameter options: Options for the embedding operation
     - Returns: Embedding result with embeddings, usage, metadata, and response info
     - Throws: Various errors including TooManyEmbeddingValuesForCallError
     */
    func doEmbed(options: EmbeddingModelV2DoEmbedOptions<VALUE>) async throws -> EmbeddingModelV2DoEmbedResult
}

extension EmbeddingModelV2 {
    /// Default implementation returns "v2"
    public var specificationVersion: String { "v2" }
}

// MARK: - Options and Result Types

/// Options for the EmbeddingModelV2 doEmbed method
public struct EmbeddingModelV2DoEmbedOptions<VALUE: Sendable>: Sendable {
    /// List of values to embed
    public let values: [VALUE]

    /// Abort signal for cancelling the operation (Swift: closure returning Bool)
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional provider-specific options
    public let providerOptions: SharedV2ProviderOptions?

    /// Additional HTTP headers to be sent with the request (only applicable for HTTP-based providers)
    public let headers: [String: String]?

    public init(
        values: [VALUE],
        abortSignal: (@Sendable () -> Bool)? = nil,
        providerOptions: SharedV2ProviderOptions? = nil,
        headers: [String: String]? = nil
    ) {
        self.values = values
        self.abortSignal = abortSignal
        self.providerOptions = providerOptions
        self.headers = headers
    }
}

/// Result from the EmbeddingModelV2 doEmbed method
public struct EmbeddingModelV2DoEmbedResult: Sendable {
    /// Generated embeddings. They are in the same order as the input values.
    public let embeddings: [EmbeddingModelV2Embedding]

    /// Token usage. We only have input tokens for embeddings.
    public let usage: EmbeddingModelV2Usage?

    /// Additional provider-specific metadata
    public let providerMetadata: SharedV2ProviderMetadata?

    /// Optional response information for debugging purposes
    public let response: EmbeddingModelV2ResponseInfo?

    public init(
        embeddings: [EmbeddingModelV2Embedding],
        usage: EmbeddingModelV2Usage? = nil,
        providerMetadata: SharedV2ProviderMetadata? = nil,
        response: EmbeddingModelV2ResponseInfo? = nil
    ) {
        self.embeddings = embeddings
        self.usage = usage
        self.providerMetadata = providerMetadata
        self.response = response
    }
}

/// Token usage information for embeddings
public struct EmbeddingModelV2Usage: Sendable {
    public let tokens: Int

    public init(tokens: Int) {
        self.tokens = tokens
    }
}

/// Response information for debugging
public struct EmbeddingModelV2ResponseInfo: Sendable {
    /// Response headers
    public let headers: SharedV2Headers?

    /// The response body
    public let body: JSONValue?

    public init(
        headers: SharedV2Headers? = nil,
        body: JSONValue? = nil
    ) {
        self.headers = headers
        self.body = body
    }
}
