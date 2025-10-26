import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private struct GoogleVertexErrorBody: Codable, Sendable {
    let code: Int?
    let message: String
    let status: String
}

private struct GoogleVertexErrorData: Codable, Sendable {
    let error: GoogleVertexErrorBody
}

private let googleVertexErrorSchema = FlexibleSchema(
    Schema.codable(
        GoogleVertexErrorData.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public let googleVertexFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: googleVertexErrorSchema,
    errorToMessage: { data in data.error.message }
)
