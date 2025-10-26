import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-embedding-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct BedrockEmbeddingConfig: Sendable {
    let baseURL: @Sendable () -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
}

private struct BedrockEmbeddingResponse: Codable, Sendable {
    let embedding: [Double]
    let inputTextTokenCount: Int
}

private let bedrockEmbeddingResponseSchema = FlexibleSchema(
    Schema<BedrockEmbeddingResponse>.codable(
        BedrockEmbeddingResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

public final class BedrockEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    private let modelIdentifier: BedrockEmbeddingModelId
    private let config: BedrockEmbeddingConfig

    init(modelId: BedrockEmbeddingModelId, config: BedrockEmbeddingConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v3" }
    public var provider: String { "amazon-bedrock" }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 1 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        if options.values.count > 1 {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: 1,
                values: options.values.map { $0 as Any }
            )
        }

        let bedrockOptions = try await parseProviderOptions(
            provider: "bedrock",
            providerOptions: options.providerOptions,
            schema: bedrockEmbeddingProviderOptionsSchema
        )

        guard let value = options.values.first else {
            return EmbeddingModelV3DoEmbedResult(embeddings: [], usage: nil, providerMetadata: nil, response: nil)
        }

        var body: [String: JSONValue] = [
            "inputText": .string(value)
        ]

        if let dimensions = bedrockOptions?.dimensions {
            body["dimensions"] = .number(Double(dimensions.rawValue))
        }

        if let normalize = bedrockOptions?.normalize {
            body["normalize"] = .bool(normalize)
        }

        let url = "\(config.baseURL())/model/\(encodeModelId(modelIdentifier.rawValue))/invoke"
        let headers = mergeHeaders(base: config.headers(), overrides: options.headers)

        let response = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let usage = EmbeddingModelV3Usage(tokens: response.value.inputTextTokenCount)

        let responseInfo = EmbeddingModelV3ResponseInfo(
            headers: response.responseHeaders,
            body: response.rawValue
        )

        return EmbeddingModelV3DoEmbedResult(
            embeddings: [response.value.embedding],
            usage: usage,
            providerMetadata: nil,
            response: responseInfo
        )
    }

    private func mergeHeaders(base: [String: String?], overrides: [String: String]?) -> [String: String] {
        let merged = combineHeaders(
            base,
            overrides?.mapValues { Optional($0) }
        )
        return merged.compactMapValues { $0 }
    }

    private func encodeModelId(_ modelId: String) -> String {
        modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelId
    }
}
