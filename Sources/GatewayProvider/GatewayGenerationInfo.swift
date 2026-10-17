import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GatewayGenerationInfoParams: Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct GatewayGenerationInfo: Sendable, Decodable {
    public let id: String
    public let totalCost: Double
    public let upstreamInferenceCost: Double
    public let usage: Double
    public let createdAt: String
    public let model: String
    public let isByok: Bool
    public let providerName: String
    public let streamed: Bool
    public let finishReason: String
    public let latency: Double
    public let generationTime: Double
    public let promptTokens: Double
    public let completionTokens: Double
    public let reasoningTokens: Double
    public let cachedTokens: Double
    public let cacheCreationTokens: Double
    public let billableWebSearchCalls: Double

    private enum CodingKeys: String, CodingKey {
        case id, usage, model, streamed, latency
        case totalCost = "total_cost"
        case upstreamInferenceCost = "upstream_inference_cost"
        case createdAt = "created_at"
        case isByok = "is_byok"
        case providerName = "provider_name"
        case finishReason = "finish_reason"
        case generationTime = "generation_time"
        case promptTokens = "native_tokens_prompt"
        case completionTokens = "native_tokens_completion"
        case reasoningTokens = "native_tokens_reasoning"
        case cachedTokens = "native_tokens_cached"
        case cacheCreationTokens = "native_tokens_cache_creation"
        case billableWebSearchCalls = "billable_web_search_calls"
    }
}

struct GatewayGenerationInfoFetcher: Sendable {
    let config: GatewayConfig

    func getGenerationInfo(_ params: GatewayGenerationInfoParams) async throws -> GatewayGenerationInfo {
        do {
            let result = try await getFromAPI(
                url: gatewayAPIURL(
                    baseURL: config.baseURL,
                    path: "/v1/generation",
                    queryItems: [.init(name: "id", value: params.id)],
                    formEncoding: false
                ),
                headers: try await resolve(config.headers).compactMapValues { $0 },
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewayGenerationInfoSchema),
                fetch: config.fetch
            )
            return result.value.data
        } catch {
            throw asGatewayError(error)
        }
    }
}

private struct GatewayGenerationInfoResponse: Sendable, Decodable {
    let data: GatewayGenerationInfo
}

private let gatewayGenerationInfoSchema = FlexibleSchema(
    Schema<GatewayGenerationInfoResponse>.codable(
        GatewayGenerationInfoResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
