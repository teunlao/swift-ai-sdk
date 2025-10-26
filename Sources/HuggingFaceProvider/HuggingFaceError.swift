import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/huggingface-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct HuggingFaceErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let message: String
        public let type: String?
        public let code: String?
    }

    public let error: ErrorPayload
}

private let huggingfaceErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(true),
    "properties": .object([
        "error": .object([
            "type": .string("object"),
            "required": .array([.string("message")]),
            "additionalProperties": .bool(true),
            "properties": .object([
                "message": .object(["type": .string("string")]),
                "type": .object(["type": .array([.string("string"), .string("null")])]),
                "code": .object(["type": .array([.string("string"), .string("null")])])
            ])
        ])
    ])
])

public let huggingfaceFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<HuggingFaceErrorData>.codable(
            HuggingFaceErrorData.self,
            jsonSchema: huggingfaceErrorJSONSchema
        )
    ),
    errorToMessage: { $0.error.message }
)
