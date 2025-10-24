import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

/// Baseten error payload (mirrors `packages/baseten/src/baseten-provider.ts`).
public struct BasetenErrorData: Codable, Sendable, Equatable {
    public let error: String
}

private let basetenErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "error": .object(["type": .string("string")])
    ])
])

private let basetenErrorSchema = FlexibleSchema(
    Schema<BasetenErrorData>.codable(
        BasetenErrorData.self,
        jsonSchema: basetenErrorJSONSchema
    )
)

private struct BasetenErrorExtractionFailure: Error {}

private func extractBasetenErrorMessage(from value: JSONValue) throws -> String {
    guard case .object(let object) = value,
          let errorValue = object["error"],
          case .string(let message) = errorValue else {
        throw BasetenErrorExtractionFailure()
    }
    return message
}

public let basetenErrorConfiguration = OpenAICompatibleErrorConfiguration(
    failedResponseHandler: createJsonErrorResponseHandler(
        errorSchema: basetenErrorSchema,
        errorToMessage: { (data: BasetenErrorData) in data.error }
    ),
    extractMessage: extractBasetenErrorMessage
)
