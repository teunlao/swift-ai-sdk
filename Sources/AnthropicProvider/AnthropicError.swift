import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let type: String
        public let message: String

        public init(type: String, message: String) {
            self.type = type
            self.message = message
        }
    }

    public let type: String
    public let error: ErrorPayload

    public init(type: String = "error", error: ErrorPayload) {
        self.type = type
        self.error = error
    }

    enum CodingKeys: String, CodingKey { case type, error }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        guard type == "error" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected error response")
        }
        error = try container.decode(ErrorPayload.self, forKey: .error)
    }
}

private let anthropicErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("type"), .string("error")]),
    "properties": .object([
        "type": .object([
            "type": .string("string")
        ]),
        "error": .object([
            "type": .string("object"),
            "required": .array([.string("type"), .string("message")]),
            "properties": .object([
                "type": .object(["type": .string("string")]),
                "message": .object(["type": .string("string")])
            ]),
            "additionalProperties": .bool(true)
        ])
    ]),
    "additionalProperties": .bool(true)
])

public let anthropicErrorDataSchema = FlexibleSchema(
    Schema<AnthropicErrorData>.codable(
        AnthropicErrorData.self,
        jsonSchema: anthropicErrorJSONSchema
    )
)

public let anthropicFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: anthropicErrorDataSchema,
    errorToMessage: { $0.error.message }
)

func createAnthropicStreamError(_ error: StreamError.Payload) -> ProviderStreamError {
    let inferred: (Int?, Bool?)
    switch error.type {
    case "api_error": inferred = (500, true)
    case "overloaded_error": inferred = (529, true)
    case "rate_limit_error": inferred = (429, true)
    case "request_too_large": inferred = (413, false)
    case "authentication_error": inferred = (401, false)
    case "permission_error": inferred = (403, false)
    case "not_found_error": inferred = (404, false)
    case "billing_error", "invalid_request_error": inferred = (400, false)
    default: inferred = (nil, nil)
    }
    let code: ProviderStreamError.Code? = switch error.code {
    case .string(let value): .string(value)
    case .number(let value): .number(value)
    default: nil
    }
    return createProviderStreamError(
        message: error.message, type: error.type, code: code,
        statusCode: error.statusCode ?? inferred.0, isRetryable: error.isRetryable ?? inferred.1,
        data: error.data ?? error.jsonValue
    )
}
