import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct CohereErrorData: Codable, Sendable {
    public let message: String
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

public let cohereFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<CohereErrorData>.codable(
            CohereErrorData.self,
            jsonSchema: genericJSONObjectSchema
        )
    ),
    errorToMessage: { $0.message }
)
