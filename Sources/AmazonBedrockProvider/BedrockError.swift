import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private struct BedrockErrorPayload: Codable, Sendable {
    let message: String
    let type: String?
}

private let bedrockErrorSchema = FlexibleSchema(
    Schema.codable(
        BedrockErrorPayload.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public let bedrockFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: bedrockErrorSchema,
    errorToMessage: { error in
        if let type = error.type {
            return "\(type): \(error.message)"
        }
        return error.message
    }
)
