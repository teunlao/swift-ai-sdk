import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GatewayRerankingModel: RerankingModelV4 {
    public let modelId: String
    private let config: GatewayModelConfig
    public var provider: String { config.provider }

    init(modelId: String, config: GatewayModelConfig) {
        self.modelId = modelId
        self.config = config
    }

    public func doRerank(options: RerankingModelV4CallOptions) async throws -> RerankingModelV4Result {
        let documents: JSONValue
        switch options.documents {
        case .text(let values): documents = .object(["type": .string("text"), "values": .array(values.map(JSONValue.string))])
        case .object(let values): documents = .object(["type": .string("object"), "values": .array(values.map(JSONValue.object))])
        }
        var body: [String: JSONValue] = ["documents": documents, "query": .string(options.query)]
        if let value = options.topN { body["topN"] = .number(Double(value)) }
        if let value = options.providerOptions { body["providerOptions"] = try gatewayJSON(value) }
        let result = try await config.post(
            "reranking", modelId: modelId, body: .object(body), headers: options.headers,
            abortSignal: options.abortSignal, response: GatewayRerankingResponse.self
        )
        return .init(
            ranking: result.value.ranking, providerMetadata: result.value.providerMetadata,
            warnings: result.value.warnings ?? [], response: .init(headers: result.responseHeaders, body: result.rawValue)
        )
    }
}

private struct GatewayRerankingResponse: Decodable, Sendable {
    let ranking: [RerankingModelV4Ranking]
    let warnings: [SharedV4Warning]?
    let providerMetadata: SharedV4ProviderMetadata?
}
