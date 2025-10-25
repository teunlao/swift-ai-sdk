import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct MistralErrorData: Codable, Sendable {
    public let object: String
    public let message: String
    public let type: String
    public let param: String?
    public let code: String?
}

private let genericJSONObjectSchema: JSONValue = .object([
    "type": .string("object")
])

public let mistralFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<MistralErrorData>.codable(
            MistralErrorData.self,
            jsonSchema: genericJSONObjectSchema
        )
    ),
    errorToMessage: { $0.message }
)
