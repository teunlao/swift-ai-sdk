import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleEmbeddingConfig: Sendable {
    public let provider: String
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let headers: @Sendable () -> [String: String]
    public let fetch: FetchFunction?
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let maxEmbeddingsPerCallOverride: Int?
    public let supportsParallelCallsOverride: Bool?

    public init(
        provider: String,
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        headers: @escaping @Sendable () -> [String: String],
        fetch: FetchFunction? = nil,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        maxEmbeddingsPerCall: Int? = nil,
        supportsParallelCalls: Bool? = nil
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.errorConfiguration = errorConfiguration
        self.maxEmbeddingsPerCallOverride = maxEmbeddingsPerCall
        self.supportsParallelCallsOverride = supportsParallelCalls
    }
}

private enum OpenAICompatibleEmbeddingContract: Sendable {
    case v3
    case v4
}

private struct OpenAICompatibleEmbeddingCoreResult: @unchecked Sendable {
    let embeddings: [[Double]]
    let tokens: Int?
    let providerMetadata: SharedV4ProviderMetadata?
    let responseHeaders: SharedV4Headers?
    let responseBody: Any?
    let warnings: [SharedV4Warning]
}

private struct OpenAICompatibleEmbeddingModelCore: Sendable {
    private let modelIdentifier: OpenAICompatibleEmbeddingModelId
    private let config: OpenAICompatibleEmbeddingConfig
    private let legacyProviderOptionsName: String
    private let v4ProviderOptionsName: String

    init(modelId: OpenAICompatibleEmbeddingModelId, config: OpenAICompatibleEmbeddingConfig) {
        modelIdentifier = modelId
        self.config = config
        legacyProviderOptionsName = config.provider.split(separator: ".").first.map(String.init)
            ?? "openai-compatible"
        v4ProviderOptionsName = config.provider
            .split(separator: ".", omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }
    var maxEmbeddingsPerCall: Int { config.maxEmbeddingsPerCallOverride ?? 2048 }
    var supportsParallelCalls: Bool { config.supportsParallelCallsOverride ?? true }

    func doEmbed(
        values: [String],
        abortSignal: (@Sendable () -> Bool)?,
        providerOptions: SharedV4ProviderOptions?,
        headers: SharedV4Headers?,
        contract: OpenAICompatibleEmbeddingContract
    ) async throws -> OpenAICompatibleEmbeddingCoreResult {
        if contract == .v3 {
            try validateValueCount(values)
        }

        let prepared = try await prepareProviderOptions(
            contract: contract,
            providerOptions: providerOptions
        )

        if contract == .v4 {
            try validateValueCount(values)
        }

        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = headers?.mapValues { Optional($0) }
        let combinedHeaders = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/embeddings")),
            headers: combinedHeaders,
            body: JSONValue.object([
                "model": .string(modelIdentifier.rawValue),
                "input": .array(values.map(JSONValue.string)),
                "encoding_format": .string("float"),
                "dimensions": prepared.options.dimensions.map { .number(Double($0)) } ?? .null,
                "user": prepared.options.user.map(JSONValue.string) ?? .null
            ].compactMapValues { value in
                if case .null = value { return nil }
                return value
            }),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(
                responseSchema: openAICompatibleEmbeddingResponseSchema
            ),
            isAborted: abortSignal,
            fetch: config.fetch
        )

        let providerMetadata = response.value.providerMetadata?.isEmpty == false
            ? response.value.providerMetadata
            : nil

        return OpenAICompatibleEmbeddingCoreResult(
            embeddings: response.value.data.map(\.embedding),
            tokens: response.value.usage?.promptTokens,
            providerMetadata: providerMetadata,
            responseHeaders: response.responseHeaders,
            responseBody: response.rawValue,
            warnings: prepared.warnings
        )
    }

    private struct PreparedProviderOptions {
        let options: OpenAICompatibleEmbeddingProviderOptions
        let warnings: [SharedV4Warning]
    }

