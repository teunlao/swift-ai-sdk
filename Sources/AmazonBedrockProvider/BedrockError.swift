import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-error.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

struct BedrockErrorPayload: Codable, Sendable {
    let message: String
    let type: String?
}

let BedrockErrorSchema = FlexibleSchema(
    Schema.codable(
        BedrockErrorPayload.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public let bedrockFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: BedrockErrorSchema,
    errorToMessage: { error in
        if let type = error.type {
            return "\(type): \(error.message)"
        }
        return error.message
    }
)
