import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct FalErrorPayload: Codable, Sendable {
    public struct ErrorBody: Codable, Sendable {
        public let message: String
        public let code: Int
    }

    public let error: ErrorBody
}

private let falErrorJSONSchema: JSONValue = .object([
    "type": .string("object")
])

public let falFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<FalErrorPayload>.codable(
            FalErrorPayload.self,
            jsonSchema: falErrorJSONSchema
        )
    ),
    errorToMessage: { $0.error.message }
)
