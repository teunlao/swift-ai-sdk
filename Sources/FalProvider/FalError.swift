import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-error.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

public struct FalErrorData: Codable, Sendable {
    public struct ErrorBody: Codable, Sendable {
        public let message: String
        public let code: Double
    }

    public let error: ErrorBody
}

private let falErrorJSONSchema: JSONValue = .object([
    "type": .string("object")
])

public let falFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<FalErrorData>.codable(
            FalErrorData.self,
            jsonSchema: falErrorJSONSchema
        )
    ),
    errorToMessage: { $0.error.message }
)
