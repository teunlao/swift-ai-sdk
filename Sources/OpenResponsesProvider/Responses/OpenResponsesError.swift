import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/open-responses/src/responses/open-responses-api.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

/// Codable representation of Open Responses error payloads.
/// Mirrors `openResponsesErrorSchema` from `packages/open-responses/src/responses/open-responses-api.ts`.
public struct OpenResponsesErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let message: String
        public let type: String
        public let param: String
        public let code: String

        public init(message: String, type: String, param: String, code: String) {
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

private let openResponsesErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "error": .object([
            "type": .string("object"),
            "required": .array([.string("message"), .string("type"), .string("param"), .string("code")]),
            // Zod object defaults to stripping unknown keys; allow them to avoid over-strict validation.
            "additionalProperties": .bool(true),
            "properties": .object([
                "message": .object(["type": .string("string")]),
                "type": .object(["type": .string("string")]),
                "param": .object(["type": .string("string")]),
                "code": .object(["type": .string("string")])
            ])
        ])
    ])
])

public let openResponsesErrorDataSchema = FlexibleSchema(
    Schema<OpenResponsesErrorData>.codable(
        OpenResponsesErrorData.self,
        jsonSchema: openResponsesErrorJSONSchema
    )
)

public let openResponsesFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: openResponsesErrorDataSchema,
    errorToMessage: { $0.error.message }
)