    private func prepareProviderOptions(
        contract: OpenAICompatibleEmbeddingContract,
        providerOptions: SharedV4ProviderOptions?
    ) async throws -> PreparedProviderOptions {
        switch contract {
        case .v3:
            let baseOptions = try await parseProviderOptions(
                provider: "openai-compatible",
                providerOptions: providerOptions,
                schema: openAICompatibleEmbeddingProviderOptionsSchema
            ) ?? OpenAICompatibleEmbeddingProviderOptions()
            let providerSpecificOptions = try await parseProviderOptions(
                provider: legacyProviderOptionsName,
                providerOptions: providerOptions,
                schema: openAICompatibleEmbeddingProviderOptionsSchema
            ) ?? OpenAICompatibleEmbeddingProviderOptions()

            var mergedOptions = baseOptions
            merge(providerSpecificOptions, into: &mergedOptions)
            return PreparedProviderOptions(options: mergedOptions, warnings: [])

        case .v4:
            var warnings: [SharedV4Warning] = []
            let deprecatedOptions = try await parseProviderOptions(
                provider: "openai-compatible",
                providerOptions: providerOptions,
                schema: openAICompatibleEmbeddingProviderOptionsSchema
            )
            if deprecatedOptions != nil {
                warnings.append(.deprecated(
                    setting: "providerOptions key 'openai-compatible'",
                    message: "Use 'openaiCompatible' instead."
                ))
            }
            if let warning = openAICompatibleDeprecatedProviderOptionsWarning(
                rawName: v4ProviderOptionsName,
                providerOptions: providerOptions
            ) {
                warnings.append(warning)
            }

            let compatibleOptions = try await parseProviderOptions(
                provider: "openaiCompatible",
                providerOptions: providerOptions,
                schema: openAICompatibleEmbeddingProviderOptionsSchema
            ) ?? OpenAICompatibleEmbeddingProviderOptions()
            let providerSpecificOptions = try await parseProviderOptions(
                provider: v4ProviderOptionsName,
                providerOptions: providerOptions,
                schema: openAICompatibleEmbeddingProviderOptionsSchema
            ) ?? OpenAICompatibleEmbeddingProviderOptions()

            var mergedOptions = deprecatedOptions ?? OpenAICompatibleEmbeddingProviderOptions()
            merge(compatibleOptions, into: &mergedOptions)
            merge(providerSpecificOptions, into: &mergedOptions)
            return PreparedProviderOptions(options: mergedOptions, warnings: warnings)
        }
    }

    private func merge(
        _ source: OpenAICompatibleEmbeddingProviderOptions,
        into destination: inout OpenAICompatibleEmbeddingProviderOptions
    ) {
        if let dimensions = source.dimensions { destination.dimensions = dimensions }
        if let user = source.user { destination.user = user }
    }

    private func validateValueCount(_ values: [String]) throws {
        guard values.count <= maxEmbeddingsPerCall else {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: maxEmbeddingsPerCall,
                values: values.map { $0 as Any }
            )
        }
    }
}

public final class OpenAICompatibleEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleEmbeddingModelId
    private let core: OpenAICompatibleEmbeddingModelCore

    public init(modelId: OpenAICompatibleEmbeddingModelId, config: OpenAICompatibleEmbeddingConfig) {
        modelIdentifier = modelId
        core = OpenAICompatibleEmbeddingModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { core.maxEmbeddingsPerCall }
    }

    public var supportsParallelCalls: Bool {
        get async throws { core.supportsParallelCalls }
    }

    public func doEmbed(
        options: EmbeddingModelV3DoEmbedOptions<String>
    ) async throws -> EmbeddingModelV3DoEmbedResult {
        let result = try await core.doEmbed(
            values: options.values,
            abortSignal: options.abortSignal,
            providerOptions: options.providerOptions,
            headers: options.headers,
            contract: .v3
        )

        return EmbeddingModelV3DoEmbedResult(
            embeddings: result.embeddings,
            usage: result.tokens.map(EmbeddingModelV3Usage.init(tokens:)),
            providerMetadata: result.providerMetadata,
            response: EmbeddingModelV3ResponseInfo(
                headers: result.responseHeaders,
                body: result.responseBody
            )
        )
    }
}

public final class OpenAICompatibleEmbeddingModelV4: EmbeddingModelV4 {
    private let core: OpenAICompatibleEmbeddingModelCore

    public init(modelId: OpenAICompatibleEmbeddingModelId, config: OpenAICompatibleEmbeddingConfig) {
        core = OpenAICompatibleEmbeddingModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { core.maxEmbeddingsPerCall }
    }

    public var supportsParallelCalls: Bool {
        get async throws { core.supportsParallelCalls }
    }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let result = try await core.doEmbed(
            values: options.values,
            abortSignal: options.abortSignal,
            providerOptions: options.providerOptions,
            headers: options.headers,
            contract: .v4
        )

        return EmbeddingModelV4Result(
            embeddings: result.embeddings,
            usage: result.tokens.map(EmbeddingModelV4Usage.init(tokens:)),
            providerMetadata: result.providerMetadata,
            response: EmbeddingModelV4ResponseInfo(
                headers: result.responseHeaders,
                body: result.responseBody
            ),
            warnings: result.warnings
        )
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private struct OpenAICompatibleEmbeddingResponse: Codable {
    struct DataItem: Codable {
        let embedding: [Double]
    }

    struct Usage: Codable {
        let promptTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
        }
    }

    let data: [DataItem]
    let usage: Usage?
    let providerMetadata: SharedV3ProviderMetadata?
}

private let openAICompatibleEmbeddingResponseSchema = FlexibleSchema(
    Schema<OpenAICompatibleEmbeddingResponse>.codable(
        OpenAICompatibleEmbeddingResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)
