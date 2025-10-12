/**
 Specification for an embedding model that implements the embedding model interface version 3.

 Port of `@ai-sdk/provider/src/embedding-model/v3/embedding-model-v3.ts`.

 VALUE is the type of the values that the model can embed.
 This will allow us to go beyond text embeddings in the future,
 e.g. to support image embeddings.
 */
public protocol EmbeddingModelV3<VALUE>: Sendable {
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
    func doEmbed(options: EmbeddingModelV3DoEmbedOptions<VALUE>) async throws -> EmbeddingModelV3DoEmbedResult
}

extension EmbeddingModelV3 {
    /// Default implementation returns "v3"
    public var specificationVersion: String { "v3" }
}

// MARK: - Options and Result Types

/// Options for the EmbeddingModelV3 doEmbed method
public struct EmbeddingModelV3DoEmbedOptions<VALUE: Sendable>: Sendable {
    /// List of values to embed
    public let values: [VALUE]

    /// Abort signal for cancelling the operation (Swift: closure returning Bool)
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional provider-specific options
    public let providerOptions: SharedV3ProviderOptions?

    /// Additional HTTP headers to be sent with the request (only applicable for HTTP-based providers)
    public let headers: [String: String]?

    public init(
        values: [VALUE],
        abortSignal: (@Sendable () -> Bool)? = nil,
        providerOptions: SharedV3ProviderOptions? = nil,
        headers: [String: String]? = nil
    ) {
        self.values = values
        self.abortSignal = abortSignal
        self.providerOptions = providerOptions
        self.headers = headers
    }
}

/// Result from the EmbeddingModelV3 doEmbed method
public struct EmbeddingModelV3DoEmbedResult: Sendable {
    /// Generated embeddings. They are in the same order as the input values.
    public let embeddings: [EmbeddingModelV3Embedding]

    /// Token usage. We only have input tokens for embeddings.
    public let usage: EmbeddingModelV3Usage?

    /// Additional provider-specific metadata
    public let providerMetadata: SharedV3ProviderMetadata?

    /// Optional response information for debugging purposes
    public let response: EmbeddingModelV3ResponseInfo?

    public init(
        embeddings: [EmbeddingModelV3Embedding],
        usage: EmbeddingModelV3Usage? = nil,
        providerMetadata: SharedV3ProviderMetadata? = nil,
        response: EmbeddingModelV3ResponseInfo? = nil
    ) {
        self.embeddings = embeddings
        self.usage = usage
        self.providerMetadata = providerMetadata
        self.response = response
    }
}

/// Token usage information for embeddings
public struct EmbeddingModelV3Usage: Sendable {
    public let tokens: Int

    public init(tokens: Int) {
        self.tokens = tokens
    }
}

/// Response information for debugging
public struct EmbeddingModelV3ResponseInfo: Sendable {
    /// Response headers
    public let headers: SharedV3Headers?

    /// The response body
    public let body: JSONValue?

    public init(
        headers: SharedV3Headers? = nil,
        body: JSONValue? = nil
    ) {
        self.headers = headers
        self.body = body
    }
}
