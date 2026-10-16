import Foundation
import AISDKProvider
import AISDKProviderUtils

let bflFailureStatuses: Set<String> = ["Content Moderated", "Error", "Failed", "Request Moderated", "Task not found"]

struct BFLSubmitResponse: Decodable, Sendable {
    let id: String
    let polling_url: String
    let cost: Double?
    let input_mp: Double?
    let output_mp: Double?
}

let bflSubmitSchema = FlexibleSchema(Schema<BFLSubmitResponse>(
    jsonSchemaResolver: { .object(["type": .string("object")]) },
    validator: { value in
        do {
            let json = try jsonValue(from: value)
            let result = try JSONDecoder().decode(BFLSubmitResponse.self, from: JSONEncoder().encode(json))
            guard let url = URL(string: result.polling_url), url.scheme != nil else { throw InvalidResponseDataError(data: value) }
            return .success(value: result)
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

struct BFLPollResponse: Decodable, Sendable {
    let status: String
    let details: JSONValue?
    let result: JSONValue?
    let cost: Double?
    private enum CodingKeys: String, CodingKey { case status, state, details, result, cost }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = container.contains(.status) ? try container.decode(String.self, forKey: .status) : nil
        let state = container.contains(.state) ? try container.decode(String.self, forKey: .state) : nil
        guard let value = status ?? state else {
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Missing status in Black Forest Labs poll response")
        }
        self.status = value
        details = try container.decodeIfPresent(JSONValue.self, forKey: .details)
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
    }
}

let bflVideoPollSchema = FlexibleSchema(Schema<BFLPollResponse>.codable(BFLPollResponse.self, jsonSchema: .object(["type": .string("object")])))

struct BFLErrorPayload: Decodable, Sendable {
    let message: String?
    let detail: JSONValue?
    let status: String?
    let state: String?
    private enum CodingKeys: String, CodingKey { case message, detail, status, state }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        message = values.contains(.message) ? try values.decode(String.self, forKey: .message) : nil
        detail = try values.decodeIfPresent(JSONValue.self, forKey: .detail)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        state = try values.decodeIfPresent(String.self, forKey: .state)
    }
}

let bflFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<BFLErrorPayload>.codable(BFLErrorPayload.self, jsonSchema: .object(["type": .string("object")]))),
    errorToMessage: { payload in
        if let detail = payload.detail, detail != .null { return bflDescribe(detail) }
        if let message = payload.message { return message }
        if let status = payload.status ?? payload.state { return "Black Forest Labs generation failed: \(status)." }
        return "Unknown Black Forest Labs error"
    },
    isRetryable: { response, payload in
        if let status = payload?.status ?? payload?.state, bflFailureStatuses.contains(status) { return false }
        return [408, 409, 429].contains(response.statusCode) || response.statusCode >= 500
    }
)

func bflDescribe(_ value: JSONValue) -> String {
    if case .string(let value) = value { return value }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "null"
}

func bflTrustedURL(_ url: String, baseURL: String) -> Bool {
    if isSameOrigin(url, baseURL) { return true }
    guard let components = URLComponents(string: url), components.scheme?.lowercased() == "https", let host = components.host?.lowercased() else { return false }
    return host == "bfl.ai" || host.hasSuffix(".bfl.ai")
}

func bflPollingURL(_ url: String, id: String) throws -> String {
    guard var components = URLComponents(string: url), components.scheme != nil else { throw InvalidResponseDataError(data: url) }
    if components.queryItems?.contains(where: { $0.name == "id" }) != true {
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "id", value: id)]
    }
    guard let result = components.url?.absoluteString else { throw InvalidResponseDataError(data: url) }
    return result
}

func bflFile(_ file: ImageModelV4File) -> String {
    switch file {
    case .url(let url, _): return url
    case .file(_, let data, _):
        switch data {
        case .base64(let value): return value
        case .binary(let value): return value.base64EncodedString()
        }
    }
}

func bflFile(_ file: VideoModelV4File) -> String {
    switch file {
    case .url(let url, _, _): return url
    case .file(_, let data, _):
        switch data {
        case .base64(let value): return value
        case .binary(let value): return value.base64EncodedString()
        }
    }
}

func bflNumber(_ value: JSONValue?) -> Double? {
    if case .number(let value) = value { return value }
    return nil
}

func bflString(_ value: JSONValue?) -> String? {
    if case .string(let value) = value { return value }
    return nil
}

struct BFLVideoError: AISDKError, Sendable {
    static let errorDomain = "black-forest-labs.video.error"
    let name: String
    let message: String
    let cause: (any Error)? = nil
}
