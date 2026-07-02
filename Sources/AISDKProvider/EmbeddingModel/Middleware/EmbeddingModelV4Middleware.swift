/**
 Middleware for `EmbeddingModelV4`.

 Port of `@ai-sdk/provider/src/embedding-model-middleware/v4/embedding-model-v4-middleware.ts`.
 */
public struct EmbeddingModelV4Middleware: Sendable {
    public let specificationVersion: String
    public let overrideProvider: (@Sendable (_ model: any EmbeddingModelV4) -> String)?
    public let overrideModelId: (@Sendable (_ model: any EmbeddingModelV4) -> String)?
    public let overrideMaxEmbeddingsPerCall: (@Sendable (_ model: any EmbeddingModelV4) async throws -> Int?)?
    public let overrideSupportsParallelCalls: (@Sendable (_ model: any EmbeddingModelV4) async throws -> Bool)?
    public let transformParams: (@Sendable (_ params: EmbeddingModelV4CallOptions, _ model: any EmbeddingModelV4) async throws -> EmbeddingModelV4CallOptions)?
    public let wrapEmbed: (@Sendable (
        _ doEmbed: @Sendable () async throws -> EmbeddingModelV4Result,
        _ params: EmbeddingModelV4CallOptions,
        _ model: any EmbeddingModelV4
    ) async throws -> EmbeddingModelV4Result)?

    public init(
        specificationVersion: String = "v4",
        overrideProvider: (@Sendable (_ model: any EmbeddingModelV4) -> String)? = nil,
        overrideModelId: (@Sendable (_ model: any EmbeddingModelV4) -> String)? = nil,
        overrideMaxEmbeddingsPerCall: (@Sendable (_ model: any EmbeddingModelV4) async throws -> Int?)? = nil,
        overrideSupportsParallelCalls: (@Sendable (_ model: any EmbeddingModelV4) async throws -> Bool)? = nil,
        transformParams: (@Sendable (_ params: EmbeddingModelV4CallOptions, _ model: any EmbeddingModelV4) async throws -> EmbeddingModelV4CallOptions)? = nil,
        wrapEmbed: (@Sendable (
            _ doEmbed: @Sendable () async throws -> EmbeddingModelV4Result,
            _ params: EmbeddingModelV4CallOptions,
            _ model: any EmbeddingModelV4
        ) async throws -> EmbeddingModelV4Result)? = nil
    ) {
        self.specificationVersion = specificationVersion
        self.overrideProvider = overrideProvider
        self.overrideModelId = overrideModelId
        self.overrideMaxEmbeddingsPerCall = overrideMaxEmbeddingsPerCall
        self.overrideSupportsParallelCalls = overrideSupportsParallelCalls
        self.transformParams = transformParams
        self.wrapEmbed = wrapEmbed
    }
}
