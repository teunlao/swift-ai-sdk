import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-fetch-metadata.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GatewayFetchMetadataResponse: Sendable, Decodable {
    public let models: [GatewayLanguageModelEntry]
}

public struct GatewayCreditsResponse: Sendable, Decodable {
    public let balance: String
    public let totalUsed: String
}

struct GatewayFetchMetadata {
    private let config: GatewayConfig

    init(config: GatewayConfig) {
        self.config = config
    }

    func getAvailableModels() async throws -> GatewayFetchMetadataResponse {
        do {
            let headers = try await resolve(config.headers)
            let result = try await getFromAPI(
                url: "\(config.baseURL)/config",
                headers: headers.compactMapValues { $0 },
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewayAvailableModelsSchema),
                fetch: config.fetch
            )
            return result.value
        } catch {
            throw asGatewayError(error)
        }
    }

    func getCredits() async throws -> GatewayCreditsResponse {
        do {
            guard let baseUrl = URL(string: config.baseURL) else {
                throw APICallError(
                    message: "Invalid base URL",
                    url: config.baseURL,
                    requestBodyValues: nil
                )
            }

            let origin: String
            if let scheme = baseUrl.scheme, let host = baseUrl.host {
                if let port = baseUrl.port {
                    origin = "\(scheme)://\(host):\(port)"
                } else {
                    origin = "\(scheme)://\(host)"
                }
            } else {
                origin = baseUrl.absoluteString
            }

            let headers = try await resolve(config.headers)
            let result = try await getFromAPI(
                url: "\(origin)/v1/credits",
                headers: headers.compactMapValues { $0 },
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewayCreditsSchema),
                fetch: config.fetch
            )

            return result.value
        } catch {
            throw asGatewayError(error)
        }
    }
}

private let gatewayAvailableModelsSchema = FlexibleSchema(
    Schema<GatewayFetchMetadataResponse>.codable(
        GatewayFetchMetadataResponse.self,
        jsonSchema: .object(["type": .string("object")]),
        configureDecoder: { decoder in
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    )
)

private let gatewayCreditsSchema = FlexibleSchema(
    Schema<GatewayCreditsResponse>.codable(
        GatewayCreditsResponse.self,
        jsonSchema: .object(["type": .string("object")]),
        configureDecoder: { decoder in
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    )
)
