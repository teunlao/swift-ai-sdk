import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fireworks/src/fireworks-provider.ts (error handling)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Fireworks API error payload (mirrors `packages/fireworks/src/fireworks-provider.ts`).
public struct FireworksErrorData: Codable, Sendable, Equatable {
    public let error: String
}

private let fireworksErrorJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "required": .array([.string("error")]),
    "additionalProperties": .bool(false),
    "properties": .object([
        "error": .object(["type": .string("string")])
    ])
])

private let fireworksErrorSchema = FlexibleSchema(
    Schema<FireworksErrorData>.codable(
        FireworksErrorData.self,
        jsonSchema: fireworksErrorJSONSchema
    )
)

private struct FireworksErrorExtractionFailure: Error {}

private func extractFireworksErrorMessage(from value: JSONValue) throws -> String {
    guard case .object(let object) = value,
          let errorValue = object["error"],
          case .string(let message) = errorValue else {
        throw FireworksErrorExtractionFailure()
    }
    return message
}

/// Error configuration for Fireworks OpenAI-compatible endpoints.
public let fireworksErrorConfiguration = OpenAICompatibleErrorConfiguration(
    failedResponseHandler: createJsonErrorResponseHandler(
        errorSchema: fireworksErrorSchema,
        errorToMessage: { (data: FireworksErrorData) in data.error }
    ),
    extractMessage: extractFireworksErrorMessage
)
