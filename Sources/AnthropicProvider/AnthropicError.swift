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
