import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-fetch-metadata.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

public struct GatewayFetchMetadataResponse: Sendable, Decodable {
    public let models: [GatewayLanguageModelEntry]

    private enum CodingKeys: String, CodingKey { case models }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let knownTypes: Set<String> = [
            "embedding", "decision", "evaluation", "image", "language", "realtime",
            "reranking", "speech", "transcription", "video",
        ]
        models = try container.decode([GatewayLanguageModelEntry].self, forKey: .models).filter {
            $0.modelType.map(knownTypes.contains) ?? true
        }
    }
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
            let headers = try await resolve(config.headers)
            let team = headers.first { $0.key.lowercased() == "x-vercel-ai-gateway-team" }?
                .value?.trimmingCharacters(in: .whitespacesAndNewlines)
            let queryItems: [URLQueryItem]
            if let team, !team.isEmpty {
                queryItems = [.init(name: team.hasPrefix("team_") ? "teamId" : "slug", value: team)]
            } else {
                queryItems = []
            }
            let result = try await getFromAPI(
                url: gatewayAPIURL(baseURL: config.baseURL, path: "/v1/credits", queryItems: queryItems),
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

func gatewayAPIURL(baseURL: String, path: String, queryItems: [URLQueryItem] = [], formEncoding: Bool = true) throws -> String {
    guard var components = URLComponents(string: baseURL), components.scheme != nil, components.host != nil else {
        throw APICallError(message: "Invalid base URL", url: baseURL, requestBodyValues: nil)
    }
    components.user = nil
    components.password = nil
    components.path = path
    components.fragment = nil
    let allowed = CharacterSet(charactersIn: formEncoding
        ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._"
        : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    func encode(_ value: String) -> String {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return formEncoding ? encoded.replacingOccurrences(of: "%20", with: "+") : encoded
    }
    components.percentEncodedQuery = queryItems.isEmpty ? nil : queryItems.map {
        "\(encode($0.name))=\(encode($0.value ?? ""))"
    }.joined(separator: "&")
    guard let url = components.string else {
        throw APICallError(message: "Invalid base URL", url: baseURL, requestBodyValues: nil)
    }
    return url
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
