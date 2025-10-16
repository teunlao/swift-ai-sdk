import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GenerateObjectResult<ResultValue: Sendable>: Sendable {
    public let object: ResultValue
    public let reasoning: String?
    public let finishReason: FinishReason
    public let usage: LanguageModelUsage
    public let warnings: [CallWarning]?
    public let request: LanguageModelRequestMetadata
    public let response: LanguageModelResponseMetadataWithBody
    public let providerMetadata: ProviderMetadata?

    public init(
        object: ResultValue,
        reasoning: String?,
        finishReason: FinishReason,
        usage: LanguageModelUsage,
        warnings: [CallWarning]?,
        request: LanguageModelRequestMetadata,
        response: LanguageModelResponseMetadataWithBody,
        providerMetadata: ProviderMetadata?
    ) {
        self.object = object
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.warnings = warnings
        self.request = request
        self.response = response
        self.providerMetadata = providerMetadata
    }

    public func toJsonResponse(
        status: Int = 200,
        headers: [String: String]? = nil
    ) -> JSONHTTPResponse {
        let mergedHeaders = prepareHeaders(headers, defaultHeaders: ["content-type": "application/json; charset=utf-8"])
        let body = encodeJSONBody(object)
        return JSONHTTPResponse(status: status, headers: mergedHeaders, body: body)
    }
}

public struct LanguageModelResponseMetadataWithBody: Sendable {
    public let id: String
    public let timestamp: Date
    public let modelId: String
    public let headers: [String: String]?
    public let body: JSONValue?

    public init(
        id: String,
        timestamp: Date,
        modelId: String,
        headers: [String: String]?,
        body: JSONValue?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.body = body
    }
}

public struct JSONHTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

private func encodeJSONBody<ResultValue>(_ object: ResultValue) -> Data {
    if let jsonValue = object as? JSONValue {
        return (try? JSONEncoder().encode(jsonValue)) ?? Data(String(describing: jsonValue).utf8)
    }

    if let dictionary = object as? [String: JSONValue] {
        return encodeJSONObject(dictionary.mapValues { $0 })
    }

    if let array = object as? [JSONValue] {
        return encodeJSONObject(array)
    }

    if let jsonValue = try? jsonValue(from: object) {
        return (try? JSONEncoder().encode(jsonValue)) ?? Data(String(describing: jsonValue).utf8)
    }

    if let encodable = object as? Encodable {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(AnyEncodableBox(encodable)) {
            return data
        }
    }

    return Data(String(describing: object).utf8)
}

private func encodeJSONObject(_ value: Any) -> Data {
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: []) {
        return data
    }
    return Data(String(describing: value).utf8)
}

private struct AnyEncodableBox: Encodable {
    private let value: Encodable

    init(_ value: Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
