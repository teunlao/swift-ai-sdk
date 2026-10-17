import Foundation
import AISDKProvider
import AISDKProviderUtils

func gatewayJSON<T: Encodable>(_ value: T) throws -> JSONValue {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
}

func gatewaySchema<T: Decodable & Sendable>(_ type: T.Type) -> FlexibleSchema<T> {
    FlexibleSchema(Schema<T>.codable(type, jsonSchema: .object(["type": .string("object")]), configureDecoder: { decoder in
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Gateway timestamp")
        }
        return decoder
    }))
}

struct GatewayModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
    var currentDate: @Sendable () -> Date = { Date() }

    func post<T: Decodable & Sendable>(
        _ endpoint: String,
        modelId: String,
        body: JSONValue,
        headers callHeaders: SharedV4Headers?,
        abortSignal: (@Sendable () -> Bool)?,
        response: T.Type
    ) async throws -> ResponseHandlerResult<T> {
        let resolved = try await headers()
        do {
            return try await postJsonToAPI(
                url: "\(baseURL)/\(endpoint)-model",
                headers: combineHeaders(
                    resolved,
                    callHeaders?.mapValues { Optional($0) },
                    ["ai-\(endpoint)-model-specification-version": "4", "ai-model-id": modelId],
                    try await o11yHeaders()
                ).compactMapValues { $0 },
                body: body,
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewaySchema(response)),
                isAborted: abortSignal,
                fetch: fetch
            )
        } catch {
            throw asGatewayError(error, authMethod: parseAuthMethod(from: resolved.compactMapValues { $0 }))
        }
    }
}

struct GatewayConfig: Sendable {
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
}

struct GatewayLanguageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
}

struct GatewayEmbeddingModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
}

struct GatewayImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
}

struct GatewayVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let o11yHeaders: @Sendable () async throws -> [String: String?]
}
