import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepgram/src/deepgram-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct DeepgramErrorData: Codable, Sendable {
    public struct ErrorBody: Codable, Sendable {
        public let message: String
        public let code: Int
    }

    public let error: ErrorBody
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

public let deepgramFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<DeepgramErrorData>.codable(
            DeepgramErrorData.self,
            jsonSchema: genericJSONObjectSchema
        )
    ),
    errorToMessage: { $0.error.message }
)
