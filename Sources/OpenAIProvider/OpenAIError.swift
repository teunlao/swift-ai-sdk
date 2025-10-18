import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Codable representation of OpenAI error payloads.
/// Mirrors the structure defined in `openai-error.ts`.
public struct OpenAIErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let message: String
        public let type: String?
        public let param: JSONValue?
        public let code: OpenAIErrorCode?

        public init(
            message: String,
            type: String? = nil,
            param: JSONValue? = nil,
            code: OpenAIErrorCode? = nil
        ) {
            self.message = message
            self.type = type
            self.param = param
            self.code = code
        }
    }

    public let error: ErrorPayload

    public init(error: ErrorPayload) {
        self.error = error
    }
}

/// Union type representing either a string or numeric error code.
public enum OpenAIErrorCode: Sendable, Equatable {
    case string(String)
    case number(Double)
}

extension OpenAIErrorCode: Codable {
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
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported OpenAI error code value")
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

private let openAIErrorJSONSchema: JSONValue = .object([
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
                "type": .object(["type": .array([.string("string"), .string("null")])]),
                "param": .bool(true),
                "code": .object(["type": .array([.string("string"), .string("number"), .string("null")])])
            ])
        ])
    ])
])

public let openAIErrorDataSchema = FlexibleSchema(
    Schema<OpenAIErrorData>.codable(
        OpenAIErrorData.self,
        jsonSchema: openAIErrorJSONSchema
    )
)

public let openAIFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: openAIErrorDataSchema,
    errorToMessage: { $0.error.message }
)
