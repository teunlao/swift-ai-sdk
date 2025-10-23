import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

/// Cerebras error payload structure.
/// Mirrors `packages/cerebras/src/cerebras-provider.ts` error schema.
public struct CerebrasErrorData: Codable, Sendable, Equatable {
    public struct ErrorPayload: Codable, Sendable, Equatable {
        public let message: String
        public let type: String
        public let param: String
        public let code: String
    }

    public let error: ErrorPayload
}

private let cerebrasErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "error": .object([
            "type": .string("object"),
            "required": .array([
                .string("message"),
                .string("type"),
                .string("param"),
                .string("code")
            ]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "message": .object(["type": .string("string")]),
                "type": .object(["type": .string("string")]),
                "param": .object(["type": .string("string")]),
                "code": .object(["type": .string("string")])
            ])
        ])
    ])
])

private let cerebrasErrorSchema = FlexibleSchema(
    Schema<CerebrasErrorData>.codable(
        CerebrasErrorData.self,
        jsonSchema: cerebrasErrorJSONSchema
    )
)

private struct CerebrasErrorExtraction: Error {}

private func extractCerebrasMessage(from json: JSONValue) throws -> String {
    guard case .object(let root) = json,
          let errorValue = root["error"],
          case .object(let errorObject) = errorValue,
          let messageValue = errorObject["message"],
          case .string(let message) = messageValue else {
        throw CerebrasErrorExtraction()
    }
    return message
}

public let cerebrasErrorConfiguration = OpenAICompatibleErrorConfiguration(
    failedResponseHandler: createJsonErrorResponseHandler(
        errorSchema: cerebrasErrorSchema,
        errorToMessage: { $0.error.message }
    ),
    extractMessage: extractCerebrasMessage
)
