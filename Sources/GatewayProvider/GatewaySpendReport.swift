import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum GatewayCredentialType: String, Sendable, Codable {
    case byok, system
}

public struct GatewaySpendReportParams: Sendable {
    public enum GroupBy: String, Sendable { case day, user, model, tag, provider, credentialType = "credential_type" }
    public enum DatePart: String, Sendable { case day, hour }

    public let startDate: String
    public let endDate: String
    public let groupBy: GroupBy?
    public let datePart: DatePart?
    public let userId: String?
    public let model: String?
    public let provider: String?
    public let credentialType: GatewayCredentialType?
    public let tags: [String]?

    public init(
        startDate: String,
        endDate: String,
        groupBy: GroupBy? = nil,
        datePart: DatePart? = nil,
        userId: String? = nil,
        model: String? = nil,
        provider: String? = nil,
        credentialType: GatewayCredentialType? = nil,
        tags: [String]? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.groupBy = groupBy
        self.datePart = datePart
        self.userId = userId
        self.model = model
        self.provider = provider
        self.credentialType = credentialType
        self.tags = tags
    }
}

public struct GatewaySpendReportRow: Sendable, Decodable {
    public let day: String?
    public let hour: String?
    public let user: String?
    public let model: String?
    public let tag: String?
    public let provider: String?
    public let credentialType: GatewayCredentialType?
    public let totalCost: Double
    public let marketCost: Double?
    public let inputTokens: Double?
    public let outputTokens: Double?
    public let cachedInputTokens: Double?
    public let cacheCreationInputTokens: Double?
    public let reasoningTokens: Double?
    public let requestCount: Double?
}

public struct GatewaySpendReportResponse: Sendable, Decodable {
    public let results: [GatewaySpendReportRow]
}

struct GatewaySpendReport: Sendable {
    let config: GatewayConfig

    func getSpendReport(_ params: GatewaySpendReportParams) async throws -> GatewaySpendReportResponse {
        do {
            var query = [
                URLQueryItem(name: "start_date", value: params.startDate),
                URLQueryItem(name: "end_date", value: params.endDate),
            ]
            let filters: [(String, String?)] = [
                ("group_by", params.groupBy?.rawValue), ("date_part", params.datePart?.rawValue),
                ("user_id", params.userId), ("model", params.model), ("provider", params.provider),
                ("credential_type", params.credentialType?.rawValue),
            ]
            query += filters.compactMap { name, value in
                value.flatMap { $0.isEmpty ? nil : URLQueryItem(name: name, value: $0) }
            }
            if let tags = params.tags, !tags.isEmpty {
                query.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
            }
            let result = try await getFromAPI(
                url: gatewayAPIURL(baseURL: config.baseURL, path: "/v1/report", queryItems: query),
                headers: try await resolve(config.headers).compactMapValues { $0 },
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewaySpendReportSchema),
                fetch: config.fetch
            )
            return result.value
        } catch {
            throw asGatewayError(error)
        }
    }
}

private let gatewaySpendReportSchema = FlexibleSchema(
    Schema<GatewaySpendReportResponse>.codable(
        GatewaySpendReportResponse.self,
        jsonSchema: .object(["type": .string("object")]),
        configureDecoder: { decoder in
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    )
)
