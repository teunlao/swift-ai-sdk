import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-embedding-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class MistralEmbeddingModel: EmbeddingModelV4 {

    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
    }

    private let modelIdentifier: MistralEmbeddingModelId
    private let config: Config
    private let maxValuesPerCall = 32

    init(modelId: MistralEmbeddingModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { maxValuesPerCall }
    }

    public var supportsParallelCalls: Bool {
        get async throws { false }
    }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        if options.values.count > maxValuesPerCall {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: maxValuesPerCall,
                values: options.values
            )
        }

        let settings = try await parseProviderOptions(provider: "mistral", providerOptions: options.providerOptions, schema: mistralEmbeddingModelOptions)
        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "input": .array(options.values.map(JSONValue.string)),
            "encoding_format": "float"
        ]
        if let metadata = settings?.metadata { body["metadata"] = .object(metadata) }
        if let dimensions = settings?.outputDimension ?? options.dimensions { body["output_dimension"] = .number(Double(dimensions)) }
        if let dtype = settings?.outputDtype { body["output_dtype"] = .string(dtype.rawValue) }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/embeddings",
            headers: try combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: { try await mistralFailedResponseHandler($0) },
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mistralEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let embeddings = response.value.data.map { $0.embedding }
        let usage = response.value.usage.flatMap { value in
            Int(exactly: value.promptTokens).map { EmbeddingModelV4Usage(tokens: $0) }
        }

        return EmbeddingModelV4Result(
            embeddings: embeddings,
            usage: usage,
            response: EmbeddingModelV4ResponseInfo(
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }
}

private struct MistralEmbeddingResponse: Codable {
    struct Entry: Codable {
        let embedding: [Double]
    }

    struct Usage: Codable {
        let promptTokens: Double

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
        }
    }

    let data: [Entry]
    let usage: Usage?
}

private let mistralEmbeddingResponseSchema = FlexibleSchema(
    Schema<MistralEmbeddingResponse>.codable(
        MistralEmbeddingResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
