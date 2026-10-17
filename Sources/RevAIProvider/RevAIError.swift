import Foundation
import AISDKProvider
import AISDKProviderUtils

// Port of packages/revai/src/revai-error.ts.

struct RevAIErrorData: Codable, Sendable, Equatable {
    struct ErrorPayload: Codable, Sendable, Equatable {
        let message: String
        let code: Double
    }

    let error: ErrorPayload
}

private let revaiErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(true),
    "properties": .object([
        "error": .object([
            "type": .string("object"),
            "required": .array([.string("message"), .string("code")]),
            "additionalProperties": .bool(true),
            "properties": .object([
                "message": .object(["type": .string("string")]),
                "code": .object(["type": .string("number")]),
            ]),
        ]),
    ]),
])

let revaiErrorDataSchema = FlexibleSchema(
    Schema<RevAIErrorData>.codable(
        RevAIErrorData.self,
        jsonSchema: revaiErrorJSONSchema
    )
)

let revaiFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: revaiErrorDataSchema,
    errorToMessage: { $0.error.message }
)

