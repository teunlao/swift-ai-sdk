import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-embedding-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class MistralEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () -> [String: String?]
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

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        if options.values.count > maxValuesPerCall {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: maxValuesPerCall,
                values: options.values
            )
        }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/embeddings",
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object([
                "model": .string(modelIdentifier.rawValue),
                "input": .array(options.values.map(JSONValue.string)),
                "encoding_format": .string("float")
            ]),
            failedResponseHandler: { try await mistralFailedResponseHandler($0) },
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mistralEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let embeddings = response.value.data.map { $0.embedding }
        let usage = response.value.usage.map { EmbeddingModelV3Usage(tokens: $0.promptTokens) }

        return EmbeddingModelV3DoEmbedResult(
            embeddings: embeddings,
            usage: usage,
            response: EmbeddingModelV3ResponseInfo(
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
        let promptTokens: Int

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
