import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gladia/src/gladia-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GladiaErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let message: String
        public let code: Int
    }

    public let error: ErrorPayload
}

private let gladiaErrorJSONSchema: JSONValue = .object([
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
                "code": .object(["type": .string("number")])
            ])
        ])
    ])
])

public let gladiaFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<GladiaErrorData>.codable(
            GladiaErrorData.self,
            jsonSchema: gladiaErrorJSONSchema
        )
    ),
    errorToMessage: { $0.error.message }
)
