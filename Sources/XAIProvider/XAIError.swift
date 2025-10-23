import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

/// Error payload returned by the xAI APIs.
/// Mirrors `packages/xai/src/xai-error.ts`.
public struct XAIErrorData: Sendable, Equatable, Codable {
    public struct ErrorBody: Sendable, Equatable, Codable {
        public let message: String
        public let type: String?
        public let param: JSONValue?
        public let code: XAIErrorCode?

        enum CodingKeys: String, CodingKey {
            case message
            case type
            case param
            case code
        }
    }

    public let error: ErrorBody
}

/// Union type representing either a string or numeric error code.
public enum XAIErrorCode: Sendable, Equatable {
    case string(String)
    case number(Double)
}

extension XAIErrorCode: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported xAI error code value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        }
    }
}

private let xaiErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "error": .object([
            "type": .string("object"),
            "required": .array([.string("message")]),
            "additionalProperties": .bool(true),
            "properties": .object([
                "message": .object(["type": .string("string")]),
                "type": .bool(true),
                "param": .bool(true),
                "code": .bool(true)
            ])
        ])
    ])
])

public let xaiErrorDataSchema = FlexibleSchema(
    Schema<XAIErrorData>.codable(
        XAIErrorData.self,
        jsonSchema: xaiErrorJSONSchema
    )
)

public let xaiFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: xaiErrorDataSchema,
    errorToMessage: { $0.error.message }
)

private let xaiErrorJSONEncoder = JSONEncoder()
private let xaiErrorJSONDecoder = JSONDecoder()

private func extractXAIErrorMessage(from json: JSONValue) throws -> String {
    let data = try xaiErrorJSONEncoder.encode(json)
    let payload = try xaiErrorJSONDecoder.decode(XAIErrorData.self, from: data)
    return payload.error.message
}

public let xaiErrorConfiguration = OpenAICompatibleErrorConfiguration(
    failedResponseHandler: xaiFailedResponseHandler,
    extractMessage: extractXAIErrorMessage
)
